import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';

import 'appwrite_service.dart';
import 'data_cache_service.dart';
import 'sync_service.dart';

class GradeService {
  final String groupId;
  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = AppwriteService().realtime;

  static const String databaseId = AppwriteService.databaseId;
  static const String collectionId = 'grades';

  GradeService({required this.groupId});

  /// جلب الفصول كـ Stream مرتبة حسب تاريخ الإنشاء
  Stream<List<String>> getGradesStream() async* {
    // 1. Emit cached data immediately if available
    final cached = await DataCacheService().getCachedGrades(groupId);
    if (cached.isNotEmpty) {
      yield cached;
    }

    // 2. Fetch fresh data and listen
    yield* Stream.fromFuture(getGrades()).asyncExpand((initialData) async* {
      yield initialData;

      final subscription = _realtime.subscribe([
        'databases.$databaseId.collections.$collectionId.documents',
      ]);

      yield* subscription.stream.asyncMap((event) async {
        return await getGrades();
      });
    });
  }

  /// جلب الفصول كـ Future (للاستخدام لمرة واحدة)
  Future<List<String>> getGrades() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.orderAsc('createdAt'),
          Query.limit(100),
        ],
      );
      final grades = result.documents
          .map((doc) => doc.data['name'] as String)
          .toList();

      // Cache the result
      await DataCacheService().cacheGrades(groupId, grades);
      return grades;
    } catch (e) {
      debugPrint("Error fetching grades from Appwrite: $e");
      // Fallback to cache on error
      return await DataCacheService().getCachedGrades(groupId);
    }
  }

  /// إضافة فصل جديد
  Future<void> addGrade(String gradeName) async {
    // التحقق من عدم وجود الاسم مسبقاً لمنع التكرار
    final result = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('groupId', groupId),
        Query.equal('name', gradeName),
      ],
    );

    if (result.total > 0) {
      throw Exception('هذا الفصل موجود بالفعل');
    }

    // 🆕 Fetch Team ID for Permissions
    // Since we don't have teamId passed here, we need to fetch it from the Group via DataCache or DB.
    // Ideally, pass teamId to GradeService constructor or calculate it.
    // For now, let's fetch it from group document (cached hopefully)
    final groupDoc = await _databases.getDocument(
      databaseId: databaseId,
      collectionId: 'groups',
      documentId: groupId,
    );
    final teamId = groupDoc.data['teamId'];

    final syncData = {'groupId': groupId, 'name': gradeName, 'teamId': teamId};

    // 🚀 Offline Logic
    final bool online = await SyncService().isOnline();
    if (!online) {
      await DataCacheService().addPendingOperation({
        'type': 'study_class_add',
        'data': syncData,
      });
      // Update cache
      final currentGrades = await getGrades();
      if (!currentGrades.contains(gradeName)) {
        currentGrades.add(gradeName);
        await DataCacheService().cacheGrades(groupId, currentGrades);
      }
      return;
    }

    await _databases.createDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: ID.unique(),
      data: {
        'groupId': groupId,
        'name': gradeName,
        'createdAt': DateTime.now().toIso8601String(),
      },
      permissions: teamId != null
          ? [
              Permission.read(Role.team(teamId)),
              Permission.write(Role.team(teamId)),
              Permission.update(Role.team(teamId)),
              Permission.delete(Role.team(teamId)),
            ]
          : [],
    );
    await getGrades(); // 🚀 Refresh cache immediately after successful add
  }

  /// حذف فصل
  Future<void> deleteGrade(String gradeName) async {
    final syncData = {'groupId': groupId, 'name': gradeName};

    // 🚀 Offline Logic
    final bool online = await SyncService().isOnline();
    if (!online) {
      await DataCacheService().addPendingOperation({
        'type': 'study_class_delete',
        'data': syncData,
      });
      // Update cache
      final currentGrades = await getGrades();
      currentGrades.remove(gradeName);
      await DataCacheService().cacheGrades(groupId, currentGrades);
      return;
    }

    final result = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [
        Query.equal('groupId', groupId),
        Query.equal('name', gradeName),
      ],
    );

    for (var doc in result.documents) {
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: doc.$id,
      );
    }
    await getGrades(); // 🚀 Refresh cache immediately after successful delete
  }

  /// تعديل اسم فصل
  Future<void> updateGradeName(String oldName, String newName) async {
    final syncData = {
      'groupId': groupId,
      'oldName': oldName,
      'newName': newName,
    };

    // 🚀 Offline Logic
    final bool online = await SyncService().isOnline();
    if (!online) {
      await DataCacheService().addPendingOperation({
        'type': 'study_class_rename',
        'data': syncData,
      });
      // Update cache
      final currentGrades = await getGrades();
      final idx = currentGrades.indexOf(oldName);
      if (idx != -1) {
        currentGrades[idx] = newName;
        await DataCacheService().cacheGrades(groupId, currentGrades);
      }
      return;
    }

    final result = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: [Query.equal('groupId', groupId), Query.equal('name', oldName)],
    );

    if (result.total > 0) {
      for (var doc in result.documents) {
        await _databases.updateDocument(
          databaseId: databaseId,
          collectionId: collectionId,
          documentId: doc.$id,
          data: {'name': newName},
        );
      }
      await getGrades(); // 🚀 Refresh cache immediately after successful rename
    } else {
      throw Exception('الفصل المراد تعديله غير موجود');
    }
  }
}
