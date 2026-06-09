import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'appwrite_service.dart';
import 'data_cache_service.dart';
import 'permission_service.dart';
import 'image_service.dart';
import 'status_service.dart';
import 'package:universal_io/io.dart';
import '../models/kid.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Databases _databases = AppwriteService().databases;
  final ImageService _imageService = ImageService();
  final DataCacheService _cache = DataCacheService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  // 🚀 Connectivity Listener
  Timer? _connectivityTimer;
  bool _isConnected = false;

  // 🚀 Sync Events Stream
  final StreamController<void> _syncController =
      StreamController<void>.broadcast();
  Stream<void> get onSyncComplete => _syncController.stream;

  void startConnectivityListener(String groupId) {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final hasConnection = await _checkInternet();
      if (hasConnection && !_isConnected) {
        debugPrint("🌐 Internet Restored! Triggering Auto-Sync & Refresh...");
        _isConnected = true;
        await syncAll(groupId);

        // 🚀 Only refresh cache if sync was completely successful (queue is empty)
        final remaining = await _cache.getPendingOperations();
        if (remaining.isEmpty) {
          await _refreshAllCache(groupId); // Pull fresh data
        } else {
          debugPrint(
            "⚠️ Sync partially failed, skipping global refresh to prevent data loss.",
          );
        }
      } else if (!hasConnection) {
        _isConnected = false;
      }
    });
  }

  void stopConnectivityListener() {
    _connectivityTimer?.cancel();
  }

  Future<bool> isOnline() async {
    if (kIsWeb) {
      return true; // 🚀 Web: Assume connected or let browser handle it
    }
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkInternet() => isOnline();

  // 🚀 Sync Everything (Push Pending + Pull Fresh)
  Future<void> syncAll(String groupId) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final List<Map<String, dynamic>> pendingOps = await _cache
          .getPendingOperations(groupId: groupId);
      if (pendingOps.isEmpty) {
        _isSyncing = false;
        return;
      }

      // 1. Check Permission/Subscription First
      // 🚀 Robustness: If groupId is empty, try to get it from the first pending op
      String effectiveGroupId = groupId;
      if (effectiveGroupId.isEmpty && pendingOps.isNotEmpty) {
        effectiveGroupId = pendingOps.first['data']['groupId'] ?? '';
      }

      if (effectiveGroupId.isEmpty ||
          !await PermissionService.canWrite(effectiveGroupId)) {
        debugPrint(
          "Sync rejected: Subscription expired or no write permission for group: $effectiveGroupId",
        );
        _isSyncing = false;
        return;
      }

      debugPrint("Starting sync for ${pendingOps.length} operations...");

      for (int i = 0; i < pendingOps.length; i++) {
        final op = pendingOps[i];
        final type = op['type'];
        final data = op['data'] as Map<String, dynamic>;

        // 🚀 CRITICAL: Use groupId from data if available, otherwise fallback to effectiveGroupId
        final String opGroupId = data['groupId'] ?? effectiveGroupId;

        if (opGroupId.isEmpty || !await PermissionService.canWrite(opGroupId)) {
          debugPrint(
            "Sync skipped for operation $i: Subscription expired or no permission for group: $opGroupId",
          );
          // Don't abort the whole sync, just skip this group's ops?
          // Actually, if it's the current group, we can't do much.
          continue;
        }

        try {
          bool success = false;
          switch (type) {
            case 'individual_visit':
              success = await _syncIndividualVisit(data, opGroupId);
              break;
            case 'individual_visit_delete':
              success = await _syncIndividualVisitDelete(data, opGroupId);
              break;
            case 'reminder_visit':
              success = await _syncReminderVisit(data);
              break;
            case 'attendance_toggle':
              success = await _syncAttendanceToggle(data);
              break;
            case 'attendance_note':
              success = await _syncAttendanceNote(data);
              break;
            case 'add_student':
              success = await _syncAddStudent(data);
              break;
            case 'edit_student':
              success = await _syncEditStudent(data);
              break;
            case 'delete_student':
              success = await _syncDeleteStudent(data);
              break;
            case 'add_servant':
              success = await _syncAddServant(data);
              break;
            case 'delete_servant':
              success = await _syncDeleteServant(data);
              break;
            case 'edit_servant':
              success = await _syncEditServant(data);
              break;
            case 'add_grade':
              success = await _syncAddGrade(data);
              break;
            case 'rename_grade':
              success = await _syncRenameGrade(data);
              break;
            case 'delete_grade':
              success = await _syncDeleteGrade(data);
              break;
            case 'add_study_subject':
              success = await _syncAddStudySubject(data);
              break;
            case 'delete_study_subject':
              success = await _syncDeleteStudySubject(data);
              break;
            case 'add_study_grade':
              success = await _syncAddStudyGrade(data);
              break;
            case 'delete_study_grade':
              success = await _syncDeleteStudyGrade(data);
              break;
            case 'study_class_add':
              success = await _syncAddGrade(data);
              break;
            case 'study_class_delete':
              success = await _syncDeleteGrade(data);
              break;
            case 'study_class_rename':
              success = await _syncRenameGrade(data);
              break;
            case 'study_student_data_clear':
              success = await _syncStudyStudentDataClear(data);
              break;
            case 'add_custom_page':
              success = await _syncAddCustomPage(data, opGroupId);
              break;
            case 'delete_custom_page':
              success = await _syncDeleteCustomPage(data, opGroupId);
              break;
            case 'absence_action_upsert':
              success = await _syncAbsenceActionUpsert(data);
              break;
            case 'congratulation_upsert':
              success = await _syncCongratulationUpsert(data);
              break;
            case 'congratulation_remove':
              success = await _syncCongratulationRemove(data);
              break;
            case 'preparation_add':
              success = await _syncPreparationAdd(data);
              break;
            case 'preparation_delete':
              success = await _syncPreparationDelete(data);
              break;
            case 'meeting_add':
              success = await _syncMeetingAdd(data);
              break;
            case 'meeting_edit':
              success = await _syncMeetingEdit(data);
              break;
            case 'meeting_delete':
              success = await _syncMeetingDelete(data);
              break;
            default:
              debugPrint("Unknown operation type: $type");
              success = true; // Mark as done to avoid stuck queue
          }

          if (success) {
            await _cache.removePendingOperation(0, groupId: opGroupId);
          }
        } catch (e) {
          debugPrint("Failed to sync operation $i: $e");
          // Abort sync for this round to avoid infinite retry loops on non-transient errors
          break;
        }
      }

      // Notify listeners that sync is done
      _syncController.add(null);
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _syncIndividualVisit(
    Map<String, dynamic> data,
    String groupId,
  ) async {
    // 1. Upload Images if any
    List<String> imageUrls = List<String>.from(data['imageUrls'] ?? []);
    List<String> publicIds = List<String>.from(data['publicIds'] ?? []);
    final List<dynamic> localPaths = data['localImagePaths'] ?? [];

    if (localPaths.isNotEmpty) {
      for (var path in localPaths) {
        final file = File(path.toString());
        if (await file.exists()) {
          final res = await _imageService.uploadImage(file);
          if (res != null) {
            imageUrls.add(res['url']!);
            publicIds.add(res['id']!);
          }
        }
      }
    }

    final dbData = Map<String, dynamic>.from(data);
    final String docId = dbData.remove('visitId') ?? ID.unique();
    dbData.remove('localImagePaths');
    dbData.remove('teamId');
    dbData['imageUrls'] = imageUrls;
    dbData['publicIds'] = publicIds;

    // 2. Create Document
    await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'individual_visits',
      documentId: docId,
      data: dbData,
      permissions:
          (data['teamId'] != null && data['teamId'].toString().isNotEmpty)
          ? [
              Permission.read(Role.team(data['teamId'])),
              Permission.update(Role.team(data['teamId'])),
              Permission.delete(Role.team(data['teamId'])),
            ]
          : null,
    );

    // 3. Create Statuses for the synced images
    if (imageUrls.isNotEmpty) {
      final statusService = StatusService(groupId: groupId);
      for (String url in imageUrls) {
        await statusService.addStatus(
          imageUrl: url,
          caption:
              "افتقاد جديد: ${data['kidName']} - ${data['visitTitle'] ?? data['subject']}",
          source: "الافتقاد",
          teamId: data['teamId'],
          uploaderName: data['servantName'],
        );
      }
    }

    return true;
  }

  Future<bool> _syncReminderVisit(Map<String, dynamic> data) async {
    await _databases.updateDocument(
      databaseId: 'main_db',
      collectionId: 'students',
      documentId: data['studentId'],
      data: {'isVisited': data['isVisited'], 'visitedBy': data['visitedBy']},
    );
    // 🚀 Optimistic Update (Targeted)
    await _cache.updateKidInListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed key
      'students', // Visits are only for students usually
      data['studentId'],
      {'isVisited': data['isVisited'], 'visitedBy': data['visitedBy']},
    );
    return true;
  }

  Future<bool> _syncAttendanceToggle(Map<String, dynamic> data) async {
    // Logic similar to _AttendancePageState._togglePresent
    // But since it's a toggle, it's safer to use the state from data or check existing.
    // If it's a create, create. If update, update.

    // For simplicity, let's assume 'data' contains the final desired state
    // and we just try to update or create based on existence.
    // Actually, AttendancePage logic is: if doc exists, update. else create.

    final name = data['name'];
    final groupId = data['groupId'];
    final grade = data['grade'];
    final type = data['type'];

    final existing = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'attendance_status',
      queries: [
        Query.equal('name', name),
        Query.equal('groupId', groupId),
        Query.equal('grade', grade),
        Query.equal('type', type),
      ],
    );

    String? finalRealId;

    if (existing.total > 0) {
      final docId = existing.documents.first.$id;
      if (data['isPresent'] == false && (data['note'] ?? '').isEmpty) {
        await _databases.deleteDocument(
          databaseId: 'main_db',
          collectionId: 'attendance_status',
          documentId: docId,
        );
        // 🚀 Remove from cache if deleted
        await _cache.removeAttendanceStatusItem(groupId, grade, type, name);
        return true;
      } else {
        final syncedDoc = await _databases.updateDocument(
          databaseId: 'main_db',
          collectionId: 'attendance_status',
          documentId: docId,
          data: {
            'isPresent': data['isPresent'],
            'markedBy': data['markedBy'],
            'timestamp': data['timestamp'],
          },
        );
        finalRealId = syncedDoc.$id;
      }
    } else if (data['isPresent'] == true || (data['note'] ?? '').isNotEmpty) {
      final dbData = Map<String, dynamic>.from(data);
      dbData.remove('teamId');

      String? effectiveteamId = data['teamId'];
      if (effectiveteamId == null || effectiveteamId.isEmpty) {
        try {
          final groupDoc = await _databases.getDocument(
            databaseId: 'main_db',
            collectionId: 'groups',
            documentId: groupId,
          );
          effectiveteamId = groupDoc.data['teamId'];
        } catch (_) {}
      }

      final syncedDoc = await _databases.createDocument(
        databaseId: 'main_db',
        collectionId: 'attendance_status',
        documentId: ID.unique(),
        data: dbData,
        permissions: (effectiveteamId != null && effectiveteamId.isNotEmpty)
            ? [
                Permission.read(Role.team(effectiveteamId)),
                Permission.update(Role.team(effectiveteamId)),
                Permission.delete(Role.team(effectiveteamId)),
              ]
            : null,
      );
      finalRealId = syncedDoc.$id;
    }

    // 🚀 Optimistic Cache Update (Better Consistency)
    // Instead of re-fetching the whole list (which might be stale),
    // we manually update our local cache with the exact data we just wrote.
    final updatedDocData = {
      '\$id': finalRealId, // 🚀 PERSIST REAL ID
      'name': name,
      'isPresent': data['isPresent'],
      'markedBy': data['markedBy'],
      'note': data['note'],
      'grade': grade,
      'type': type,
      'groupId': groupId,
      'timestamp': data['timestamp'],
    };

    await _cache.updateAttendanceStatusItem(
      groupId,
      grade,
      type,
      name,
      updatedDocData,
    );

    return true;
  }

  Future<bool> _syncAttendanceNote(Map<String, dynamic> data) async {
    // Similar logic for notes
    return _syncAttendanceToggle(data);
  }

  Future<bool> _syncAddStudent(Map<String, dynamic> data) async {
    String? photoUrl;
    if (data['localImagePath'] != null) {
      final file = File(data['localImagePath']);
      if (await file.exists()) {
        final res = await _imageService.uploadImage(file);
        photoUrl = res?['url'];
        if (photoUrl == null) {
          // 🚀 Trigger retry if upload failed but file exists
          throw Exception("Image upload failed, retrying sync later.");
        }
      }
    }

    final dbData = Map<String, dynamic>.from(data);
    dbData.remove('localImagePath');
    dbData.remove('teamId'); // 🚀 Internal field, not in collection
    dbData.remove('studentId'); // 🚀 Internal field
    dbData['photoUrl'] = photoUrl;

    // 3. Create Document
    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'students',
      documentId: ID.unique(),
      data: dbData,
      permissions:
          (data['teamId'] != null && data['teamId'].toString().isNotEmpty)
          ? [
              Permission.read(Role.team(data['teamId'])),
              Permission.update(Role.team(data['teamId'])),
              Permission.delete(Role.team(data['teamId'])),
            ]
          : null,
    );

    // 🚀 Granular Cache Update
    final createdKid = Kid.fromAppwrite(doc);
    // Explicitly set role to student if not present, though fromAppwrite handles it usually via generic logic
    // but better to rely on what fromAppwrite helper does.

    await _cache.upsertKidInListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed Key
      'attendees',
      createdKid,
    );
    return true;
  }

  Future<bool> _syncEditStudent(Map<String, dynamic> data) async {
    String? photoUrl = data['photoUrl'];
    if (data['localImagePath'] != null) {
      // If there's an old image, should we delete it?
      // For simplicity in sync, we just upload the new one if local path exists.
      final file = File(data['localImagePath']);
      if (await file.exists()) {
        final res = await _imageService.uploadImage(file);
        photoUrl = res?['url'];
        if (photoUrl == null) {
          throw Exception("Image upload failed, retrying sync later.");
        }
      }
    }

    final dbData = Map<String, dynamic>.from(data);
    dbData.remove('localImagePath');
    dbData.remove('teamId');
    dbData['photoUrl'] = photoUrl;
    final studentId = dbData.remove('studentId');

    await _databases.updateDocument(
      databaseId: 'main_db',
      collectionId: 'students',
      documentId: studentId,
      data: dbData,
    );

    // 🚀 Granular Cache Update
    await _cache.updateKidInListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed key
      "attendees",
      studentId,
      dbData,
    );
    return true;
  }

  Future<bool> _syncDeleteStudent(Map<String, dynamic> data) async {
    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'students',
      documentId: data['studentId'],
    );
    // 🚀 Granular Cache Remove
    await _cache.removeKidFromListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed
      'attendees',
      data['studentId'],
    );
    return true;
  }

  Future<bool> _syncAddServant(Map<String, dynamic> data) async {
    String? photoUrl;
    if (data['localImagePath'] != null) {
      final file = File(data['localImagePath']);
      if (await file.exists()) {
        final res = await _imageService.uploadImage(file);
        photoUrl = res?['url'];
        if (photoUrl == null) {
          throw Exception("Image upload failed, retrying sync later.");
        }
      }
    }

    final dbData = Map<String, dynamic>.from(data);
    dbData.remove('localImagePath');
    dbData.remove('teamId'); // 🚀 Internal
    dbData['photoUrl'] = photoUrl;

    // Ideally we should use the ID returned from createDocument.
    // Let's modify the code to capture the result.
    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'servants',
      documentId: ID.unique(),
      data: dbData,
      permissions:
          (data['teamId'] != null && data['teamId'].toString().isNotEmpty)
          ? [
              Permission.read(Role.team(data['teamId'])),
              Permission.update(Role.team(data['teamId'])),
              Permission.delete(Role.team(data['teamId'])),
            ]
          : null,
    );

    // Use the actual ID from the created document
    final createdKid = Kid.fromAppwrite(doc);
    // Preserve local image path if available for immediate display
    if (data['localImagePath'] != null) {
      // Kid.fromAppwrite doesn't know about local paths, manually set it?
      // The Kid model has copyWith? No.
      // We can just rely on the photoUrl if upload succeeded.
      // But if we want to be super smooth, we can keep local path.
      // For now, let's just use what we have.
    }

    // 🚀 Granular Cache Update
    await _cache.upsertKidInListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed key
      'servants',
      createdKid,
    );
    return true;
  }

  Future<bool> _syncEditServant(Map<String, dynamic> data) async {
    // 1. Handle Image
    String? photoUrl = data['photoUrl'];

    // If local image path is provided, upload it
    if (data['localImagePath'] != null && data['localImagePath'].isNotEmpty) {
      final file = File(data['localImagePath']);
      if (await file.exists()) {
        final res = await _imageService.uploadImage(file);
        if (res != null) {
          photoUrl = res['url'];
        } else {
          throw Exception("Image upload failed, retrying sync later.");
        }
      }
    }

    // If delete flag is on, remove old image
    if (data['isDeletePhoto'] == true && data['oldPhotoUrl'] != null) {
      await _imageService.deleteImageByUrl(data['oldPhotoUrl']);
      photoUrl = null;
    }

    // 2. Update Document
    await _databases.updateDocument(
      databaseId: 'main_db',
      collectionId: 'servants',
      documentId: data['servantId'],
      data: {
        'name': data['name'],
        'phoneRequired': data['phone'],
        'dateOfBirth': data['dateOfBirth'],
        'photoUrl': photoUrl,
      },
    );

    // 3. Refresh Cache (Granular)
    // We need to fetch the existing kid from cache to preserve other fields?
    // upsertKidInListCache replaces or adds.
    // We should construct the updated Kid object.
    // We need 'grade' and 'groupId' to find the list.
    // final grade = data['grade']; // Unused
    final servantId = data['servantId'];

    // It's safer to fetch the specific document to get full state?
    // No, that defeats the purpose of avoiding stale reads.
    // We should patch the local cache item.

    // Let's use updateKidInListCache which we already have!
    await _cache.updateKidInListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed Key
      'servants',
      servantId,
      {
        'name': data['name'],
        'phoneRequired': data['phone'], // key in Kid model
        'dateOfBirth': data['dateOfBirth'],
        'photoUrl': photoUrl,
      },
    );

    return true;
  }

  Future<bool> _syncDeleteServant(Map<String, dynamic> data) async {
    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'servants',
      documentId: data['servantId'],
    );

    // 🚀 Granular Cache Remove
    await _cache.removeKidFromListCache(
      "${data['groupId']}_${data['grade']}", // 🚀 Fixed Key
      'servants',
      data['servantId'],
    );
    return true;
  }

  Future<bool> _syncAddGrade(Map<String, dynamic> data) async {
    final groupId = data['groupId'];
    final gradeName = data['name'];

    // Check duplicate
    final existing = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'grades',
      queries: [
        Query.equal('groupId', groupId),
        Query.equal('name', gradeName),
      ],
    );

    if (existing.total > 0) return true; // Already exists

    // Fetch Team ID for permissions
    final groupDoc = await _databases.getDocument(
      databaseId: 'main_db',
      collectionId: 'groups',
      documentId: groupId,
    );
    final teamId = groupDoc.data['teamId'];

    await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'grades',
      documentId: ID.unique(),
      data: {
        'groupId': groupId,
        'name': gradeName,
        'createdAt': DateTime.now().toIso8601String(),
      },
      permissions: teamId != null
          ? [
              Permission.read(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
              Permission.write(Role.team(teamId)),
            ]
          : null,
    );
    await _refreshGradesCache(groupId);
    return true;
  }

  Future<bool> _syncRenameGrade(Map<String, dynamic> data) async {
    final groupId = data['groupId'];
    final oldName = data['oldName'];
    final newName = data['newName'];

    final result = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'grades',
      queries: [Query.equal('groupId', groupId), Query.equal('name', oldName)],
    );

    if (result.total > 0) {
      for (var doc in result.documents) {
        await _databases.updateDocument(
          databaseId: 'main_db',
          collectionId: 'grades',
          documentId: doc.$id,
          data: {'name': newName},
        );
      }
    }
    await _refreshGradesCache(groupId);
    return true;
  }

  Future<bool> _syncDeleteGrade(Map<String, dynamic> data) async {
    final groupId = data['groupId'];
    final name = data['name'];

    final result = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'grades',
      queries: [Query.equal('groupId', groupId), Query.equal('name', name)],
    );

    for (var doc in result.documents) {
      await _databases.deleteDocument(
        databaseId: 'main_db',
        collectionId: 'grades',
        documentId: doc.$id,
      );
    }
    await _refreshGradesCache(groupId);
    return true;
  }

  Future<bool> _syncAddStudySubject(Map<String, dynamic> data) async {
    final Map<String, dynamic> dbData = Map.from(data);
    final String studentId = dbData['studentId'];
    final String? teamId = dbData.remove('teamId');
    final String docId = dbData.remove(r'$id') ?? ID.unique(); // 🚀 Extract ID

    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'subjects',
      documentId: docId,
      data: dbData,
      permissions: (teamId != null && teamId.isNotEmpty)
          ? [
              Permission.read(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
            ]
          : null,
    );

    final Map<String, dynamic> cacheData = doc.toMap();
    await _cache.upsertStudySubjectInCache(studentId, cacheData);
    return true;
  }

  Future<bool> _syncDeleteStudySubject(Map<String, dynamic> data) async {
    final String subjectId = data['subjectId'];
    final String studentId = data['studentId'];

    // 1. Delete associated grades
    final subjectDoc = await _databases.getDocument(
      databaseId: 'main_db',
      collectionId: 'subjects',
      documentId: subjectId,
    );
    final String subjectName = subjectDoc.data['name'];

    final grades = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'study_grades',
      queries: [
        Query.equal('studentId', studentId),
        Query.equal('subject', subjectName),
      ],
    );

    for (var grade in grades.documents) {
      await _databases.deleteDocument(
        databaseId: 'main_db',
        collectionId: 'study_grades',
        documentId: grade.$id,
      );
    }

    // 2. Delete subject
    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'subjects',
      documentId: subjectId,
    );

    await _cache.removeStudySubjectFromCache(studentId, subjectId);
    return true;
  }

  Future<bool> _syncAddStudyGrade(Map<String, dynamic> data) async {
    final Map<String, dynamic> dbData = Map.from(data);
    final String studentId = dbData['studentId'];
    final String subject = dbData['subject'];
    final String? teamId = dbData.remove('teamId');
    final String docId = dbData.remove(r'$id') ?? ID.unique(); // 🚀 Extract ID

    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'study_grades',
      documentId: docId,
      data: dbData,
      permissions: (teamId != null && teamId.isNotEmpty)
          ? [
              Permission.read(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
            ]
          : null,
    );

    final Map<String, dynamic> cacheData = doc.toMap();
    await _cache.upsertStudyGradeInCache(studentId, subject, cacheData);
    return true;
  }

  Future<bool> _syncDeleteStudyGrade(Map<String, dynamic> data) async {
    final String gradeId = data['gradeId'];
    final String studentId = data['studentId'];
    final String subject = data['subject'];

    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'study_grades',
      documentId: gradeId,
    );

    await _cache.removeStudyGradeFromCache(studentId, subject, gradeId);
    return true;
  }

  Future<bool> _syncStudyStudentDataClear(Map<String, dynamic> data) async {
    final String studentId = data['studentId'];

    // 1. Get Subjects
    final subjects = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'subjects',
      queries: [Query.equal('studentId', studentId), Query.limit(1000)],
    );

    // 2. Delete Subjects and Grades
    for (final subjectDoc in subjects.documents) {
      final subjectName = subjectDoc.data['name'];

      // Get Grades
      final grades = await _databases.listDocuments(
        databaseId: 'main_db',
        collectionId: 'study_grades',
        queries: [
          Query.equal('studentId', studentId),
          Query.equal('subject', subjectName),
          Query.limit(1000),
        ],
      );

      // Delete Grades
      for (final gradeDoc in grades.documents) {
        await _databases.deleteDocument(
          databaseId: 'main_db',
          collectionId: 'study_grades',
          documentId: gradeDoc.$id,
        );
      }

      // Delete Subject
      await _databases.deleteDocument(
        databaseId: 'main_db',
        collectionId: 'subjects',
        documentId: subjectDoc.$id,
      );
    }

    // 3. Clear Cache
    await _cache.cacheStudySubjects(studentId, []);
    return true;
  }

  Future<bool> _syncAddCustomPage(
    Map<String, dynamic> data,
    String groupId,
  ) async {
    final Map<String, dynamic> dbData = Map.from(data);
    dbData['groupId'] = groupId;
    final String? teamId = dbData.remove('teamId');

    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'custom_pages',
      documentId: ID.unique(),
      data: dbData,
      permissions: (teamId != null && teamId.isNotEmpty)
          ? [
              Permission.read(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
            ]
          : null,
    );

    final Map<String, dynamic> cacheData = Map.from(doc.data);
    cacheData[r'$id'] = doc.$id;
    await _cache.upsertCustomPageInCache(groupId, cacheData);
    return true;
  }

  Future<bool> _syncDeleteCustomPage(
    Map<String, dynamic> data,
    String groupId,
  ) async {
    final String docId = data['docId'];

    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'custom_pages',
      documentId: docId,
    );

    await _cache.removeCustomPageFromCache(groupId, docId);
    return true;
  }

  Future<void> _refreshKidsCache(
    String? groupId,
    String? grade,
    String type,
  ) async {
    if (groupId == null || groupId.isEmpty || grade == null) return;
    try {
      final String collectionId = (type == 'servants')
          ? 'servants'
          : 'students';
      final result = await _databases.listDocuments(
        databaseId: 'main_db',
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('grade', grade),
          Query.limit(1000),
        ],
      );
      final kids = result.documents.map((d) => Kid.fromAppwrite(d)).toList();
      await _cache.cacheKidsList("${groupId}_$grade", type, kids);
    } catch (e) {
      debugPrint("Cache refresh failed for kids ($type): $e");
    }
  }

  Future<void> _refreshGradesCache(String? groupId) async {
    if (groupId == null || groupId.isEmpty) return;
    try {
      final result = await _databases.listDocuments(
        databaseId: 'main_db',
        collectionId: 'grades',
        queries: [Query.equal('groupId', groupId), Query.limit(100)],
      );
      final List<String> gradeNames = result.documents
          .map((doc) => doc.data['name'].toString())
          .toList();
      await _cache.cacheGrades(groupId, gradeNames);
    } catch (e) {
      debugPrint("Cache refresh failed for grades: $e");
    }
  }

  // 🚀 New Public Method for Global Refresh (Pull)
  Future<void> _refreshAllCache(String groupId) async {
    // 1. Refresh Grades
    await _refreshGradesCache(groupId);

    // 2. Refresh Students & Servants for each grade
    // To do this efficiently, we might need to know which grades exist.
    // Ideally, we iterate over cached grades.
    try {
      final grades = await _cache.getCachedGrades(groupId);
      for (final grade in grades) {
        await _refreshKidsCache(groupId, grade, 'students');
        await _refreshKidsCache(groupId, grade, 'servants');
        // Also refresh status map if needed?
        // AttendancePage handles its own refresh on mount, but global sync is good.
      }
    } catch (e) {
      debugPrint("Global cache refresh partial error: $e");
    }
  }

  Future<bool> _syncAbsenceActionUpsert(Map<String, dynamic> data) async {
    final reportId = data['reportId'];
    final kidName = data['kidName'];
    final grade = data['grade'];
    final groupId = data['groupId'];
    final teamId = data['teamId'];
    final updates = data['updates'];

    // Check if action exists
    final result = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'absence_actions',
      queries: [
        Query.equal('reportId', reportId),
        Query.equal('kidName', kidName),
        Query.limit(1),
      ],
    );

    if (result.documents.isNotEmpty) {
      await _databases.updateDocument(
        databaseId: 'main_db',
        collectionId: 'absence_actions',
        documentId: result.documents.first.$id,
        data: updates,
      );
    } else {
      await _databases.createDocument(
        databaseId: 'main_db',
        collectionId: 'absence_actions',
        documentId: ID.unique(),
        data: {
          'reportId': reportId,
          'kidName': kidName,
          'grade': grade,
          'groupId': groupId,
          ...updates,
        },
        permissions: teamId != null && teamId.toString().isNotEmpty
            ? [
                Permission.read(Role.team(teamId)),
                Permission.update(Role.team(teamId)),
                Permission.delete(Role.team(teamId)),
              ]
            : null,
      );
    }

    // Refresh the local cache to match the server state just in case
    await _cache.updateSingleAbsenceActionInCache(reportId, kidName, updates);
    return true;
  }

  Future<bool> _syncCongratulationUpsert(Map<String, dynamic> data) async {
    final String groupId = data['groupId'];
    final String kidName = data['kidName'];
    final List<String> congratulatedBy = List<String>.from(
      data['congratulatedBy'],
    );
    final String? teamId = data['teamId'];

    // Check if exists
    final result = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'birthday_congratulations',
      queries: [
        Query.equal('groupId', groupId),
        Query.equal('kidName', kidName),
        Query.limit(1),
      ],
    );

    if (result.documents.isNotEmpty) {
      await _databases.updateDocument(
        databaseId: 'main_db',
        collectionId: 'birthday_congratulations',
        documentId: result.documents.first.$id,
        data: {
          'congratulatedBy': congratulatedBy,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } else {
      await _databases.createDocument(
        databaseId: 'main_db',
        collectionId: 'birthday_congratulations',
        documentId: ID.unique(),
        data: {
          'groupId': groupId,
          'kidName': kidName,
          'congratulatedBy': congratulatedBy,
          'timestamp': DateTime.now().toIso8601String(),
        },
        permissions: (teamId != null && teamId.isNotEmpty)
            ? [
                Permission.read(Role.users()),
                Permission.update(Role.team(teamId)),
                Permission.delete(Role.team(teamId)),
              ]
            : [
                Permission.read(Role.users()),
                Permission.update(Role.users()),
                Permission.delete(Role.users()),
              ],
      );
    }
    return true;
  }

  Future<bool> _syncCongratulationRemove(Map<String, dynamic> data) async {
    final String groupId = data['groupId'];
    final String kidName = data['kidName'];
    final String serverName = data['serverName'];

    final result = await _databases.listDocuments(
      databaseId: 'main_db',
      collectionId: 'birthday_congratulations',
      queries: [
        Query.equal('groupId', groupId),
        Query.equal('kidName', kidName),
        Query.limit(1),
      ],
    );

    if (result.documents.isNotEmpty) {
      final doc = result.documents.first;
      List<String> currentList = List<String>.from(
        doc.data['congratulatedBy'] ?? [],
      );
      currentList.remove(serverName);

      if (currentList.isEmpty) {
        await _databases.deleteDocument(
          databaseId: 'main_db',
          collectionId: 'birthday_congratulations',
          documentId: doc.$id,
        );
      } else {
        await _databases.updateDocument(
          databaseId: 'main_db',
          collectionId: 'birthday_congratulations',
          documentId: doc.$id,
          data: {
            'congratulatedBy': currentList,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
      }
    }
    return true;
  }

  Future<bool> _syncPreparationAdd(Map<String, dynamic> data) async {
    final groupId = data['groupId'];
    final teamId = data['teamId'];

    // 1. Upload Images
    List<String> imageUrls = [];
    List<String> fileIds = [];
    final List<dynamic> localPaths = data['localImagePaths'] ?? [];

    for (var path in localPaths) {
      final file = File(path.toString());
      if (await file.exists()) {
        final res = await _imageService.uploadImage(file);
        if (res != null) {
          imageUrls.add(res['url']!);
          fileIds.add(res['id']!);
        }
      }
    }

    // 2. Create Document
    final dbData = Map<String, dynamic>.from(data);
    dbData.remove('localImagePaths');
    dbData.remove('teamId');
    dbData['imageUrls'] = imageUrls;
    dbData['fileIds'] = fileIds;

    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'preparations',
      documentId: ID.unique(),
      data: dbData,
      permissions: (teamId != null && teamId.toString().isNotEmpty)
          ? [
              Permission.read(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
            ]
          : null,
    );

    // 3. Statuses
    if (imageUrls.isNotEmpty) {
      final statusService = StatusService(groupId: groupId);
      for (String url in imageUrls) {
        await statusService.addStatus(
          imageUrl: url,
          caption: "تحضير جديد: ${data['title']}",
          source: "التحضير",
          teamId: teamId,
          uploaderName: data['servantName'],
        );
      }
    }

    // 4. Update Cache
    final currentList = await _cache.getCachedPreparations(groupId);
    currentList.insert(0, doc.toMap());
    await _cache.cachePreparations(groupId, currentList);

    return true;
  }

  Future<bool> _syncPreparationDelete(Map<String, dynamic> data) async {
    final docId = data['docId'];
    final groupId = data['groupId'];
    final List<dynamic> fileIds = data['fileIds'] ?? [];
    final List<dynamic> imageUrls = data['imageUrls'] ?? [];

    // 1. Delete Files
    final storage = AppwriteService().storage;
    for (var id in fileIds) {
      try {
        await storage.deleteFile(bucketId: 'images', fileId: id.toString());
      } catch (_) {}
    }

    // 2. Delete Statuses
    final statusService = StatusService(groupId: groupId);
    for (var url in imageUrls) {
      await statusService.deleteStatusByImageUrl(url.toString());
    }

    // 3. Delete Document
    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'preparations',
      documentId: docId,
    );

    // 4. Update Cache
    await _cache.removePreparationFromCache(groupId, docId);

    return true;
  }

  Future<bool> _syncMeetingAdd(Map<String, dynamic> data) async {
    final groupId = data['groupId'];
    final teamId = data['teamId'];

    // 1. Upload Images
    List<String> imageUrls = [];
    List<String> fileIds = [];
    final List<dynamic> localPaths = data['localImagePaths'] ?? [];

    for (var path in localPaths) {
      final file = File(path.toString());
      if (await file.exists()) {
        final res = await _imageService.uploadImage(file);
        if (res != null) {
          imageUrls.add(res['url']!);
          fileIds.add(res['id']!);
        }
      }
    }

    // 2. Create Document
    final dbData = Map<String, dynamic>.from(data);
    dbData.remove('localImagePaths');
    dbData.remove('teamId');
    dbData['imageUrls'] = imageUrls;
    dbData['fileIds'] = fileIds;

    final doc = await _databases.createDocument(
      databaseId: 'main_db',
      collectionId: 'meetings',
      documentId: ID.unique(),
      data: dbData,
      permissions: (teamId != null && teamId.toString().isNotEmpty)
          ? [
              Permission.read(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
            ]
          : null,
    );

    // 3. Statuses
    if (imageUrls.isNotEmpty) {
      final statusService = StatusService(groupId: groupId);
      for (String url in imageUrls) {
        await statusService.addStatus(
          imageUrl: url,
          caption: "اجتماع جديد: ${data['title']}",
          source: "الاجتماعات",
          teamId: teamId,
          uploaderName: data['servantName'],
        );
      }
    }

    // 4. Update Cache
    final currentList = await _cache.getCachedMeetings(groupId);
    currentList.insert(0, doc.toMap());
    await _cache.cacheMeetings(groupId, currentList);

    return true;
  }

  Future<bool> _syncMeetingEdit(Map<String, dynamic> data) async {
    final docId = data['docId'];
    final groupId = data['groupId'];
    final updates = data['updates'];

    await _databases.updateDocument(
      databaseId: 'main_db',
      collectionId: 'meetings',
      documentId: docId,
      data: updates,
    );

    await _cache.updateMeetingInCache(groupId, docId, updates);
    return true;
  }

  Future<bool> _syncMeetingDelete(Map<String, dynamic> data) async {
    final docId = data['docId'];
    final groupId = data['groupId'];
    final List<dynamic> fileIds = data['fileIds'] ?? [];
    final List<dynamic> imageUrls = data['imageUrls'] ?? [];

    // 1. Delete Files
    final storage = AppwriteService().storage;
    for (var id in fileIds) {
      try {
        await storage.deleteFile(bucketId: 'images', fileId: id.toString());
      } catch (_) {}
    }

    // 2. Delete Statuses
    final statusService = StatusService(groupId: groupId);
    for (var url in imageUrls) {
      await statusService.deleteStatusByImageUrl(url.toString());
    }

    // 3. Delete Document
    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'meetings',
      documentId: docId,
    );

    // 4. Update Cache
    await _cache.removeMeetingFromCache(groupId, docId);

    return true;
  }

  Future<bool> _syncIndividualVisitDelete(
    Map<String, dynamic> data,
    String groupId,
  ) async {
    final String visitId = data['visitId'];
    final List<dynamic> imageUrls = data['imageUrls'] ?? [];
    final List<dynamic> publicIds = data['publicIds'] ?? [];

    // 1. Delete from Storage
    for (var id in publicIds) {
      if (id != null) {
        try {
          await _imageService.deleteImage(id.toString());
        } catch (_) {}
      }
    }

    // 2. Delete Statuses
    final statusService = StatusService(groupId: groupId);
    for (var url in imageUrls) {
      if (url != null) {
        try {
          await statusService.deleteStatusByImageUrl(url.toString());
        } catch (_) {}
      }
    }

    // 3. Delete Document
    await _databases.deleteDocument(
      databaseId: 'main_db',
      collectionId: 'individual_visits',
      documentId: visitId,
    );

    // 4. Update Cache
    await _cache.removeIndividualVisitFromCache(
      groupId,
      data['kidGrade'],
      visitId,
    );
    // Also remove from kid specific cache
    await _cache.removeKidVisitFromCache(groupId, data['kidName'], visitId);

    return true;
  }
}
