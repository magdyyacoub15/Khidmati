import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import 'stats_page.dart';
import 'statuses_page.dart';
import 'profile_page.dart';
import '../services/ai_insight_service.dart';
import '../models/kid.dart';
import '../services/notification_service.dart';
import '../services/data_cache_service.dart';
import '../services/appwrite_service.dart';
import 'individual_visited_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  String _myGroupId = '';
  String? _userRole;
  AIInsightService? _insightService;
  List<AIInsight> _myInsights = [];
  bool _isInsightLoading = false;
  bool _isPendingApproval = false; // 🚀 User is waiting for admin approval
  bool _hasCheckedBirthdays = false; // Session-based check
  bool _hasScheduledInsights = false; // Session-based check for insights

  final Account _account = AppwriteService().account;
  final Databases _databases = AppwriteService().databases;
  late Realtime _realtime;
  RealtimeSubscription? _subscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  final List<String> _dailyVerses = const [
    "\"الْحَقَّ أَقُولُ لَكُمْ: بِمَا أَنكُمْ فَعَلْتُمُوهُ بِأَحَدِ إِخْوَتِي هؤُلاَءِ الأَصَاغِرِ، فَبِي فَعَلْتُمْْ\" (متى 25: 40)",
    "\"ارْعَوْا رَعِيَّةَ اللهِ الَّتِي بَيْنَكُمْ نُظَّارًا، لاَ عَنِ اضْطِرَارٍ بَلْ بِالاخْتِيَارِ، وَلاَ لِرِبْحٍ قَبِيحٍ بَلْ بِنَشَاطٍِ\" (1 بطرس 5: 2)",
  ];

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
    _setupAppwriteListener();
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  Future<void> _setupAppwriteListener() async {
    try {
      // 🚀 1. Load from Cache First (Instant)
      final cachedData = await DataCacheService().getCachedUserData();
      if (cachedData != null && mounted) {
        _updateLocalState(cachedData);
      }

      final user = await _account.get();

      // 2. Fetch Fresh Data (User Info)
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      // 2b. Fetch Membership for Role
      final activeGroupId = doc.data['groupId'] ?? '';
      String? groupRole;
      String? groupStatus; // 🚀 حقل الحالة الجديد

      if (activeGroupId.isNotEmpty) {
        try {
          final membershipRes = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: AppwriteService.membershipsCollectionId,
            queries: [
              Query.equal('userId', user.$id),
              Query.equal('groupId', activeGroupId),
            ],
          );
          if (membershipRes.total > 0) {
            final membership = membershipRes.documents.first;
            groupRole = membership.data['role'];
            groupStatus = membership.data['status']; // 🚀 جلب الحالة من العضوية
            if (mounted) {
              setState(() {
                _isPendingApproval = groupStatus == 'pending';
              });
            }
          } else {
            // 🚨 SELF-HEALING: GroupId exists in users_info but no membership found.
            // This user was deleted from the group.
            debugPrint(
              "🚨 No membership found for active group. Forcing logout...",
            );

            // Clear groupId in users_info to prevent loop on next login
            try {
              await _databases.updateDocument(
                databaseId: databaseId,
                collectionId: usersCollectionId,
                documentId: user.$id,
                data: {'groupId': ''},
              );
            } catch (e) {
              debugPrint("Silent error clearing orphaned groupId: $e");
            }

            _handleForcedLogout();
            return;
          }
        } catch (e) {
          debugPrint("⚠️ Membership query failed: $e");
        }
      }

      final combinedData = {
        ...doc.data,
        if (groupRole != null) 'role': groupRole,
        if (groupStatus != null)
          'status': groupStatus, // 🚀 تخزين الحالة في الكاش
        'groupId': activeGroupId,
      };

      // Save to Cache & Update UI
      if (mounted) {
        await DataCacheService().cacheUserData(combinedData);
        _updateLocalState(combinedData, isInitialLoad: false); // 🚀 تمرير flag
      }

      // 3. User Info Realtime Listener
      _subscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);

      _subscription!.stream.listen((event) {
        if (mounted) {
          _updateLocalState(event.payload);
          DataCacheService().cacheUserData(event.payload);
        }
      });

      // 4. Membership Realtime Listener (FOR APPROVAL SYNC) 🚀
      if (activeGroupId.isNotEmpty) {
        final membershipSubscription = _realtime.subscribe([
          'databases.$databaseId.collections.${AppwriteService.membershipsCollectionId}.documents',
        ]);

        membershipSubscription.stream.listen((event) {
          final payload = event.payload;
          if (payload['userId'] == user.$id &&
              payload['groupId'] == activeGroupId) {
            final newStatus = payload['status'];
            final wasPending = _isPendingApproval;
            final isNowApproved = newStatus == 'approved';

            if (mounted && wasPending && isNowApproved) {
              setState(() {
                _isPendingApproval = false;
              });
              _syncData(); // 🚀 Instant sync upon approval!
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "🎉 تم قبول طلب انضمامك! يمكنك الآن استخدام جميع المميزات.",
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        });
      }
    } catch (e) {
      debugPrint("❌ Dashboard Appwrite Setup Error: $e");
      // ⚡ FIX: Only logout if unauthorized (401), ignore network errors
      if (e is AppwriteException && e.code == 401) {
        _handleForcedLogout();
      }
    }
  }

  void _updateLocalState(
    Map<String, dynamic> data, {
    bool isInitialLoad = true,
  }) {
    if (!mounted || data.isEmpty) {
      return; // 🛡️ Safety check against empty payloads
    }

    final newGroupId = data['groupId'] ?? '';
    final newRole = data['role'] as String?;

    if (newGroupId != _myGroupId ||
        newRole != _userRole ||
        data.containsKey('status')) {
      // 🚨 إذا تم حذف المستخدم من المجموعة (groupId أصبح فارغاً) وكان في مجموعة سابقاً
      if ((newGroupId.isEmpty) && (_myGroupId.isNotEmpty)) {
        debugPrint("User has no active group. Logging out...");
        _handleForcedLogout();
        return;
      }

      setState(() {
        // 🛡️ SECURITY: Only force pending if it's a real group change during session
        // If it's initial load from cache, respect the cached status.
        bool realGroupChange =
            !isInitialLoad && newGroupId != _myGroupId && newGroupId.isNotEmpty;

        _myGroupId = newGroupId;
        _userRole = newRole;

        if (realGroupChange) {
          _isPendingApproval =
              (newRole != 'admin'); // 🛡️ Admins are never pending
        } else if (data.containsKey('status')) {
          _isPendingApproval =
              (data['status'] == 'pending') && (newRole != 'admin');
        } else {
          // Default fallbacks if status is missing
          _isPendingApproval =
              (newRole != 'admin' &&
              newGroupId.isNotEmpty &&
              (data['status'] == 'pending'));
        }
      });

      // Logic moved out of setState to avoid build-time errors
      if (_myGroupId.isNotEmpty) {
        if (_insightService == null || _insightService!.groupId != _myGroupId) {
          _insightService = AIInsightService(groupId: _myGroupId);
          _listenToInsights();
          _syncData(); // مزامنة البيانات والجدولة
        }
      }
    }
  }

  Future<void> _syncData() async {
    if (_myGroupId.isEmpty) return;
    try {
      // 1. Fetch Students
      final studentsResult = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'students',
        queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
      );
      final studentKids = studentsResult.documents
          .map((d) => Kid.fromAppwrite(d))
          .toList();

      // 2. Fetch Servants
      final servantsResult = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'servants',
        queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
      );
      final servantKids = servantsResult.documents.map((d) {
        // Map servant data to Kid model for consistency in birthday checks
        return Kid(
          id: d.$id,
          name: d.data['name'] ?? '',
          address: d.data['address'] ?? '',
          phoneRequired: d.data['phone'],
          phoneRequiredOwner: d.data['phoneOwner'],
          dateOfBirth: d.data['dateOfBirth'] != null
              ? DateTime.tryParse(d.data['dateOfBirth'])
              : null,
          grade: 'خادم',
        );
      }).toList();

      final allKids = [...studentKids, ...servantKids];

      // 3. Sync with Notification Service (System level)
      await NotificationService().syncAllBirthdays(allKids);

      // 4. Show Birthday Alert (UI Popup - once per session)
      if (!_hasCheckedBirthdays) {
        _hasCheckedBirthdays = true;
        final birthdaysToday = allKids
            .where((k) => k.isBirthdayToday())
            .toList();
        if (birthdaysToday.isNotEmpty && mounted) {
          _showBirthdayAlert(birthdaysToday);
        }
      }

      // 5. Generate AI Insights (once per day, for all users)
      if (_insightService != null && !_hasScheduledInsights) {
        _hasScheduledInsights = true;
        await _generateDailyInsights();
        await _insightService!.schedulePendingNotifications();
      }
    } catch (e) {
      debugPrint("⚠️ Sync Data Error: $e");
    }
  }

  /// Generate AI insights once per day (on first app open)
  Future<void> _generateDailyInsights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month}-${today.day}';
      final lastGenerated = prefs.getString(
        'last_insights_generated_$_myGroupId',
      );

      // Only generate if not already done today
      if (lastGenerated != todayStr) {
        debugPrint('🔄 Generating daily AI insights for group $_myGroupId...');
        await _insightService!.generateInsights();
        await prefs.setString('last_insights_generated_$_myGroupId', todayStr);
        debugPrint('✅ AI insights generated successfully');
      } else {
        debugPrint('✓ AI insights already generated today');
      }
    } catch (e) {
      debugPrint('❌ Error generating daily insights: $e');
    }
  }

  void _showBirthdayAlert(List<Kid> birthdayKids) {
    final randomVerse = _dailyVerses[Random().nextInt(_dailyVerses.length)];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true, // Added
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Text(
              "🎉 أعياد ميلاد اليوم! 🎉",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Divider(),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Text(
                randomVerse,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "احتفل بعيد ميلاد أحبائنا اليوم:",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 15),
            ...birthdayKids
                .take(3)
                .map(
                  (kid) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min, // Added
                      children: [
                        const Icon(Icons.cake, color: Colors.pink, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          // Added
                          child: Text(
                            kid.name,
                            textAlign: TextAlign.center, // Added
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (birthdayKids.length > 3)
              Text(
                "و ${birthdayKids.length - 3} آخرين...",
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/birthdays');
            },
            child: const Text(
              "الذهاب لصفحة أعياد الميلاد",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إغلاق"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForcedLogout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _listenToInsights() {
    if (_insightService != null) {
      _insightService!.getMyInsights().listen((insights) {
        if (mounted) {
          setState(() {
            _myInsights = insights;
          });
          // Scheduling is now handled by syncData() once per session
        }
      });
    }
  }

  void _onItemTapped(int index) {
    if (_isPendingApproval && (index == 1 || index == 2)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ برجاء انتظار موافقة الأدمن للوصول لهذه البيانات"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // القوائم لكل تاب
    final List<Widget> pages = [
      _buildHomeGrid(context, _userRole),
      const StatsHomePage(),
      const StatusesPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'الإحصائيات',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.style), label: 'الحالات'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'حسابي'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue.shade900,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHomeGrid(BuildContext context, String? role) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF81D4FA), Color(0xFF0277BD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Custom AppBar Area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (role == "admin")
                    IconButton(
                      icon: const Icon(Icons.shield, color: Colors.limeAccent),
                      tooltip: "لوحة التحكم",
                      onPressed: () => Navigator.pushNamed(context, '/admin'),
                    )
                  else
                    const SizedBox(
                      width: 48,
                    ), // Placeholder to keep title centered
                  const Text(
                    "خدمتي",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (!_isPendingApproval)
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              _myInsights.isNotEmpty
                                  ? Icons.lightbulb
                                  : Icons.lightbulb_outline,
                              color: Colors.orange,
                            ),
                            onPressed: _showInsightsDialog,
                          ),
                        ),
                        if (_myInsights.isNotEmpty)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${_myInsights.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
            if (_isPendingApproval) _buildPendingApprovalBanner(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(
                  15,
                ), // Removed bottom padding as BottomNavigationBar handles it
                child: _isPendingApproval
                    ? _buildPendingEmptyState()
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _syncData();
                        },
                        child: ListView(
                        children: [
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 15,
                            mainAxisSpacing: 15,
                            childAspectRatio: 1.0,
                            children: [
                              _redesignedCard(
                                context,
                                "الافتقاد التذكيري",
                                Icons.notifications_none,
                                Colors.blue.shade50,
                                Colors.blue,
                                '/visited',
                              ),
                              _redesignedCard(
                                context,
                                "الافتقاد الفردي",
                                Icons.person_search_outlined,
                                Colors.orange.shade50,
                                Colors.orange,
                                '/individual_visited',
                              ),
                              _redesignedCard(
                                context,
                                "سجل الحضور",
                                Icons.done_all,
                                Colors.teal.shade50,
                                Colors.teal,
                                '/attended',
                              ),
                              _redesignedCard(
                                context,
                                "الغياب",
                                Icons.person_off_outlined,
                                Colors.red.shade50,
                                Colors.red,
                                '/absence',
                              ),
                              _redesignedCard(
                                context,
                                "أعياد الميلاد",
                                Icons.cake_outlined,
                                Colors.pink.shade50,
                                Colors.pink,
                                '/birthdays',
                              ),
                              _redesignedCard(
                                context,
                                "التحضير",
                                Icons.menu_book,
                                Colors.deepOrange.shade50,
                                Colors.deepOrange,
                                '/preparation',
                              ),
                              _redesignedCard(
                                context,
                                "الاجتماعات",
                                Icons.groups_outlined,
                                Colors.indigo.shade50,
                                Colors.indigo,
                                '/meetings',
                              ),
                              _redesignedCard(
                                context,
                                "المتابعة الدراسية",
                                Icons.school_outlined,
                                Colors.purple.shade50,
                                Colors.purple,
                                '/study_tracking',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingApprovalBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_empty, color: Colors.orange),
          SizedBox(width: 15),
          Expanded(
            child: Text(
              "طلب الانضمام قيد المراجعة. برجاء التواصل مع مسؤول المجموعة للموافقة.",
              style: TextStyle(
                color: Colors.brown,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_clock_outlined,
          size: 80,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 20),
        const Text(
          "البيانات مخفية حالياً",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "ستظهر لك جميع الخصائص والبيانات فور قيام أدمن المجموعة بقبول طلب انضمامك.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _redesignedCard(
    BuildContext context,
    String title,
    IconData icon,
    Color circleBg,
    Color iconColor,
    String route,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: circleBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: iconColor),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInsightsDialog() {
    if (_insightService == null) return;

    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<List<AIInsight>>(
          stream: _insightService!.getMyInsights(),
          builder: (context, snapshot) {
            final insights = snapshot.data ?? [];
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  scrollable: true,
                  title: const Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.orange),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "توصيات ذكية 💡",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  content: insights.isEmpty
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: 20),
                            Text(
                              "لا توجد توصيات حالياً.\nشكراً لتعب محبتك وخدمتك! ✨",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            SizedBox(height: 20),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: insights.map((insight) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          insight.type == 'consecutive_absence'
                                              ? Icons.favorite_border
                                              : Icons.auto_awesome,
                                          color:
                                              insight.type ==
                                                  'consecutive_absence'
                                              ? Colors.redAccent
                                              : Colors.blueAccent,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            insight.kidName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Color(0xFF1A237E),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      insight.message,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    OverflowBar(
                                      alignment: MainAxisAlignment.end,
                                      spacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed: () async {
                                            await _insightService
                                                ?.dismissInsight(insight.id);
                                          },
                                          child: const Text(
                                            "تجاهل",
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () async {
                                            // جلب بيانات الطالب للذهاب لصفحة الزيارات
                                            try {
                                              final studentResult =
                                                  await _databases
                                                      .listDocuments(
                                                        databaseId: databaseId,
                                                        collectionId:
                                                            'students',
                                                        queries: [
                                                          Query.equal(
                                                            'name',
                                                            insight.kidName,
                                                          ),
                                                          Query.equal(
                                                            'groupId',
                                                            _myGroupId,
                                                          ),
                                                          Query.limit(1),
                                                        ],
                                                      );

                                              if (studentResult.total > 0 &&
                                                  context.mounted) {
                                                final kid = Kid.fromAppwrite(
                                                  studentResult.documents.first,
                                                );
                                                Navigator.pop(
                                                  context,
                                                ); // إغلاق الحوار
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        IndividualVisitedPage(
                                                          kidName: kid.name,
                                                          grade: kid.grade,
                                                          photoUrl:
                                                              kid.photoUrl,
                                                        ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              debugPrint(
                                                "❌ Error fetching student for insight: $e",
                                              );
                                            }
                                          },
                                          child: const Text("افتقاد الآن"),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                  actions: [
                    if (_userRole == "admin")
                      TextButton(
                        onPressed: () async {
                          try {
                            setDialogState(() => _isInsightLoading = true);
                            await _insightService?.generateInsights();
                          } catch (e) {
                            debugPrint("❌ Error generating insights: $e");
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => _isInsightLoading = false);
                            }
                          }
                        },
                        child: _isInsightLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text("تحديث الكل"),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("إغلاق"),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
