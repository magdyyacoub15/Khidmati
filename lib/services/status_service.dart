import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'appwrite_service.dart';
import 'user_service.dart';
import 'package:flutter/foundation.dart';

class StatusService {
  final String groupId;
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Realtime _realtime = AppwriteService().realtime;

  static const String databaseId = AppwriteService.databaseId;
  static const String collectionId = 'statuses';

  StatusService({required this.groupId});

  Future<void> addStatus({
    required String imageUrl,
    required String caption,
    required String source,
    String? teamId,
    String? uploaderName, // 🚀 New: Allow passing uploader name directly
  }) async {
    try {
      final user = await _account.get();
      String name = uploaderName ?? await UserService().getCurrentUserName();

      List<String>? permissions;
      if (teamId != null && teamId.isNotEmpty) {
        // 🚀 Allow all authenticated users to READ, but only team members can UPDATE/DELETE
        permissions = [
          Permission.read(Role.users()),
          Permission.update(Role.team(teamId)),
          Permission.delete(Role.team(teamId)),
        ];
        debugPrint(
          "🔐 Creating status with team permissions for teamId: $teamId",
        );
      } else {
        // Fallback: if no teamId, allow all users to read/update/delete
        permissions = [
          Permission.read(Role.users()),
          Permission.update(Role.users()),
          Permission.delete(Role.users()),
        ];
        debugPrint(
          "🔐 Creating status with user-level permissions (no teamId)",
        );
      }

      final docId = ID.unique();

      // 🚀 Build data map, only include teamId if it exists
      final Map<String, dynamic> statusData = {
        'groupId': groupId,
        'uploaderId': user.$id,
        'uploaderName': name,
        'imageUrl': imageUrl,
        'caption': caption,
        'source': source,
        'timestamp': DateTime.now().toIso8601String(),
        'viewers': [],
      };

      // Only add teamId if it's not null (to avoid schema validation error)
      if (teamId != null && teamId.isNotEmpty) {
        statusData['teamId'] = teamId;
      }

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: docId,
        data: statusData,
        permissions: permissions,
      );

      debugPrint(
        "✅ Status created successfully: $docId for group $groupId, source: $source",
      );
    } catch (e) {
      debugPrint("❌ Error adding status to Appwrite: $e");
    }
  }

  /// Fetches statuses from the last 24 hours as a Stream
  Stream<List<models.Document>> getRecentStatuses() {
    return Stream.fromFuture(_fetchRecentStatuses()).asyncExpand((
      initialData,
    ) async* {
      yield initialData;

      final subscription = _realtime.subscribe([
        'databases.$databaseId.collections.$collectionId.documents',
      ]);

      yield* subscription.stream.asyncMap((event) async {
        return await _fetchRecentStatuses();
      });
    });
  }

  Future<List<models.Document>> _fetchRecentStatuses() async {
    try {
      final twentyFourHoursAgo = DateTime.now().subtract(
        const Duration(hours: 24),
      );

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.greaterThanEqual(
            'timestamp',
            twentyFourHoursAgo.toIso8601String(),
          ),
          Query.orderAsc('timestamp'),
          Query.limit(100),
        ],
      );

      // 🚀 Debug logging
      debugPrint(
        "📊 StatusService: Fetched ${result.documents.length} statuses for group $groupId",
      );

      return result.documents;
    } catch (e) {
      debugPrint("Error fetching recent statuses: $e");
      return [];
    }
  }

  /// Marks a status as viewed by the current user
  Future<void> markAsViewed(String statusId) async {
    try {
      final user = await _account.get();

      // Appwrite doesn't have arrayUnion, so we fetch and update
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: statusId,
      );

      List<String> viewers = List<String>.from(doc.data['viewers'] ?? []);
      if (!viewers.contains(user.$id)) {
        viewers.add(user.$id);
        await _databases.updateDocument(
          databaseId: databaseId,
          collectionId: collectionId,
          documentId: statusId,
          data: {'viewers': viewers},
        );
      }
    } catch (e) {
      debugPrint("Error marking status as viewed: $e");
    }
  }

  /// Deletes a status by its image URL
  Future<void> deleteStatusByImageUrl(String imageUrl) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('imageUrl', imageUrl),
        ],
      );

      for (var doc in result.documents) {
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: collectionId,
          documentId: doc.$id,
        );
      }
    } catch (e) {
      debugPrint("Error deleting status by image URL: $e");
    }
  }
}
