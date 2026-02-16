import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../services/grade_service.dart';
import '../services/appwrite_service.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache
import '../services/user_service.dart';
import 'attendance_page.dart';

class AttendanceGradeSelectorPage extends StatefulWidget {
  final String type;

  const AttendanceGradeSelectorPage({required this.type, super.key});

  @override
  State<AttendanceGradeSelectorPage> createState() =>
      _AttendanceGradeSelectorPageState();
}

class _AttendanceGradeSelectorPageState
    extends State<AttendanceGradeSelectorPage> {
  GradeService? _gradeService;
  bool _isLoadingRole = true;
  String _myGroupId = '';

  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = Realtime(AppwriteService().client);
  final Account _account = AppwriteService().account;
  RealtimeSubscription? _userSubscription;
  StreamSubscription<List<String>>? _gradesSubscription;

  List<String> _grades = [];
  bool _isLoadingGrades = true;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // 🚀 1. Cache First (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        _applyUserData(cachedCtx['groupId']!);
      }
    } else {
      // Global fallback
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        _applyUserData(lastData['groupId']);
      }
    }

    // 🚀 2. Background Refresh
    try {
      final user = await _account.get();
      final userId = user.$id;
      await UserService().getCurrentUser(); // Cache ID

      await _handleUserUpdate(userId);

      _userSubscription?.close();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.$userId',
      ]);

      _userSubscription!.stream.listen((event) {
        if (mounted) {
          _updateState(event.payload);
        }
      });
    } catch (e) {
      debugPrint("Network fetch failed (offline): $e");
      if (mounted && _myGroupId.isEmpty) {
        setState(() => _isLoadingRole = false);
      }
    }
  }

  void _applyUserData(String groupId) {
    if (mounted) {
      setState(() {
        _myGroupId = groupId;
        if (_myGroupId.isNotEmpty) {
          _gradeService = GradeService(groupId: _myGroupId);
          _isLoadingRole = false;
          _setupGradesStream();
        } else {
          _isLoadingRole = false;
        }
      });
    }
  }

  Future<void> _handleUserUpdate(String userId) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );

      // Update Cache
      await DataCacheService().cacheUserGroupId(
        userId,
        doc.data['groupId'],
        doc.data['teamId'],
        doc.data['role'],
      );

      _updateState(doc.data);
    } catch (e) {
      debugPrint("Error fetching user doc: $e");
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  void _updateState(Map<String, dynamic> data) {
    if (mounted) {
      setState(() {
        final newGroupId = data['groupId'] ?? '';
        if (newGroupId != _myGroupId) {
          _myGroupId = newGroupId;
          if (_myGroupId.isNotEmpty) {
            _gradeService = GradeService(groupId: _myGroupId);
            _isLoadingRole = false;
            _setupGradesStream();
          } else {
            _isLoadingRole = false;
          }
        }
      });
    }
  }

  Future<void> _setupGradesStream() async {
    // 1. Initial Cache Load
    final cachedGrades = await DataCacheService().getCachedGrades(_myGroupId);
    if (cachedGrades.isNotEmpty) {
      if (mounted) {
        setState(() {
          _grades = cachedGrades;
          _isLoadingGrades = false;
        });
      }
    }

    // 2. Subscribe to Stream
    _gradesSubscription?.cancel();
    _gradesSubscription = _gradeService?.getGradesStream().listen(
      (grades) {
        if (mounted) {
          setState(() {
            _grades = grades;
            _isLoadingGrades = false;
          });
          // Update Cache
          DataCacheService().cacheGrades(_myGroupId, grades);
        }
      },
      onError: (e) {
        debugPrint("Error in grades stream: $e");
        if (mounted && _grades.isEmpty) {
          setState(() => _isLoadingGrades = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("اختيار المرحلة - ${widget.type}")),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Center(
            child: _isLoadingRole || (_isLoadingGrades && _grades.isEmpty)
                ? const CircularProgressIndicator()
                : _grades.isEmpty
                ? const Center(
                    child: Text(
                      "لا توجد فصول مضافة حالياً",
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    itemCount: _grades.length,
                    itemBuilder: (context, index) {
                      final grade = _grades[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        child: Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(15),
                            title: Center(
                              child: Text(
                                grade,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onLongPress: null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttendancePage(
                                    grade: grade,
                                    type: widget.type,
                                    groupId: _myGroupId,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userSubscription?.close();
    _gradesSubscription?.cancel();
    super.dispose();
  }
}
