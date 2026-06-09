import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'appwrite_service.dart';
import 'data_cache_service.dart';
import 'user_service.dart';

class CustomPageService {
  final Databases _databases = AppwriteService().databases;
  final String _dbId = AppwriteService.databaseId;
  final DataCacheService _cache = DataCacheService();
  static const String collectionId = 'custom_pages';

  final String groupId;

  CustomPageService({required this.groupId});

  Future<bool> _isConnected() async {
    if (kIsWeb) return true;
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 1. Get All Custom Pages for this group
  Future<List<Document>> getCustomPages() async {
    // 🚀 Load from cache first
    final cached = await _cache.getCachedCustomPages(groupId);
    final List<Document> cachedDocs = cached
        .map((m) => Document.fromMap(m))
        .toList();

    // Background fetch
    _fetchAndCachePages();

    return cachedDocs;
  }

  Future<void> _fetchAndCachePages() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: _dbId,
        collectionId: collectionId,
        queries: [Query.equal('groupId', groupId), Query.orderAsc('createdAt')],
      );
      final List<Map<String, dynamic>> dataToCache = result.documents
          .map((d) => d.data..[r'$id'] = d.$id)
          .toList();
      await _cache.cacheCustomPages(groupId, dataToCache);
    } catch (e) {
      debugPrint("Background fetch failed: $e");
    }
  }

  /// 2. Add a new custom page
  Future<String?> addCustomPage(String name) async {
    try {
      final existing = await _cache.getCachedCustomPages(groupId);
      if (existing.length >= 2) {
        return "لا يمكن إضافة أكثر من صفحتين مخصصتين.";
      }
      if (existing.any((m) => m['name'] == name)) {
        return "يوجد صفحة بنفس الاسم بالفعل.";
      }

      final String? teamId = await UserService().getGroupTeamId(groupId);
      final Map<String, dynamic> pageData = {
        'groupId': groupId,
        'name': name,
        'type': 'custom_${ID.unique()}',
        'createdAt': DateTime.now().toIso8601String(),
      };

      if (await _isConnected()) {
        final doc = await _databases.createDocument(
          databaseId: _dbId,
          collectionId: collectionId,
          documentId: ID.unique(),
          data: pageData,
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
      } else {
        // Offline
        final Map<String, dynamic> tempDoc = Map.from(pageData);
        tempDoc[r'$id'] = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        await _cache.upsertCustomPageInCache(groupId, tempDoc);
        await _cache.addPendingOperation({
          'type': 'add_custom_page',
          'data': {...pageData, 'teamId': teamId},
        });
      }
      return null;
    } catch (e) {
      debugPrint("Error adding custom page: $e");
      return "فشل في إضافة الصفحة: $e";
    }
  }

  /// 3. Delete a custom page
  Future<bool> deleteCustomPage(String documentId) async {
    try {
      // Optimistic cache removal
      await _cache.removeCustomPageFromCache(groupId, documentId);

      if (await _isConnected()) {
        await _databases.deleteDocument(
          databaseId: _dbId,
          collectionId: collectionId,
          documentId: documentId,
        );
      } else {
        await _cache.addPendingOperation({
          'type': 'delete_custom_page',
          'data': {'docId': documentId, 'groupId': groupId},
        });
      }
      return true;
    } catch (e) {
      debugPrint("Error deleting custom page: $e");
      return false;
    }
  }
}
