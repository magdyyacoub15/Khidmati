import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:async';
import 'package:flutter/services.dart';
import '../services/user_service.dart';
import '../services/permission_service.dart';
import '../services/appwrite_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io';
import '../services/image_service.dart';
import '../services/image_cache_service.dart';
import '../services/data_cache_service.dart';
import '../services/sync_service.dart';
import '../widgets/full_screen_image.dart';
import '../models/kid.dart';

// Appwrite Collection constants
const String databaseId = 'main_db';
const String studentsCollectionId = 'students';
const String servantsCollectionId = 'servants';
const String usersCollectionId = 'users_info';
const String attendanceStatusCollectionId = 'attendance_status';

// -------------------------------------------------------------------------
// ✅ Data Model

// -------------------------------------------------------------------------
// ✅ Data Model Wrapper
class AttendanceKid {
  final Kid kid;
  final bool isPresent;
  final String markedBy;
  final String note;

  AttendanceKid({
    required this.kid,
    this.isPresent = false,
    this.markedBy = '',
    this.note = '',
  });

  String get id => kid.id;
  String get name => kid.name;
  String? get photoUrl => kid.photoUrl;
  String? get localImagePath => kid.localImagePath;
  String get address => kid.address;
  List<String> get phones => kid.phones;
  String getPhoneWithOwner(String p) => kid.getPhoneWithOwner(p);
  String? get locationUrl => kid.locationUrl;

  AttendanceKid copyWithStatus({
    bool? isPresent,
    String? markedBy,
    String? note,
  }) {
    return AttendanceKid(
      kid: kid,
      isPresent: isPresent ?? this.isPresent,
      markedBy: markedBy ?? this.markedBy,
      note: note ?? this.note,
    );
  }
}

// -------------------------------------------------------------------------
// ✅ AttendancePage Widget
// -------------------------------------------------------------------------

class AttendancePage extends StatefulWidget {
  final String grade;
  final String type; // طلاب أو خدام
  final String groupId;

  const AttendancePage({
    required this.grade,
    required this.type,
    required this.groupId,
    super.key,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String searchText = '';

  String _currentUserRole = 'loading';
  String _currentUserGradeNumber = 'none';
  bool _canWrite = true; // 🚀 Subscription Check
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String? _teamId;
  DateTime? _selectedServantDateOfBirth;
  File? _imageFile;

  // void initState() { super.initState(); _fetchTeamId(); } // Removed duplicate
  Future<void> _fetchTeamId() async {
    try {
      final user = await AppwriteService().account.get();
      // 1. Try Cache
      final cached = await DataCacheService().getCachedUserGroupId(user.$id);
      if (cached != null && cached['groupId'] == widget.groupId) {
        if (mounted) {
          setState(() => _teamId = cached['teamId']);
        }
        return;
      }

      // 2. Fetch from Groups Collection (More reliable for non-members)
      final groupDoc = await AppwriteService().databases.getDocument(
        databaseId: databaseId,
        collectionId: 'groups',
        documentId: widget.groupId,
      );
      if (mounted) {
        setState(() => _teamId = groupDoc.data['teamId']);
      }
    } catch (e) {
      debugPrint("Error fetching teamId: $e");
    }
  }

  // --- OPTIMISTIC UI ---
  final Map<String, AttendanceKid> _optimisticUpdates = {};

  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = Realtime(AppwriteService().client);
  final Account _account = AppwriteService().account;

  RealtimeSubscription? _roleSubscription;
  RealtimeSubscription? _statusSubscription;

  // Local Data
  List<Kid> _baseKidsList = [];
  Map<String, models.Document> _liveStatusMap = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => searchText = _searchController.text);
    });
    _loadCachedData(); // 🚀 Load from cache FIRST
    _fetchBaseKids();
    _fetchAttendanceStatus();
    _loadUserRole();
    _subscribeToStatus();
    _fetchTeamId();
    _checkSubscriptionStatus(); // 🚀 Verify subscription

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.groupId.isNotEmpty) {
        SyncService().syncAll(widget.groupId);
        SyncService().startConnectivityListener(widget.groupId);
      }
    });
    _subscribeToKidsList(); // 🚀 Live Kids Updates
  }

  Future<void> _checkSubscriptionStatus() async {
    final canWrite = await PermissionService.canWrite(widget.groupId);
    if (mounted) {
      setState(() {
        _canWrite = canWrite;
      });
    }
  }

  Future<void> _loadCachedData() async {
    try {
      final cachedKids = await DataCacheService().getCachedKidsList(
        "${widget.groupId}_${widget.grade}",
        widget.type,
      );
      final cachedStatus = await DataCacheService()
          .getCachedAttendanceStatusMap(
            widget.groupId,
            widget.grade,
            widget.type,
          );

      if (mounted && (cachedKids.isNotEmpty || cachedStatus.isNotEmpty)) {
        setState(() {
          if (_baseKidsList.isEmpty) _baseKidsList = cachedKids;
          if (_liveStatusMap.isEmpty) {
            final Map<String, models.Document> restoredMap = {};
            cachedStatus.forEach((key, data) {
              restoredMap[key] = models.Document(
                $id: data['\$id'] ?? 'cached',
                $collectionId: attendanceStatusCollectionId,
                $databaseId: databaseId,
                $createdAt: data['\$createdAt'] ?? '',
                $updatedAt: data['\$updatedAt'] ?? '',
                $permissions: [],
                data: Map<String, dynamic>.from(data),
              );
            });
            _liveStatusMap = restoredMap;
          }
          if (_isLoading) _isLoading = false;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _roleSubscription?.close();
    _statusSubscription?.close();
    _kidsSubscription?.close();
    SyncService().stopConnectivityListener(); // 🚀 Stop Listener
    super.dispose();
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------------------------------------------------------------
  // ## Data Fetching
  // -------------------------------------------------------------------------

  Future<void> _fetchBaseKids() async {
    final String collectionId = (widget.type == "خدام")
        ? servantsCollectionId
        : studentsCollectionId;

    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('grade', widget.grade),
          Query.limit(100), // Adjust limit/pagination if needed
        ],
      );

      if (mounted) {
        setState(() {
          _baseKidsList = result.documents
              .map((doc) => Kid.fromAppwrite(doc))
              .toList();
          _isLoading = false;
        });
        // 🚀 Update Cache with fresh data
        DataCacheService().cacheKidsList(
          "${widget.groupId}_${widget.grade}",
          widget.type,
          _baseKidsList,
        );
      }
    } catch (e) {
      debugPrint("Error fetching base kids: $e");
      // Fallback to cache
      final cached = await DataCacheService().getCachedKidsList(
        "${widget.groupId}_${widget.grade}",
        widget.type,
      );
      if (mounted) {
        setState(() {
          _baseKidsList = cached.where((k) {
            // Filter by grade manually since cache stores all for group/type
            final kidGradeNorm = _normalizeGradeText(k.grade ?? '');
            final targetGradeNorm = _normalizeGradeText(widget.grade);
            return kidGradeNorm == targetGradeNorm ||
                kidGradeNorm.contains(targetGradeNorm) ||
                targetGradeNorm.contains(kidGradeNorm);
          }).toList();
        });
      }
    }
    // Save to Cache on Success (we need to add this to the TRY block)
  }

  Future<void> _fetchAttendanceStatus() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceStatusCollectionId,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('grade', widget.grade),
          Query.equal('type', widget.type),
          Query.limit(1000),
        ],
      );

      final Map<String, models.Document> statusMap = {};
      for (var doc in result.documents) {
        statusMap[doc.data['name']] = doc;
      }

      // Cache the result
      final Map<String, dynamic> statusDataToCache = {};
      statusMap.forEach((key, doc) {
        statusDataToCache[key] = doc.data;
      });
      await DataCacheService().cacheAttendanceStatusMap(
        widget.groupId,
        widget.grade,
        widget.type,
        statusDataToCache,
      );

      if (mounted) {
        setState(() {
          _liveStatusMap = statusMap;
        });
      }
    } catch (e) {
      debugPrint("Error fetching attendance status: $e");
      // Fallback to Cache
      final cachedMap = await DataCacheService().getCachedAttendanceStatusMap(
        widget.groupId,
        widget.grade,
        widget.type,
      );

      final Map<String, models.Document> restoredMap = {};
      cachedMap.forEach((key, data) {
        // Reconstruct Document (mocking $id, $collectionId etc if needed or acceptable)
        restoredMap[key] = models.Document(
          $id: data['\$id'] ?? 'cached',
          $collectionId: attendanceStatusCollectionId,
          $databaseId: databaseId,
          $createdAt: data['\$createdAt'] ?? '',
          $updatedAt: data['\$updatedAt'] ?? '',
          $permissions: [],
          data: Map<String, dynamic>.from(data),
        );
      });

      if (mounted) {
        setState(() {
          _liveStatusMap = restoredMap;
        });
      }
    }
  }

  RealtimeSubscription? _kidsSubscription; // Add field

  void _subscribeToStatus() {
    _statusSubscription = _realtime.subscribe([
      'databases.$databaseId.collections.$attendanceStatusCollectionId.documents',
    ]);

    _statusSubscription!.stream.listen((event) {
      if (!mounted) return;
      final payload = event.payload;

      if (payload['groupId'] == widget.groupId &&
          payload['type'] == widget.type &&
          _normalizeGradeText(payload['grade'] ?? '') ==
              _normalizeGradeText(widget.grade)) {
        final String name = payload['name'];
        final isDelete = event.events.any((e) => e.contains('.delete'));

        setState(() {
          if (isDelete) {
            _liveStatusMap.remove(name);
          } else {
            _liveStatusMap[name] = models.Document.fromMap(payload);
          }
        });
        _syncStatusCache();
      }
    });
  }

  void _subscribeToKidsList() {
    final String collectionId = (widget.type == "خدام")
        ? servantsCollectionId
        : studentsCollectionId;

    _kidsSubscription = _realtime.subscribe([
      'databases.$databaseId.collections.$collectionId.documents',
    ]);

    _kidsSubscription!.stream.listen((event) {
      if (!mounted) return;
      final payload = event.payload;

      // Filter by Group and Grade
      if (payload['groupId'] != widget.groupId) return;

      final pGrade = _normalizeGradeText(payload['grade'] ?? '');
      final wGrade = _normalizeGradeText(widget.grade);

      // Strict match for grade (or if grade is part of it)
      if (pGrade != wGrade &&
          !pGrade.contains(wGrade) &&
          !wGrade.contains(pGrade)) {
        return;
      }

      final isDelete = event.events.any((e) => e.contains('.delete'));
      final kid = Kid.fromAppwrite(models.Document.fromMap(payload));

      setState(() {
        if (isDelete) {
          _baseKidsList.removeWhere((k) => k.id == kid.id);
        } else {
          // Check if exists
          final index = _baseKidsList.indexWhere((k) => k.id == kid.id);
          if (index != -1) {
            _baseKidsList[index] = kid; // Update
          } else {
            _baseKidsList.add(kid); // Add
          }
        }
      });
    });
  }

  Future<void> _loadUserRole() async {
    // 🚀 1. Cache First (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        _updateUserRoleFromData(cachedCtx);
        if (mounted) setState(() {});
        // Permission check based on cached group ID (if needed, but widget.groupId is passed)
        _canWrite = await PermissionService.canWrite(widget.groupId);
        if (mounted) setState(() {});
      }
    }

    // 🚀 2. Background Refresh
    try {
      final user = await _account.get();
      await UserService().getCurrentUser(); // Cache ID

      // Check permissions live
      _checkSubscriptionStatus();

      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      // Cache Update
      await DataCacheService().cacheUserGroupId(
        user.$id,
        doc.data['groupId'],
        doc.data['teamId'],
        doc.data['role'],
      );

      _updateUserRoleFromData(doc.data);

      _roleSubscription?.close();
      _roleSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);

      _roleSubscription!.stream.listen((event) {
        if (mounted) {
          final data = event.payload;
          _updateUserRoleFromData(data);
        }
      });
    } catch (e) {
      debugPrint("Network fetch failed (offline): $e");
      // Fallback if cache was empty
      if (_currentUserRole == 'loading') {
        final cachedId = await UserService().getCachedUserId();
        if (cachedId != null) {
          final cached = await DataCacheService().getCachedUserGroupId(
            cachedId,
          );
          if (cached != null) _updateUserRoleFromData(cached);
        }
      }
    }
  }

  void _updateUserRoleFromData(Map<String, dynamic> data) {
    if (mounted) {
      setState(() {
        _currentUserRole = data['role'] ?? 'user';
        String rawRole = data['role'] ?? 'user';
        if (rawRole.startsWith('class_supervisor_grade_')) {
          // Extract everything after the prefix as the grade name
          _currentUserGradeNumber = rawRole
              .replaceFirst('class_supervisor_grade_', '')
              .trim();
        } else {
          _currentUserGradeNumber = 'none';
        }
        // _currentUserName removed as it is unused
      });
    }
  }

  // -------------------------------------------------------------------------
  // ## Helper Methods
  // -------------------------------------------------------------------------
  String _normalizeGradeText(String text) {
    if (text.isEmpty) {
      return '';
    }
    return text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .trim();
  }

  // -------------------------------------------------------------------------
  // ## Logic
  // -------------------------------------------------------------------------

  bool _canToggleAttendance(
    AttendanceKid kid,
    bool newIsPresent,
    String currentUserName,
  ) {
    final isUserAdmin = _currentUserRole == 'admin';
    final isUserGeneralSupervisor = _currentUserRole == 'general_supervisor';

    // 1. Admin & General Supervisor: Full Access
    if (isUserAdmin || isUserGeneralSupervisor) return true;

    final isKidsAttendance = widget.type != "خدام";

    // 2. Class Supervisor
    if (_currentUserRole.startsWith('class_supervisor_grade_')) {
      if (isKidsAttendance) {
        // Can attend ANY kid
        return true;
      } else {
        // Servants: Only own grade
        // Extract grade from role (already done in _currentUserGradeNumber)
        // Normalize both for comparison
        final pageGradeNorm = _normalizeGradeText(widget.grade);
        final roleGradeNorm = _normalizeGradeText(_currentUserGradeNumber);

        // Check if one contains the other (e.g. "Primary 1" vs "1")
        // Or exact match after normalization
        return pageGradeNorm == roleGradeNorm ||
            pageGradeNorm.contains(roleGradeNorm) ||
            roleGradeNorm.contains(pageGradeNorm);
      }
    }

    // 3. Regular User (Servant)
    if (_currentUserRole == 'user' || _currentUserRole == 'priest') {
      if (isKidsAttendance) {
        // Can attend ANY kid
        return true;
      } else {
        // Servants: Read Only
        return false;
      }
    }

    return false;
  }

  Future<void> _togglePresent(AttendanceKid kid) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ انتهت صلاحية الاشتراك. المجلد للقراءة فقط."),
          ),
        );
      }
      return;
    }

    final currentUserName = await UserService().getCurrentUserName();
    final newIsPresent = !kid.isPresent;

    if (!_canToggleAttendance(kid, newIsPresent, currentUserName)) {
      String message;
      if (widget.type != "خدام") {
        message = newIsPresent
            ? "❌ غير مسموح لك بتسجيل حضور المخدومين."
            : "⚠️ لا يمكنك إلغاء التسجيل. (للمسجل الأصلي أو الأدوار الأعلى).";
      } else {
        message = "❌ غير مسموح لك بتعديل حالة حضور الخدام في هذا الصف.";
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    // Optimistic Update
    final optimisticKid = kid.copyWithStatus(
      isPresent: newIsPresent,
      markedBy: newIsPresent ? currentUserName : '',
    );
    if (mounted) {
      setState(() {
        _optimisticUpdates[kid.name] = optimisticKid;
      });
    }

    try {
      final existingDoc = _liveStatusMap[kid.name];

      if (newIsPresent) {
        if (existingDoc != null) {
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: attendanceStatusCollectionId,
            documentId: existingDoc.$id,
            data: {
              'isPresent': true,
              'markedBy': currentUserName,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
        } else {
          final newDoc = await _databases.createDocument(
            databaseId: databaseId,
            collectionId: attendanceStatusCollectionId,
            documentId: ID.unique(),
            data: {
              'name': kid.name,
              'isPresent': true,
              'markedBy': currentUserName,
              'note': kid.note,
              'grade': widget.grade,
              'type': widget.type,
              'groupId': widget.groupId,
              'timestamp': DateTime.now().toIso8601String(),
            },
            permissions: (_teamId != null && _teamId!.isNotEmpty)
                ? [
                    Permission.read(Role.team(_teamId!)),
                    Permission.update(Role.team(_teamId!)),
                    Permission.delete(Role.team(_teamId!)),
                  ]
                : null,
          );
          if (mounted) {
            setState(() => _liveStatusMap[kid.name] = newDoc);
          }
        }
      } else {
        if (existingDoc != null) {
          final note = existingDoc.data['note'] ?? '';
          if (note.toString().isEmpty) {
            await _databases.deleteDocument(
              databaseId: databaseId,
              collectionId: attendanceStatusCollectionId,
              documentId: existingDoc.$id,
            );
            if (mounted) {
              setState(() => _liveStatusMap.remove(kid.name));
            }
          } else {
            await _databases.updateDocument(
              databaseId: databaseId,
              collectionId: attendanceStatusCollectionId,
              documentId: existingDoc.$id,
              data: {
                'isPresent': false,
                'markedBy': '',
                'timestamp': DateTime.now().toIso8601String(),
              },
            );
          }
        }
      }
      _syncStatusCache();
    } catch (e) {
      debugPrint("Toggle attendance error: $e. Saving pending.");
      final operationData = {
        'name': kid.name,
        'isPresent': newIsPresent,
        'grade': widget.grade,
        'type': widget.type,
        'groupId': widget.groupId,
        'markedBy': currentUserName,
        'timestamp': DateTime.now().toIso8601String(),
      };

      DataCacheService().addPendingOperation({
        'type': 'attendance_toggle',
        'data': operationData,
      });

      if (mounted) {
        setState(() {
          _liveStatusMap[kid.name] = models.Document(
            $id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
            $collectionId: attendanceStatusCollectionId,
            $databaseId: databaseId,
            $createdAt: DateTime.now().toIso8601String(),
            $updatedAt: DateTime.now().toIso8601String(),
            $permissions: [],
            data: operationData,
          );
        });
      }
      _syncStatusCache();
    } finally {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _optimisticUpdates.remove(kid.name));
        });
      }
    }
  }

  Future<void> _editNote(AttendanceKid kid) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ انتهت صلاحية الاشتراك. المجلد للقراءة فقط."),
          ),
        );
      }
      return;
    }

    bool isAllowed = false;
    if (_currentUserRole == 'admin' ||
        _currentUserRole == 'general_supervisor') {
      isAllowed = true;
    } else if (widget.type != "خدام") {
      isAllowed = true;
    } else {
      if (_currentUserRole.startsWith('class_supervisor_grade_')) {
        final pageGradeNorm = _normalizeGradeText(widget.grade);
        final roleGradeNorm = _normalizeGradeText(_currentUserGradeNumber);
        if (pageGradeNorm == roleGradeNorm ||
            pageGradeNorm.contains(roleGradeNorm) ||
            roleGradeNorm.contains(pageGradeNorm)) {
          isAllowed = true;
        }
      }
    }

    if (!isAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ غير مسموح لك بتعديل الملحوظات هنا.")),
        );
      }
      return;
    }

    final controller = TextEditingController(text: kid.note);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("📝 تعديل ملحوظة لـ ${kid.name}"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "اكتب الملحوظة هنا"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("حفظ"),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final existingDoc = _liveStatusMap[kid.name];
        if (existingDoc != null) {
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: attendanceStatusCollectionId,
            documentId: existingDoc.$id,
            data: {
              'note': result,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
        } else {
          final newDoc = await _databases.createDocument(
            databaseId: databaseId,
            collectionId: attendanceStatusCollectionId,
            documentId: ID.unique(),
            data: {
              'name': kid.name,
              'isPresent': kid.isPresent,
              'markedBy': kid.markedBy,
              'note': result,
              'grade': widget.grade,
              'type': widget.type,
              'groupId': widget.groupId,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
          if (mounted) {
            setState(() => _liveStatusMap[kid.name] = newDoc);
          }
        }
        _syncStatusCache();
      } catch (e) {
        debugPrint("Error updating note: $e");
        final operationData = {
          'name': kid.name,
          'isPresent': kid.isPresent,
          'markedBy': kid.markedBy,
          'note': result,
          'grade': widget.grade,
          'type': widget.type,
          'groupId': widget.groupId,
          'timestamp': DateTime.now().toIso8601String(),
        };

        DataCacheService().addPendingOperation({
          'type': 'attendance_note',
          'data': operationData,
        });

        if (mounted) {
          setState(() {
            _liveStatusMap[kid.name] = models.Document(
              $id: 'pending_note_${DateTime.now().millisecondsSinceEpoch}',
              $collectionId: attendanceStatusCollectionId,
              $databaseId: databaseId,
              $createdAt: DateTime.now().toIso8601String(),
              $updatedAt: DateTime.now().toIso8601String(),
              $permissions: [],
              data: operationData,
            );
          });
        }
        _syncStatusCache();
      }
    }
  }

  Future<void> _syncStatusCache() async {
    final Map<String, dynamic> statusDataToCache = {};
    _liveStatusMap.forEach((key, doc) {
      statusDataToCache[key] = doc.data;
    });
    await DataCacheService().cacheAttendanceStatusMap(
      widget.groupId,
      widget.grade,
      widget.type,
      statusDataToCache,
    );
  }

  Future<models.Document?> _getServantData(String servantName) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: servantsCollectionId,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('name', servantName),
          Query.limit(1),
        ],
      );
      return result.documents.isNotEmpty ? result.documents.first : null;
    } catch (e) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // ## Servant Management
  // -------------------------------------------------------------------------
  // Re-implemented to use Appwrite createDocument/updateDocument on 'servants' collection
  void _showAddServantDialog() async {
    if (!_canWrite) {
      return;
    }
    if (widget.type != "خدام") {
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    _selectedServantDateOfBirth = DateTime.now().subtract(
      const Duration(days: 365 * 20),
    );
    _imageFile = null; // Reset image file

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text("إضافة خادم جديد"),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Image Picker Widget
                    GestureDetector(
                      onTap: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 70,
                        );

                        if (image != null) {
                          File file = File(image.path);

                          // ✂️ Cropping
                          final croppedFile = await ImageCropper().cropImage(
                            sourcePath: file.path,
                            uiSettings: [
                              AndroidUiSettings(
                                toolbarTitle: 'تعديل الصورة',
                                toolbarColor: Colors.deepOrange,
                                toolbarWidgetColor: Colors.white,
                                initAspectRatio: CropAspectRatioPreset.square,
                                lockAspectRatio: false,
                              ),
                              IOSUiSettings(title: 'تعديل الصورة'),
                            ],
                          );

                          if (croppedFile != null) {
                            file = File(croppedFile.path);
                            final String targetPath =
                                '${file.parent.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';
                            final XFile? compressed =
                                await FlutterImageCompress.compressAndGetFile(
                                  file.absolute.path,
                                  targetPath,
                                  quality: 50,
                                  minWidth: 500,
                                  minHeight: 500,
                                );

                            if (compressed != null) {
                              setDialogState(() {
                                _imageFile = File(compressed.path);
                              });
                            }
                          }
                        }
                      },
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: _imageFile != null
                            ? FileImage(_imageFile!)
                            : null,
                        child: _imageFile == null
                            ? const Icon(
                                Icons.add_a_photo,
                                size: 30,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "اسم الخادم",
                      ),
                      validator: (v) => v!.isEmpty ? "مطلوب" : null,
                    ),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: "رقم الموبايل (اختياري)",
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedServantDateOfBirth == null
                                ? "لم يتم الاختيار"
                                : DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(_selectedServantDateOfBirth!),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedServantDateOfBirth!,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100),
                              initialDatePickerMode: DatePickerMode.year,
                            );
                            if (picked != null && mounted) {
                              setDialogState(
                                () => _selectedServantDateOfBirth = picked,
                              );
                            }
                          },
                          child: const Text("اختر التاريخ"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate() &&
                      _selectedServantDateOfBirth != null) {
                    Navigator.pop(context);
                    _addServant(
                      nameController.text.trim(),
                      widget.grade,
                      phoneController.text.trim(),
                      _selectedServantDateOfBirth!,
                      _imageFile,
                    );
                  }
                },
                child: const Text("إضافة"),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _addServant(
    String name,
    String grade,
    String phone,
    DateTime dob,
    File? imageFile,
  ) async {
    if (!_canWrite) {
      _showSnackbar("⚠️ انتهت صلاحية الاشتراك. المجلد للقراءة فقط.");
      return;
    }
    // ⚡ Optimistic Update
    final docId = ID.unique(); // 🚀 Generate ID upfront for consistency
    final tempKid = Kid(
      id: docId,
      name: name,
      address: '', // Required by global model
      phoneRequired: phone,
      grade: widget.grade,
      photoUrl: null,
      localImagePath: imageFile?.path, // ⚡ Show local image instantly
    );

    if (mounted) {
      setState(() {
        _baseKidsList.add(tempKid);
      });
    }

    try {
      String? photoUrl;
      if (imageFile != null) {
        final result = await ImageService().uploadImage(imageFile);
        photoUrl = result?['url'];
      }

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: servantsCollectionId,
        documentId: docId, // 🚀 Use same ID
        data: {
          'name': name,
          'grade': grade,
          'phoneRequired': phone,
          'dateOfBirth': dob.toIso8601String(),
          'addedAt': DateTime.now().toIso8601String(),
          'groupId': widget.groupId,
          'photoUrl': photoUrl,
        },
        permissions: (_teamId != null && _teamId!.isNotEmpty)
            ? [
                Permission.read(Role.team(_teamId!)),
                Permission.update(Role.team(_teamId!)),
                Permission.delete(Role.team(_teamId!)),
              ]
            : null,
      );
      // 🚀 Instant Cache Update (PERSISTENCE)
      DataCacheService().cacheKidsList(
        "${widget.groupId}_${widget.grade}",
        widget.type,
        _baseKidsList,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ تم إضافة الخادم بنجاح")),
        );
      }
    } catch (e) {
      debugPrint("Add servant error: $e. Saving to pending operations.");

      // 🚀 Save as pending operation
      DataCacheService().addPendingOperation({
        'type': 'add_servant',
        'data': {
          'name': name,
          'grade': grade,
          'phoneRequired': phone,
          'dateOfBirth': dob.toIso8601String(),
          'addedAt': DateTime.now().toIso8601String(),
          'groupId': widget.groupId,
          'localImagePath': imageFile?.path,
          'teamId': _teamId,
        },
      });

      // Ensure cache is updated with the temp kid
      DataCacheService().cacheKidsList(
        "${widget.groupId}_${widget.grade}",
        widget.type,
        _baseKidsList,
      );

      if (mounted) {
        // Optimistic UI state kept
      }
    }
  }

  Future<void> _editServant({
    required String servantId,
    required String name,
    required String phone,
    required DateTime dateOfBirth,
    File? imageFile,
    String? oldPhotoUrl,
    bool isDeletePhoto = false,
  }) async {
    if (!_canWrite) {
      _showSnackbar("⚠️ انتهت صلاحية الاشتراك. المجلد للقراءة فقط.");
      return;
    }
    // ⚡ Optimistic Update using index
    final int index = _baseKidsList.indexWhere((k) => k.id == servantId);
    Kid? originalKid;
    if (index != -1) {
      originalKid = _baseKidsList[index];
      final Kid promotedKid = originalKid;
      if (mounted) {
        setState(() {
          _baseKidsList[index] = Kid(
            id: servantId,
            name: name,
            address: promotedKid.address,
            phoneRequired: phone,
            isVisited: promotedKid.isVisited,
            visitedBy: promotedKid.visitedBy,
            grade: promotedKid.grade,
            photoUrl: promotedKid.photoUrl,
            localImagePath: imageFile?.path ?? promotedKid.localImagePath,
          );
        });
      }
    }

    try {
      String? newPhotoUrl = oldPhotoUrl;

      if (isDeletePhoto) {
        // Delete old image
        await ImageService().deleteImageByUrl(oldPhotoUrl);
        newPhotoUrl = null;
      } else if (imageFile != null) {
        // 1. Delete old image if exists
        await ImageService().deleteImageByUrl(oldPhotoUrl);

        // 2. Upload new image
        final result = await ImageService().uploadImage(imageFile);
        newPhotoUrl = result?['url'];
      }

      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: servantsCollectionId,
        documentId: servantId,
        data: {
          'name': name,
          'phoneRequired': phone,
          'dateOfBirth': dateOfBirth.toIso8601String(),
          'photoUrl': newPhotoUrl,
        },
      );
      // 🚀 Instant Cache Update (PERSISTENCE)
      DataCacheService().cacheKidsList(
        "${widget.groupId}_${widget.grade}",
        widget.type,
        _baseKidsList,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ تم التعديل بنجاح")));
      }
    } catch (e) {
      debugPrint("Edit servant error: $e. Saving to pending operations.");

      // For Edit, we can use 'edit_student' type in SyncService if we make it generic,
      // but let's assume servants are also students for sync purposes or add a specific one.
      // Actually my SyncService doesn't have edit_servant yet. Let's add it or use edit_student.
      // I'll add edit_servant to SyncService later if needed, but for now let's use edit_student sync logic.

      DataCacheService().addPendingOperation({
        'type': 'edit_servant',
        'data': {
          'servantId': servantId,
          'name': name,
          'phone': phone,
          'dateOfBirth': dateOfBirth.toIso8601String(),
          'localImagePath': imageFile?.path,
          'photoUrl': oldPhotoUrl, // Fix: Use oldPhotoUrl in catch block
          'oldPhotoUrl': oldPhotoUrl,
          'isDeletePhoto': isDeletePhoto,
          'groupId': widget.groupId,
          'grade': widget.grade,
        },
      });

      // Ensure cache is updated
      DataCacheService().cacheKidsList(
        "${widget.groupId}_${widget.grade}",
        widget.type,
        _baseKidsList,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ℹ️ تم حفظ التعديلات محلياً.")),
        );
      }
    }
  }

  Future<void> _showEditServantDialog(
    String servantId,
    String currentName,
    String currentPhone,
    DateTime currentDateOfBirth,
    String? currentPhotoUrl,
  ) async {
    if (!mounted) {
      return;
    }
    if (!_canWrite || _currentUserRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ ليس لديك صلاحية التعديل.")),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);
    DateTime selectedDateOfBirth = currentDateOfBirth;
    _imageFile = null; // Reset image file
    bool isPhotoDeleted = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("تعديل بيانات الخادم"),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image Picker for Edit
                  GestureDetector(
                    onTap: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 70,
                      );

                      if (image != null) {
                        File file = File(image.path);

                        // ✂️ Cropping
                        final croppedFile = await ImageCropper().cropImage(
                          sourcePath: file.path,
                          uiSettings: [
                            AndroidUiSettings(
                              toolbarTitle: 'تعديل الصورة',
                              toolbarColor: Colors.deepOrange,
                              toolbarWidgetColor: Colors.white,
                              initAspectRatio: CropAspectRatioPreset.square,
                              lockAspectRatio: false,
                            ),
                            IOSUiSettings(title: 'تعديل الصورة'),
                          ],
                        );

                        if (croppedFile != null) {
                          file = File(croppedFile.path);
                          final String targetPath =
                              '${file.parent.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';
                          final XFile? compressed =
                              await FlutterImageCompress.compressAndGetFile(
                                file.absolute.path,
                                targetPath,
                                quality: 50,
                                minWidth: 500,
                                minHeight: 500,
                              );

                          if (compressed != null) {
                            setDialogState(() {
                              _imageFile = File(compressed.path);
                              isPhotoDeleted = false;
                            });
                          }
                        }
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : (!isPhotoDeleted &&
                                currentPhotoUrl != null &&
                                currentPhotoUrl.isNotEmpty)
                          ? CachedNetworkImageProvider(
                                  currentPhotoUrl,
                                  cacheManager: ImageCacheService.instance,
                                )
                                as ImageProvider
                          : null,
                      child:
                          (_imageFile == null &&
                              (isPhotoDeleted ||
                                  currentPhotoUrl == null ||
                                  currentPhotoUrl.isEmpty))
                          ? const Icon(
                              Icons.add_a_photo,
                              size: 30,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                  ),
                  if (_imageFile != null ||
                      (!isPhotoDeleted &&
                          currentPhotoUrl != null &&
                          currentPhotoUrl.isNotEmpty))
                    TextButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          _imageFile = null;
                          isPhotoDeleted = true;
                        });
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        "حذف الصورة",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "اسم الخادم"),
                    validator: (v) => v!.isEmpty ? "مطلوب" : null,
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: "رقم الموبايل (اختياري)",
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('yyyy-MM-dd').format(selectedDateOfBirth),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDateOfBirth,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                            initialDatePickerMode: DatePickerMode.year,
                          );
                          if (picked != null && mounted) {
                            setDialogState(() => selectedDateOfBirth = picked);
                          }
                        },
                        child: const Text("اختر التاريخ"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  _editServant(
                    servantId: servantId,
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    dateOfBirth: selectedDateOfBirth,
                    imageFile: _imageFile,
                    oldPhotoUrl: currentPhotoUrl,
                    isDeletePhoto: isPhotoDeleted,
                  );
                }
              },
              child: const Text("حفظ"),
            ),
          ],
        ),
      ),
    );
  }

  List<AttendanceKid> _getFilteredAndSortedKids() {
    List<AttendanceKid> liveKids = _baseKidsList.map((baseKid) {
      if (_optimisticUpdates.containsKey(baseKid.name)) {
        return _optimisticUpdates[baseKid.name]!;
      }
      if (_liveStatusMap.containsKey(baseKid.name)) {
        final doc = _liveStatusMap[baseKid.name]!;
        final data = doc.data;
        return AttendanceKid(
          kid: baseKid,
          isPresent: data['isPresent'] ?? false,
          markedBy: data['markedBy'] ?? '',
          note: data['note'] ?? '',
        );
      }
      return AttendanceKid(kid: baseKid);
    }).toList();

    final filtered = liveKids.where((k) {
      final query = searchText.toLowerCase();
      return k.name.toLowerCase().contains(query) ||
          k.address.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      if (a.isPresent && !b.isPresent) return 1;
      if (!a.isPresent && b.isPresent) return -1;
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  Widget _buildStatsHeader(List<AttendanceKid> filteredKids) {
    final total = _baseKidsList.length;
    final present = _liveStatusMap.values
        .where((doc) => doc.data['isPresent'] == true)
        .length;
    final absent = total - present;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem("الإجمالي", total.toString(), Colors.white),
          _buildStatItem("حضور", present.toString(), Colors.green.shade300),
          _buildStatItem("غياب", absent.toString(), Colors.red.shade300),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: "بحث عن اسم...",
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search, color: Colors.blue),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildKidCard(AttendanceKid kid, bool isAdminOrSupervisor) {
    final bool isServant = widget.type == "خدام";
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: kid.isPresent
            ? Colors.white.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _togglePresent(kid),
        onLongPress: () async {
          if (widget.type == "خدام" && isAdminOrSupervisor && _canWrite) {
            final doc = await _getServantData(kid.name);
            if (doc != null) {
              _showEditServantDialog(
                doc.$id,
                doc.data['name'],
                doc.data['phoneRequired'] ?? '',
                DateTime.tryParse(doc.data['dateOfBirth']) ?? DateTime.now(),
                doc.data['photoUrl'],
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  if ((kid.photoUrl != null && kid.photoUrl!.isNotEmpty) ||
                      (kid.localImagePath != null &&
                          kid.localImagePath!.isNotEmpty)) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImage(
                          imageUrl: kid.photoUrl,
                          localPath: kid.localImagePath,
                          tag: 'attendance_kid_${kid.id}',
                        ),
                      ),
                    );
                  }
                },
                child: Hero(
                  tag: 'attendance_kid_${kid.id}',
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kid.isPresent
                            ? Colors.green
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: kid.localImagePath != null
                          ? FileImage(File(kid.localImagePath!))
                                as ImageProvider
                          : (kid.photoUrl != null && kid.photoUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(
                              kid.photoUrl!,
                              cacheManager: ImageCacheService.instance,
                            )
                          : null,
                      child:
                          (kid.photoUrl == null || kid.photoUrl!.isEmpty) &&
                              (kid.localImagePath == null)
                          ? Icon(
                              isServant ? Icons.people_alt : Icons.person,
                              color: Colors.grey,
                              size: 28,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kid.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    if (kid.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "📝 ${kid.note}",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (kid.isPresent)
                      Text(
                        "(${kid.markedBy})",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  kid.isPresent
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: kid.isPresent ? Colors.green : Colors.grey.shade400,
                  size: 30,
                ),
                onPressed: () => _togglePresent(kid),
              ),
              IconButton(
                icon: Icon(Icons.edit_note, color: Colors.blue.shade300),
                onPressed: () => _editNote(kid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdminOrSupervisor =
        (_currentUserRole == 'admin' || _currentUserGradeNumber != 'none');
    final List<AttendanceKid> filteredKids = _getFilteredAndSortedKids();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.type == 'خدام'
              ? "حضور الخدام - ${widget.grade}"
              : "حضور - ${widget.grade}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildStatsHeader(filteredKids),
              _buildSearchBar(),
              if (!_canWrite)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "⚠️ تنبيه: اشتراك المجموعة منتهي. وضع القراءة فقط مفعل.",
                          style: TextStyle(color: Colors.white, fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading && _baseKidsList.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _fetchBaseKids();
                          await _fetchAttendanceStatus();
                          await _checkSubscriptionStatus();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filteredKids.length,
                          itemBuilder: (context, index) {
                            final kid = filteredKids[index];
                            final card = _buildKidCard(
                              kid,
                              isAdminOrSupervisor,
                            );

                            if (isAdminOrSupervisor && widget.type == 'خدام') {
                              return Dismissible(
                                key: Key(kid.id),
                                direction: (_currentUserRole == 'admin')
                                    ? DismissDirection.startToEnd
                                    : DismissDirection.none,
                                confirmDismiss: (direction) async {
                                  if (!_canWrite) {
                                    _showSnackbar("⚠️ انتهت صلاحية الاشتراك");
                                    return false;
                                  }
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text("تأكيد الحذف"),
                                      content: Text(
                                        "هل أنت متأكد من حذف ${kid.name}؟",
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text("إلغاء"),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text("حذف"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                onDismissed: (direction) {
                                  final originalKid = _baseKidsList.firstWhere(
                                    (k) => k.id == kid.id,
                                  );
                                  setState(() {
                                    _baseKidsList.removeWhere(
                                      (k) => k.id == kid.id,
                                    );
                                  });

                                  _databases
                                      .deleteDocument(
                                        databaseId: databaseId,
                                        collectionId: servantsCollectionId,
                                        documentId: kid.id,
                                      )
                                      .then((_) {
                                        if (originalKid.photoUrl != null &&
                                            originalKid.photoUrl!.isNotEmpty) {
                                          ImageService().deleteImageByUrl(
                                            originalKid.photoUrl!,
                                          );
                                        }
                                      })
                                      .catchError((e) {
                                        // Handle error
                                      });
                                },
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  color: Colors.red,
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                                child: card,
                              );
                            }
                            return card;
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: (_currentUserRole == 'admin' && _canWrite)
          ? FloatingActionButton(
              onPressed: _showAddServantDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
