import 'package:flutter/material.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import 'subscription_page.dart';
import 'super_admin_page.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service
import '../services/user_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // Placeholder removed
  final Account _account = AppwriteService().account;
  final Databases _databases = AppwriteService().databases;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  AnimationController? _animationController;

  // 🚀 Local State for Caching
  Map<String, dynamic>? _cachedUserData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _loadUserData(); // 🚀 Load Data on Init
  }

  // 🚀 Fetch Data with Caching Strategy
  Future<void> _loadUserData() async {
    // 1. Try Loading from Cache
    final cached = await DataCacheService().getCachedUserData();
    if (cached != null) {
      if (mounted) {
        setState(() {
          _cachedUserData = cached;
          _isLoading = false;
        });
      }
    }

    // 2. Fetch Fresh Data (Background)
    try {
      final user = await _account.get();
      final userDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      // 2b. Fetch Status from Membership
      String? groupStatus;
      final activeGroupId = userDoc.data['groupId'] ?? '';
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
            groupStatus = membershipRes.documents.first.data['status'];
          }
        } catch (e) {
          debugPrint("Error fetching membership status in Profile: $e");
        }
      }

      final Map<String, dynamic> freshData = {
        'id': user.$id,
        'email': user.email,
        'username': userDoc.data['username'] ?? user.email,
        'role': userDoc.data['role'] ?? 'user',
        'groupId': activeGroupId,
        if (groupStatus != null) 'status': groupStatus,
      };

      // 3. Update Cache & UI
      await DataCacheService().cacheUserData(freshData);
      if (mounted) {
        setState(() {
          _cachedUserData = freshData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile data: $e");
      if (mounted && _cachedUserData == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  // Removed checkNotificationStatus as requested

  Future<void> _signOut() async {
    try {
      await UserService().clearSession(); // 🗑️ Clear local cache
      await _account.deleteSession(sessionId: 'current');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint("Error signing out: $e");
      // Force logout anyway for UX
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  void _showGlobalBroadcastDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController(
      text: "إعلان عام من الإدارة 📢",
    );
    final TextEditingController bodyController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "إرسال إشعار لجميع مستخدمي التطبيق",
            textAlign: TextAlign.right,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: "عنوان الرسالة"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyController,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: "نص الرسالة"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            if (isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: () async {
                  if (bodyController.text.isEmpty) return;

                  setState(() => isLoading = true);
                  try {
                    await NotificationService().sendBroadcast(
                      titleController.text,
                      bodyController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "🚀 تم إرسال الإشعار لجميع المستخدمين بنجاح",
                            textAlign: TextAlign.right,
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("❌ فشل الإرسال: $e")),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.send),
                label: const Text("إرسال الآن"),
              ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF0277BD)),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                "عن التطبيق والأمان",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "تطبيق خدمتي لإدارة المجموعات ومتابعة الحضور والغياب والأنشطة المختلفة بشكل سهل ومنظم.",
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Divider(height: 30),
              _buildSecurityPoint(
                "تشفير SSL/TLS",
                "جميع البيانات يتم نقلها من وإلى التطبيق تحت بروتوكولات تشفير عالمية لضمان عدم اعتراضها.",
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                "حماية التطبيق ",
                "تُخزن البيانات في خوادم مؤمنة بأعلى المعايير الأمنية والحواجز النارية.",
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                "تشفير كلمات المرور",
                "لا يتم تخزين كلمات المرور كنصوص عادية، بل يتم تجزئتها وتشفيرها بشكل آمن.",
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                "أمان الصور والملفات",
                "تُعالج الصور عبر روابط آمنة (HTTPS) لضمان الخصوصية وسرعة الوصول.",
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                "حماية بيانات المجموعة",
                "نظام رادع يمنع دخول أي مستخدم للمجموعة أو رؤية البيانات (حالات، إحصائيات، طلاب) إلا بعد مراجعة وقبول يدوي من مدير المجموعة (Admin)، مع تحديث لحظي للصلاحيات بمجرد الموافقة.",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "إغلاق",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPoint(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF0277BD),
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  void _showGroupsDialog(BuildContext context, String currentUserId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _GroupsManagerDialog(userId: currentUserId, databases: _databases),
    );
  }

  void _showFontSizeDialog(BuildContext context, double currentMultiplier) {
    final Map<String, double> sizes = {
      "صغير": 0.8,
      "عادي": 1.0,
      "متوسط": 1.2,
      "كبير": 1.4,
      "كبير جداً": 1.6,
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "اختر حجم الخط مناسب لك",
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sizes.entries.map((entry) {
            final isSelected = (currentMultiplier - entry.value).abs() < 0.01;
            return ListTile(
              title: Text(
                entry.key,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF0277BD) : Colors.black87,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Color(0xFF0277BD))
                  : null,
              onTap: () {
                SettingsService().setFontSize(entry.value);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPremiumBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (_animationController != null)
            AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildAnimatedBlob(
                      top: -50,
                      left: -50,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 60,
                        cos(_animationController!.value * 2 * pi) * 40,
                      ),
                      color: Colors.white.withValues(alpha: 0.1),
                      size: 300,
                    ),
                    _buildAnimatedBlob(
                      top: 300,
                      left: 150,
                      offset: Offset(
                        cos(_animationController!.value * 2 * pi) * 70,
                        sin(_animationController!.value * 2 * pi) * 50,
                      ),
                      color: Colors.white.withValues(alpha: 0.07),
                      size: 250,
                    ),
                    _buildAnimatedBlob(
                      top: 600,
                      left: -30,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 40,
                        -cos(_animationController!.value * 2 * pi) * 60,
                      ),
                      color: Colors.white.withValues(alpha: 0.05),
                      size: 200,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    double? top,
    double? left,
    required Offset offset,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 Use Local State instead of FutureBuilder
    if (_isLoading && _cachedUserData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Default values if data load failed
    final String displayName = _cachedUserData?['username'] ?? "مستخدم";
    final String email = _cachedUserData?['email'] ?? "";
    final String role = _cachedUserData?['role'] ?? "user";
    final String? groupId = _cachedUserData?['groupId'];
    final String? userId = _cachedUserData?['id'];

    return Scaffold(
      body: Stack(
        children: [
          _buildPremiumBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Centered Title with padding to avoid icons
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 50),
                          child: Text(
                            "حسابي",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        // Action Icons vertically on the right
                        Align(
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ValueListenableBuilder<double>(
                                valueListenable:
                                    SettingsService().fontSizeMultiplier,
                                builder: (context, currentMultiplier, _) {
                                  return IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.format_size,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    onPressed: () => _showFontSizeDialog(
                                      context,
                                      currentMultiplier,
                                    ),
                                    tooltip: "حجم الخط",
                                  );
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.groups,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: () {
                                  if (userId != null) {
                                    _showGroupsDialog(context, userId);
                                  }
                                },
                                tooltip: "مجموعاتي",
                              ),
                              if (email == 'magdyyacoub41@gmail.com')
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.campaign_rounded,
                                    color: Colors.orangeAccent,
                                    size: 22,
                                  ),
                                  onPressed: () =>
                                      _showGlobalBroadcastDialog(context),
                                  tooltip: "إرسال إشعار عالمي",
                                ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.info_outline,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: () => _showInfoDialog(context),
                                tooltip: "عن التطبيق",
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 🚀 User Info Section (Using Cached Data)
                  Column(
                    children: [
                      const CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          email,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const SizedBox(height: 20),

                      const SizedBox(height: 20),

                      // Contact Us Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                "تواصل معنا",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildSocialButton(
                                    icon: Icons.chat_bubble_outline,
                                    label: "واتساب",
                                    color: Colors.green.shade400,
                                    onTap: () => _launchURL(
                                      "https://wa.me/qr/PVCRF6JDXXLVD1",
                                    ),
                                  ),
                                  _buildSocialButton(
                                    icon: Icons.send,
                                    label: "تليجرام",
                                    color: Colors.blue.shade400,
                                    onTap: () => _launchURL(
                                      "https://t.me/+Eql6H_Ebm_4wMWFk",
                                    ),
                                  ),
                                  _buildSocialButton(
                                    icon: Icons.camera_alt_outlined,
                                    label: "إنستجرام",
                                    color: Colors.pink.shade400,
                                    onTap: () => _launchURL(
                                      "https://www.instagram.com/magdyyacoub0?igsh=MXFyb2ZwcjJtbGNwYg==",
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Subscription Button
                      if (role != 'user' && groupId != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 10,
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SubscriptionPage(groupId: groupId),
                                ),
                              );
                            },
                            icon: const Icon(Icons.star, color: Colors.blue),
                            label: const Text("الاشتراكات"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 50),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),

                      // Super Admin Button
                      if (email == 'magdyyacoub41@gmail.com')
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 10,
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SuperAdminPage(),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.admin_panel_settings,
                              color: Colors.red,
                            ),
                            label: const Text("لوحة تحكم المشرف العام"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 50),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 32),

                      ElevatedButton.icon(
                        onPressed: () => _signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text("تسجيل الخروج"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 🛠️ Debugging Section
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _GroupsManagerDialog extends StatefulWidget {
  final String userId;
  final Databases databases;

  const _GroupsManagerDialog({required this.userId, required this.databases});

  @override
  State<_GroupsManagerDialog> createState() => _GroupsManagerDialogState();
}

class _GroupsManagerDialogState extends State<_GroupsManagerDialog> {
  bool _isLoading = true;
  List<models.Document> _memberships = [];
  final TextEditingController _joinCodeController = TextEditingController();
  // Cloud Function removed in favor of Admin Approval flow

  @override
  void initState() {
    super.initState();
    _loadMemberships();
  }

  Future<void> _loadMemberships() async {
    try {
      final membershipResult = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [Query.equal('userId', widget.userId)],
      );

      final groupIds = membershipResult.documents
          .map((m) => m.data['groupId'] as String)
          .toList();

      Map<String, String> groupNames = {};
      if (groupIds.isNotEmpty) {
        final groupsResult = await widget.databases.listDocuments(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.groupsCollectionId,
          queries: [Query.equal('groupId', groupIds)],
        );
        for (var g in groupsResult.documents) {
          final serviceName = g.data['serviceName'] ?? 'بدون اسم';
          final stageName = g.data['churchName'] ?? '';
          groupNames[g.data['groupId']] = stageName.isNotEmpty
              ? "$serviceName - $stageName"
              : serviceName;
        }
      }

      // 1.5. Self-healing: Check if primary group is missing from memberships
      final userDoc = await widget.databases.getDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.usersCollectionId,
        documentId: widget.userId,
      );
      final primaryGroupId = userDoc.data['groupId'] ?? '';

      if (primaryGroupId.isNotEmpty && !groupIds.contains(primaryGroupId)) {
        debugPrint(
          "Self-healing: Primary group $primaryGroupId missing from memberships. Creating...",
        );
        await widget.databases.createDocument(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.membershipsCollectionId,
          documentId: ID.unique(),
          data: {
            'userId': widget.userId,
            'groupId': primaryGroupId,
            'role': userDoc.data['role'] ?? 'user',
            'joinedAt': DateTime.now().toIso8601String(),
          },
        );
        // Reload once to include the new membership
        return _loadMemberships();
      }

      if (mounted) {
        setState(() {
          _memberships = membershipResult.documents;
          _groupNamesMap = groupNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading memberships: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, String> _groupNamesMap = {};

  Future<void> _switchGroup(String groupId) async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch role for this group from memberships (using Query instead of direct ID)
      final membershipRes = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupId', groupId),
        ],
      );

      if (membershipRes.total == 0) {
        throw Exception("لم يتم العثور على عضوية لهذه المجموعة");
      }

      final membership = membershipRes.documents.first;
      final role = membership.data['role'] ?? 'user';
      final status = membership.data['status'] ?? 'approved';

      if (status == 'pending') {
        throw Exception("عذراً، هذه المجموعة بانتظار موافقة الأدمن.");
      }

      // 2. Update user doc with groupId AND role
      await widget.databases.updateDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.usersCollectionId,
        documentId: widget.userId,
        data: {'groupId': groupId, 'role': role},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error switching group: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("خطأ في التبديل: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _joinNewGroup() async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // 1. Validate Code
      final groups = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.groupsCollectionId,
        queries: [Query.equal('joinCode', code)],
      );

      if (groups.total == 0) {
        throw Exception("كود المجموعة غير صحيح");
      }

      final group = groups.documents.first;
      final groupId = group.data['groupId'];

      // 2. Check if already joined
      final existing = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupId', groupId),
        ],
      );

      if (existing.total > 0) {
        throw Exception("أنت بالفعل عضو في هذه المجموعة أو بانتظار الموافقة");
      }

      // 3. Create Pending Membership
      await widget.databases.createDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: ID.unique(),
        data: {
          'userId': widget.userId,
          'groupId': groupId,
          'role': 'user',
          'status': 'pending', // 🚀 Pending approval
          'joinedAt': DateTime.now().toIso8601String(),
        },
      );

      // 🚀 UPDATE CACHE IMMEDIATELY TO PREVENT DATA LEAK
      await DataCacheService().cacheUserData({
        'groupId': groupId,
        'role': 'user',
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم إرسال الطلب! بانتظار موافقة أدمن المجموعة."),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context); // Close groups manager dialog
      }
    } catch (e) {
      debugPrint("Error joining group: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("$e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        "مجموعاتي",
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._memberships.map((m) {
                        final gid = m.data['groupId'];
                        final name = _groupNamesMap[gid] ?? 'جاري التحميل...';
                        final status = m.data['status'] ?? 'approved';
                        final isPending = status == 'pending';

                        return ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isPending)
                                Container(
                                  margin: const EdgeInsets.only(left: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "قيد الانتظار",
                                    style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              Text(
                                name,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            "ID: $gid",
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                          leading: Icon(
                            isPending ? Icons.hourglass_top : Icons.church,
                            color: isPending ? Colors.orange : Colors.blue,
                          ),
                          onTap: isPending ? null : () => _switchGroup(gid),
                        );
                      }),
                      const Divider(),
                      TextField(
                        controller: _joinCodeController,
                        decoration: const InputDecoration(
                          hintText: "كود الانضمام الجديد",
                          prefixIcon: Icon(Icons.add),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("إلغاء"),
        ),
        ElevatedButton(onPressed: _joinNewGroup, child: const Text("انضمام")),
      ],
    );
  }
}
