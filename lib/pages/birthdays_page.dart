import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:cached_network_image/cached_network_image.dart';

import '../services/appwrite_service.dart';
import '../services/grade_service.dart';
import '../services/user_service.dart';
import '../services/permission_service.dart';
import '../services/data_cache_service.dart';
import '../services/image_cache_service.dart';
import '../models/kid.dart'; // ✅ Import Global Model
import '../widgets/full_screen_image.dart';

// ✅ Constants
const String studentsCollectionId = "students";
const String servantsCollectionId = "servants";
const String congratulationsCollectionId = "birthday_congratulations";

// ✅ Wrapper Model for View State
class BirthdayKid {
  final Kid kid;
  final String type; // "مخدوم" or "خادم"
  List<String> congratulatedBy;

  BirthdayKid({
    required this.kid,
    required this.type,
    this.congratulatedBy = const [],
  });

  // Proxy Getters for convenience
  String get name => kid.name;
  String get id => kid.id;
  String get grade => kid.grade ?? (type == "خادم" ? 'خدام' : 'صف غير معروف');
  DateTime? get birthDate => kid.dateOfBirth;
  String? get photoUrl => kid.photoUrl;
  String? get localImagePath => kid.localImagePath;

  bool isBirthdayToday() => kid.isBirthdayToday();

  // Helper to get formatted phone with owner
  String getPhoneWithOwner(String phone) => kid.getPhoneWithOwner(phone);

  Map<String, dynamic> toJson() {
    return {
      'kid': kid.toMap(),
      'type': type,
      'congratulatedBy': congratulatedBy,
    };
  }

  factory BirthdayKid.fromJson(Map<String, dynamic> json) {
    try {
      // Handle null or missing kid data
      final kidData = json['kid'];
      if (kidData == null) {
        throw Exception('Kid data is null in cached birthday');
      }

      return BirthdayKid(
        kid: Kid.fromJson(Map<String, dynamic>.from(kidData)),
        type: json['type'] ?? 'مخدوم',
        congratulatedBy: List<String>.from(json['congratulatedBy'] ?? []),
      );
    } catch (e) {
      debugPrint("🎂 Error parsing BirthdayKid from JSON: $e");
      debugPrint("🎂 JSON data: $json");
      rethrow;
    }
  }
}

class BirthdaysPage extends StatefulWidget {
  const BirthdaysPage({super.key});

  @override
  State<BirthdaysPage> createState() => _BirthdaysPageState();
}

class _BirthdaysPageState extends State<BirthdaysPage>
    with SingleTickerProviderStateMixin {
  List<BirthdayKid> _allKids = [];
  List<BirthdayKid> _students = [];
  List<BirthdayKid> _servants = [];

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Client _client = AppwriteService().client;
  late Realtime _realtime;

  RealtimeSubscription? _userSubscription;
  RealtimeSubscription? _studentsSubscription;
  RealtimeSubscription? _servantsSubscription;
  RealtimeSubscription? _congratulationsSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  AnimationController? _animationController;

  String _myGroupId = '';
  String? _teamId; // ✅ Add Team ID
  String _currentServerName = "جاري التحميل...";
  bool _isLoading = true;
  List<String> _gradeOrder = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _realtime = Realtime(_client);
    _loadServerName();
    _loadUserData();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _userSubscription?.close();
    _studentsSubscription?.close();
    _servantsSubscription?.close();
    _congratulationsSubscription?.close();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();

      // 1. Fetch User Data & Team ID
      try {
        // Try Cache first for Team ID
        final cachedCtx = await DataCacheService().getCachedUserGroupId(
          user.$id,
        );
        if (cachedCtx != null) {
          if (mounted) {
            setState(() {
              _myGroupId = cachedCtx['groupId'] ?? '';
              _teamId = cachedCtx['teamId'];
            });
          }
        } else {
          // Fetch from DB
          final doc = await _databases.getDocument(
            databaseId: databaseId,
            collectionId: usersCollectionId,
            documentId: user.$id,
          );
          if (mounted) {
            _updateUserState(doc.data);
            // 🚀 Trigger load immediately after network fetch
            _fetchGradeOrder();
            _fetchInitialData(forceRefresh: true);
            _subscribeToData();
            _subscribeToCongratulations();
          }
        }
      } catch (e) {
        debugPrint("Error fetching user data: $e");
      }

      // Realtime Listener
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);

      _userSubscription!.stream.listen((event) {
        try {
          if (mounted) {
            final payload = Map<String, dynamic>.from(event.payload);
            _updateUserState(payload);

            // Reload data if groupId changed
            if (payload['groupId'] != null &&
                payload['groupId'] != _myGroupId) {
              _fetchGradeOrder();
              _fetchInitialData(forceRefresh: true);
            }
          }
        } catch (e) {
          debugPrint("🎂 Error processing realtime user update: $e");
        }
      });

      // Trigger initial load if we have data from cache/fetch
      if (_myGroupId.isNotEmpty) {
        _fetchGradeOrder();
        await _fetchInitialData();
        _subscribeToData();
        _subscribeToCongratulations();
      }
    } catch (e) {
      debugPrint("Error in _loadUserData: $e");
    }
  }

  void _updateUserState(Map<String, dynamic> data) {
    try {
      if (mounted) {
        setState(() {
          _myGroupId = data['groupId'] ?? '';
          _teamId = data['teamId']; // ✅ Update Team ID
        });
        debugPrint(
          "🎂 User state updated: groupId=$_myGroupId, teamId=$_teamId",
        );
      }
    } catch (e) {
      debugPrint("🎂 Error updating user state: $e");
    }
  }

  Future<void> _loadServerName() async {
    final name = await UserService().getCurrentUserName();
    if (mounted) {
      setState(() {
        _currentServerName = name;
      });
    }
  }

  Future<void> _fetchGradeOrder() async {
    try {
      final grades = await GradeService(groupId: _myGroupId).getGrades();
      if (mounted) {
        setState(() {
          _gradeOrder = grades;
        });
      }
    } catch (e) {
      debugPrint("Error fetching grades order: $e");
    }
  }

  Future<void> _fetchInitialData({bool forceRefresh = false}) async {
    try {
      debugPrint(
        "🎂 _fetchInitialData started, forceRefresh=$forceRefresh, groupId=$_myGroupId",
      );

      // 1. Try Cache
      if (!forceRefresh) {
        final cachedList = await DataCacheService().getCachedBirthdayList(
          _myGroupId,
        );
        if (cachedList.isNotEmpty) {
          if (mounted) {
            setState(() {
              _allKids = cachedList
                  .where((e) => e['kid'] != null)
                  .map((e) {
                    try {
                      return BirthdayKid.fromJson(e);
                    } catch (err) {
                      return null;
                    }
                  })
                  .whereType<BirthdayKid>()
                  .toList();
              _isLoading = false;
            });
          }
          // 🚀 Background refresh after loading cache
          _fetchFreshData();
          return;
        }
        debugPrint("🎂 Cache is empty, fetching from server...");
      }

      await _fetchFreshData();
    } catch (e) {
      debugPrint("🎂 Error in _fetchInitialData: $e");
      _handleError("بيانات", e);
    }
  }

  Future<void> _fetchFreshData() async {
    try {
      debugPrint("🎂 Fetching fresh data from server...");
      final List<BirthdayKid> freshStudents = [];
      await _fetchCollection(studentsCollectionId, "مخدوم", freshStudents);

      final List<BirthdayKid> freshServants = [];
      await _fetchCollection(servantsCollectionId, "خادم", freshServants);

      if (mounted) {
        setState(() {
          _students = freshStudents;
          _servants = freshServants;
          _combineAndSetState();
        });
      }

      final allData = [
        ...freshStudents,
        ...freshServants,
      ].map((k) => k.toJson()).toList();
      await DataCacheService().cacheBirthdayList(_myGroupId, allData);
      await _fetchCongratulations();
    } catch (e) {
      debugPrint("🎂 Error fetching fresh data: $e");
    }
  }

  Future<void> _fetchCollection(
    String collectionId,
    String type,
    List<BirthdayKid> targetList,
  ) async {
    String? lastId;
    bool hasMore = true;

    while (hasMore) {
      List<String> queries = [
        Query.equal('groupId', _myGroupId),
        Query.limit(100),
      ];
      if (lastId != null) {
        queries.add(Query.cursorAfter(lastId));
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: queries,
      );

      if (result.documents.isEmpty) {
        hasMore = false;
        break;
      }

      for (var doc in result.documents) {
        try {
          targetList.add(BirthdayKid(kid: Kid.fromAppwrite(doc), type: type));
        } catch (e) {
          debugPrint("🎂 Error parsing kid document ${doc.$id}: $e");
          debugPrint("🎂 Document data: ${doc.data}");
        }
      }

      if (result.documents.length < 100) {
        hasMore = false;
      } else {
        lastId = result.documents.last.$id;
      }
    }
  }

  void _subscribeToData() {
    _studentsSubscription = _realtime.subscribe([
      'databases.$databaseId.collections.$studentsCollectionId.documents',
    ]);
    _studentsSubscription!.stream.listen((event) {
      if (event.payload['groupId'] == _myGroupId) {
        _handleRealtimeUpdate(event, "مخدوم");
      }
    });

    _servantsSubscription = _realtime.subscribe([
      'databases.$databaseId.collections.$servantsCollectionId.documents',
    ]);
    _servantsSubscription!.stream.listen((event) {
      if (event.payload['groupId'] == _myGroupId) {
        _handleRealtimeUpdate(event, "خادم");
      }
    });
  }

  void _handleRealtimeUpdate(RealtimeMessage event, String type) async {
    final payload = event.payload;
    final docId = payload['\$id'];
    final eventType = event.events.first;

    if (mounted) {
      setState(() {
        if (eventType.endsWith('.delete')) {
          _allKids.removeWhere((k) => k.id == docId);
        } else {
          final newKid = BirthdayKid(
            kid: Kid.fromAppwrite(models.Document.fromMap(payload)),
            type: type,
          );

          final index = _allKids.indexWhere((k) => k.id == docId);
          if (index != -1) {
            // Preserve congratulations logic if any
            newKid.congratulatedBy = _allKids[index].congratulatedBy;
            _allKids[index] = newKid;
          } else {
            _allKids.add(newKid);
          }
        }
        _allKids.sort((a, b) => a.name.compareTo(b.name));
      });

      final allData = _allKids.map((k) => k.toJson()).toList();
      await DataCacheService().cacheBirthdayList(_myGroupId, allData);
    }
  }

  void _combineAndSetState() {
    if (mounted) {
      setState(() {
        List<BirthdayKid> combinedKids = [..._students, ..._servants];
        combinedKids.sort((a, b) => a.name.compareTo(b.name));
        _allKids = combinedKids;
        _isLoading = false;
      });
    }
  }

  void _handleError(String dataType, dynamic error) {
    if (mounted) {
      setState(() => _isLoading = false);
      // Only show snackbar if it's a real error (not just empty list)
      debugPrint("Error fetching $dataType: $error");
    }
  }

  Future<void> _fetchCongratulations() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: congratulationsCollectionId,
        queries: [Query.equal('groupId', _myGroupId), Query.limit(1000)],
      );

      debugPrint(
        "🎂 BirthdaysPage: Fetched ${result.documents.length} congratulations for group $_myGroupId",
      );

      _processCongratulations(result.documents);
    } catch (e) {
      debugPrint("Error fetching congratulations: $e");
    }
  }

  void _subscribeToCongratulations() {
    _congratulationsSubscription = _realtime.subscribe([
      'databases.$databaseId.collections.$congratulationsCollectionId.documents',
    ]);

    _congratulationsSubscription!.stream.listen((event) {
      if (event.payload['groupId'] == _myGroupId) {
        _fetchCongratulations();
      }
    });
  }

  Future<void> _processCongratulations(List<models.Document> docs) async {
    for (var k in _allKids) {
      k.congratulatedBy = [];
    }

    final List<String> docsToDelete = [];
    final now = DateTime.now();

    for (var doc in docs) {
      final data = doc.data;
      final kidName = data['kidName'];

      // Match by Name
      final kidIndex = _allKids.indexWhere((k) => k.name == kidName);
      if (kidIndex == -1) continue;

      final kid = _allKids[kidIndex];
      if (kid.birthDate == null) continue;

      final localBirth = kid.birthDate!.toLocal();
      final birthdayThisYear = DateTime(
        now.year,
        localBirth.month,
        localBirth.day,
      );

      if (kid.isBirthdayToday()) {
        if (data['congratulatedBy'] != null) {
          kid.congratulatedBy = List<String>.from(data['congratulatedBy']);
        }
      } else if (now.isAfter(birthdayThisYear) &&
          now.difference(birthdayThisYear).inDays < 7) {
        // Mark for deletion if birthday passed > 7 days ago and still in DB
        docsToDelete.add(doc.$id);
      }
    }

    // Cleanup
    for (var docId in docsToDelete) {
      try {
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: congratulationsCollectionId,
          documentId: docId,
        );
      } catch (e) {
        /* Ignore */
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _recordCongratulation(BirthdayKid kid) async {
    if (_currentServerName.contains("جاري التحميل") ||
        _currentServerName.contains("الزائر")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء الانتظار حتى يتم تحميل اسم الخادم.'),
        ),
      );
      return;
    }

    final hasPermission = await PermissionService.canWrite(_myGroupId);
    if (!hasPermission) {
      // Show error based on permission logic
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ انتهت صلاحية الاشتراك")),
        );
      }
      return;
    }

    // Optimistic Update
    setState(() {
      if (!kid.congratulatedBy.contains(_currentServerName)) {
        kid.congratulatedBy.add(_currentServerName);
      }
    });

    try {
      final docs = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: congratulationsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('kidName', kid.name),
          Query.limit(1),
        ],
      );

      if (docs.documents.isNotEmpty) {
        final doc = docs.documents.first;
        List<String> currentList = List<String>.from(
          doc.data['congratulatedBy'] ?? [],
        );
        if (!currentList.contains(_currentServerName)) {
          currentList.add(_currentServerName);
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: congratulationsCollectionId,
            documentId: doc.$id,
            data: {
              'congratulatedBy': currentList,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
        }
      } else {
        // ✅ Create with permissions
        await _databases.createDocument(
          databaseId: databaseId,
          collectionId: congratulationsCollectionId,
          documentId: ID.unique(),
          data: {
            'groupId': _myGroupId,
            'kidName': kid.name,
            'congratulatedBy': [_currentServerName],
            'timestamp': DateTime.now().toIso8601String(),
          },
          permissions: (_teamId != null && _teamId!.isNotEmpty)
              ? [
                  Permission.read(Role.users()),
                  Permission.update(Role.team(_teamId!)),
                  Permission.delete(Role.team(_teamId!)),
                ]
              : [
                  Permission.read(Role.users()),
                  Permission.update(Role.users()),
                  Permission.delete(Role.users()),
                ],
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 تمت التهنئة لـ ${kid.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() {
        kid.congratulatedBy.remove(_currentServerName);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
      }
    }
  }

  void _removeCongratulation(BirthdayKid kid) async {
    if (_currentServerName.contains("جاري التحميل") ||
        _currentServerName.contains("الزائر")) {
      return;
    }

    setState(() {
      kid.congratulatedBy.remove(_currentServerName);
    });

    try {
      final docs = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: congratulationsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('kidName', kid.name),
          Query.limit(1),
        ],
      );

      if (docs.documents.isNotEmpty) {
        final doc = docs.documents.first;
        List<String> currentList = List<String>.from(
          doc.data['congratulatedBy'] ?? [],
        );
        currentList.remove(_currentServerName);

        await _databases.updateDocument(
          databaseId: databaseId,
          collectionId: congratulationsCollectionId,
          documentId: doc.$id,
          data: {
            'congratulatedBy': currentList,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ تم إلغاء التهنئة'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() {
        kid.congratulatedBy.add(_currentServerName);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
      }
    }
  }

  Map<String, List<BirthdayKid>> _getTodayBirthdaysByGrade() {
    final Map<String, List<BirthdayKid>> groupedBirthdays = {};
    final now = DateTime.now();

    debugPrint("🎂 Today is: ${now.year}-${now.month}-${now.day}");
    debugPrint("🎂 Total kids to check: ${_allKids.length}");

    // Debug: Check each kid's birthday
    for (var kid in _allKids) {
      if (kid.birthDate != null) {
        final isBirthday = kid.isBirthdayToday();
        if (isBirthday ||
            (kid.birthDate!.month == now.month &&
                (kid.birthDate!.day - now.day).abs() <= 2)) {
          debugPrint(
            "🎂 ${kid.name}: birthDate=${kid.birthDate!.month}-${kid.birthDate!.day}, isBirthdayToday=$isBirthday",
          );
        }
      }
    }

    final todayBirthdays = _allKids.where((k) => k.isBirthdayToday()).toList();
    debugPrint("🎂 Found ${todayBirthdays.length} birthdays today");

    final List<BirthdayKid> studentsToday = todayBirthdays
        .where((k) => k.type == "مخدوم")
        .toList();
    for (var kid in studentsToday) {
      final key = kid.grade;
      if (!groupedBirthdays.containsKey(key)) {
        groupedBirthdays[key] = [];
      }
      groupedBirthdays[key]!.add(kid);
    }

    final List<BirthdayKid> servantsToday = todayBirthdays
        .where((k) => k.type == "خادم")
        .toList();
    if (servantsToday.isNotEmpty) {
      groupedBirthdays["الخدام"] = servantsToday;
    }

    final sortedKeys = groupedBirthdays.keys.toList();
    sortedKeys.sort((a, b) {
      if (a == "الخدام") return -1;
      if (b == "الخدام") return 1;
      final indexA = _gradeOrder.indexOf(a);
      final indexB = _gradeOrder.indexOf(b);
      if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;
      return a.compareTo(b);
    });

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, groupedBirthdays[key]!)),
    );
  }

  void _showPhoneOptions(
    BuildContext context,
    String phone,
    String kidName,
    String phoneWithOwner,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 15,
              spreadRadius: 0,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔹 رأس البطاقة
              Container(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width * 0.04,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(
                        MediaQuery.of(context).size.width * 0.015,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.phone,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width * 0.05,
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width * 0.025),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "خيارات الاتصال",
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.045,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.005,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              kidName,
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.035,
                                color: Colors.blue.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.005,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              phoneWithOwner,
                              style: TextStyle(
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.03,
                                color: Colors.blue.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 🔹 خيارات الاتصال
              Padding(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width * 0.04,
                ),
                child: Column(
                  children: [
                    // زر الاتصال
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height * 0.012,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          launchUrl(Uri.parse("tel:$phone"));
                        },
                        icon: Icon(
                          Icons.phone,
                          color: Colors.white,
                          size: MediaQuery.of(context).size.width * 0.045,
                        ),
                        label: Text(
                          "الاتصال",
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.04,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: MediaQuery.of(context).size.height * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),

                    // زر واتساب
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height * 0.012,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          launchUrl(Uri.parse("https://wa.me/$phone"));
                        },
                        icon: Icon(
                          Icons.message,
                          color: Colors.white,
                          size: MediaQuery.of(context).size.width * 0.045,
                        ),
                        label: Text(
                          "رسالة واتساب",
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.04,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: MediaQuery.of(context).size.height * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),

                    // زر نسخ الرقم
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height * 0.01,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Clipboard.setData(ClipboardData(text: phone));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("✅ تم نسخ الرقم: $phone"),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.content_copy,
                          color: Colors.white,
                          size: MediaQuery.of(context).size.width * 0.045,
                        ),
                        label: Text(
                          "نسخ الرقم",
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.04,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: MediaQuery.of(context).size.height * 0.02,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🔹 زر الإلغاء
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width * 0.04,
                  vertical: MediaQuery.of(context).size.height * 0.01,
                ),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: EdgeInsets.symmetric(
                      vertical: MediaQuery.of(context).size.height * 0.015,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    "إلغاء",
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.04,
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 دالة عرض تأكيد إلغاء التهنئة
  void _showRemoveCongratulationDialog(BirthdayKid kid) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning,
                color: Colors.orange,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              SizedBox(width: MediaQuery.of(context).size.width * 0.02),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "إلغاء التهنئة",
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.045,
                    ),
                  ),
                ),
              ),
            ],
          ),
          content: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              "هل تريد إلغاء تهنئة ${kid.name}؟",
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.04,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                "إلغاء",
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _removeCongratulation(kid);
              },
              child: Text(
                "نعم، إلغاء",
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.035,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D47A1),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.02),
              Text(
                "جاري تحميل البيانات...",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: MediaQuery.of(context).size.width * 0.04,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final todayBirthdays = _getTodayBirthdaysByGrade();
    final hasBirthdays = todayBirthdays.isNotEmpty;

    // Format current date in Arabic
    final now = DateTime.now();
    final arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final arabicDays = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    final dayName = arabicDays[(now.weekday - 1) % 7];
    final formattedDate = '$dayName, ${now.day} ${arabicMonths[now.month - 1]}';

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.height * 0.25,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  "أعياد الميلاد",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width * 0.045,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      const Shadow(blurRadius: 10, color: Colors.black),
                    ],
                  ),
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.02,
                      right: MediaQuery.of(context).size.width * 0.05,
                      child: Icon(
                        Icons.celebration,
                        size: MediaQuery.of(context).size.width * 0.15,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    Positioned(
                      bottom: MediaQuery.of(context).size.height * 0.02,
                      left: MediaQuery.of(context).size.width * 0.05,
                      child: Icon(
                        Icons.cake,
                        size: MediaQuery.of(context).size.width * 0.12,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.05,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formattedDate,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.045,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.01,
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _currentServerName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize:
                                    MediaQuery.of(context).size.width * 0.035,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.02,
                bottom: MediaQuery.of(context).size.height * 0.01,
              ),
              child: hasBirthdays
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "🎊 أعياد ميلاد اليوم",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width * 0.06,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: const Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.06,
                        ),
                        Icon(
                          Icons.snooze,
                          size: MediaQuery.of(context).size.width * 0.2,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.02,
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            "لا توجد أعياد ميلاد اليوم. 🙏",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.045,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          if (hasBirthdays)
            SliverList(
              delegate: SliverChildListDelegate(
                todayBirthdays.entries.map((entry) {
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.02,
                    ),
                    child: _buildGradeSection(entry.key, entry.value),
                  );
                }).toList(),
              ),
            ),

          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).size.height * 0.06),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeSection(String grade, List<BirthdayKid> kids) {
    final isServantsSection = grade == "الخدام";
    final mainColor = isServantsSection ? Colors.purple : Colors.blue;
    final title = isServantsSection ? "الخدام" : "المخدومين";

    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height * 0.02,
      ),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ExpansionTile(
            initiallyExpanded: true,
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            tilePadding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.05,
              vertical: MediaQuery.of(context).size.height * 0.01,
            ),
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(
                    MediaQuery.of(context).size.width * 0.02,
                  ),
                  decoration: BoxDecoration(
                    color: mainColor.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isServantsSection ? Icons.volunteer_activism : Icons.school,
                    color: mainColor.shade700,
                    size: MediaQuery.of(context).size.width * 0.05,
                  ),
                ),
                SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: MediaQuery.of(context).size.width * 0.045,
                        color: mainColor.shade900,
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width * 0.03,
                    vertical: MediaQuery.of(context).size.height * 0.008,
                  ),
                  decoration: BoxDecoration(
                    color: mainColor.shade100,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${kids.length}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: mainColor.shade800,
                        fontSize: MediaQuery.of(context).size.width * 0.04,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            children: kids.map((kid) {
              return _buildCelebrationCard(kid);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // 🔥 دالة بناء كارت المخدوم المعدلة (Firebase Design)
  Widget _buildCelebrationCard(BirthdayKid kid) {
    final hasCongratulated = kid.congratulatedBy.contains(_currentServerName);
    final isServant = kid.type == "خادم";
    final gradeText = isServant ? kid.grade : " ${kid.grade}";

    // Format birth date
    String formattedBirthDate = "";
    if (kid.birthDate != null) {
      formattedBirthDate =
          "${kid.birthDate!.day}/${kid.birthDate!.month}/${kid.birthDate!.year}";
    }

    return Container(
      margin: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.008,
        horizontal: MediaQuery.of(context).size.width * 0.02,
      ),
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.18,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasCongratulated
                ? [Colors.green.shade50, Colors.lightGreen.shade50]
                : isServant
                ? [Colors.purple.shade50, Colors.deepPurple.shade50]
                : [Colors.blue.shade50, Colors.lightBlue.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 🔹 الجزء الأيسر: الصورة والمعلومات
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width * 0.03,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (kid.photoUrl != null ||
                                kid.kid.localImagePath != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenImage(
                                    imageUrl: kid.photoUrl,
                                    localPath: kid.kid.localImagePath,
                                    tag: 'bday_${kid.id}',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Hero(
                            tag: 'bday_${kid.id}',
                            child: CircleAvatar(
                              radius: MediaQuery.of(context).size.width * 0.055,
                              backgroundColor: isServant
                                  ? Colors.purple.shade100
                                  : Colors.blue.shade100,
                              backgroundImage:
                                  (kid.kid.localImagePath != null &&
                                      kid.kid.localImagePath!.isNotEmpty)
                                  ? FileImage(File(kid.kid.localImagePath!))
                                  : ((kid.photoUrl != null &&
                                                kid.photoUrl!.isNotEmpty)
                                            ? CachedNetworkImageProvider(
                                                kid.photoUrl!,
                                                cacheManager:
                                                    ImageCacheService.instance,
                                              )
                                            : null)
                                        as ImageProvider?,
                              child:
                                  ((kid.photoUrl == null ||
                                          kid.photoUrl!.isEmpty) &&
                                      (kid.kid.localImagePath == null ||
                                          kid.kid.localImagePath!.isEmpty))
                                  ? Icon(
                                      isServant ? Icons.person_pin : Icons.cake,
                                      color: isServant
                                          ? Colors.deepPurple
                                          : Colors.pink,
                                      size:
                                          MediaQuery.of(context).size.width *
                                          0.05,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.03,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  kid.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                        0.04,
                                    color: isServant
                                        ? Colors.purple.shade900
                                        : Colors.blue.shade900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.005,
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  gradeText,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                        0.035,
                                    color: isServant
                                        ? Colors.purple.shade700
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                    if (formattedBirthDate.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "🎂 تاريخ الميلاد: $formattedBirthDate",
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.033,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    SizedBox(height: MediaQuery.of(context).size.height * 0.01),

                    // 🔹 عرض الأرقام
                    if (kid.kid.phones.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: kid.kid.phones.map((phone) {
                          final phoneWithOwner = kid.getPhoneWithOwner(phone);
                          return Container(
                            margin: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(context).size.height * 0.005,
                            ),
                            child: InkWell(
                              onTap: () => _showPhoneOptions(
                                context,
                                phone,
                                kid.name,
                                phoneWithOwner,
                              ),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      MediaQuery.of(context).size.width * 0.02,
                                  vertical:
                                      MediaQuery.of(context).size.height *
                                      0.005,
                                ),
                                decoration: BoxDecoration(
                                  color: isServant
                                      ? Colors.purple.shade50
                                      : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isServant
                                        ? Colors.purple.shade200
                                        : Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.phone,
                                      size:
                                          MediaQuery.of(context).size.width *
                                          0.035,
                                      color: isServant
                                          ? Colors.purple.shade700
                                          : Colors.blue.shade700,
                                    ),
                                    SizedBox(
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.01,
                                    ),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          phoneWithOwner,
                                          style: TextStyle(
                                            color: isServant
                                                ? Colors.purple.shade800
                                                : Colors.blue.shade800,
                                            fontWeight: FontWeight.w500,
                                            fontSize:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.03,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                    // 🔹 عرض قائمة المهنئين
                    if (kid.congratulatedBy.isNotEmpty) ...[
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.01,
                      ),
                      Container(
                        padding: EdgeInsets.all(
                          MediaQuery.of(context).size.width * 0.015,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.celebration,
                                  size:
                                      MediaQuery.of(context).size.width * 0.035,
                                  color: Colors.green.shade700,
                                ),
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width * 0.01,
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "المهنئون:",
                                    style: TextStyle(
                                      fontSize:
                                          MediaQuery.of(context).size.width *
                                          0.03,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              height:
                                  MediaQuery.of(context).size.height * 0.005,
                            ),
                            Wrap(
                              spacing:
                                  MediaQuery.of(context).size.width * 0.008,
                              runSpacing:
                                  MediaQuery.of(context).size.height * 0.003,
                              children: kid.congratulatedBy.map((name) {
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal:
                                        MediaQuery.of(context).size.width *
                                        0.015,
                                    vertical:
                                        MediaQuery.of(context).size.height *
                                        0.003,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize:
                                            MediaQuery.of(context).size.width *
                                            0.028,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 🔹 الجزء الأيمن: زر التهنئة
            Container(
              width: MediaQuery.of(context).size.width * 0.18,
              padding: EdgeInsets.symmetric(
                vertical: MediaQuery.of(context).size.height * 0.015,
                horizontal: MediaQuery.of(context).size.width * 0.01,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // زر التهنئة/إلغاء التهنئة
                  Container(
                    width: MediaQuery.of(context).size.width * 0.11,
                    height: MediaQuery.of(context).size.width * 0.11,
                    decoration: BoxDecoration(
                      color: hasCongratulated ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(
                        MediaQuery.of(context).size.width * 0.055,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        hasCongratulated ? Icons.check : Icons.cake,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width * 0.055,
                      ),
                      onPressed: hasCongratulated
                          ? () => _showRemoveCongratulationDialog(kid)
                          : () => _recordCongratulation(kid),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.008),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      hasCongratulated ? "مُهَنأ" : "تهنئة",
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.033,
                        color: hasCongratulated
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
