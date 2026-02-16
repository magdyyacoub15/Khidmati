import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';

/// Service for managing daily visit recommendations
/// Assigns least-visited kids to servants on a daily rotation basis
class DailyVisitRecommendationService {
  final Databases _databases = AppwriteService().databases;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String studentsCollectionId = 'students';
  static const String visitsCollectionId = 'individual_visits';
  static const String recommendationsCollectionId =
      'daily_visit_recommendations';

  /// Get least visited kids for a group
  /// Returns [servantCount] number of kids with lowest visit counts
  Future<List<Map<String, dynamic>>> getLeastVisitedKids(
    String groupId,
    int servantCount,
  ) async {
    try {
      // 1. Fetch all students in the group
      final studentsSnapshot = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [Query.equal('groupId', groupId), Query.limit(5000)],
      );

      if (studentsSnapshot.total == 0) return [];

      // 2. Fetch all visits to count them
      final visitsSnapshot = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: visitsCollectionId,
        queries: [Query.equal('groupId', groupId), Query.limit(10000)],
      );

      // 3. Count visits per kid
      final Map<String, int> visitCountMap = {};
      final Map<String, Map<String, dynamic>> kidDataMap = {};

      for (var doc in studentsSnapshot.documents) {
        final kidName = doc.data['name'];
        visitCountMap[kidName] = 0;
        kidDataMap[kidName] = {
          'id': doc.$id,
          'name': kidName,
          'grade': doc.data['grade'] ?? '',
        };
      }

      for (var doc in visitsSnapshot.documents) {
        final kidName = doc.data['name'] ?? doc.data['kidName'];
        if (kidName != null && visitCountMap.containsKey(kidName)) {
          visitCountMap[kidName] = visitCountMap[kidName]! + 1;
        }
      }

      // 4. Sort by visit count (ascending) and take top N
      final List<String> sortedKids = visitCountMap.keys.toList();
      sortedKids.sort((a, b) => visitCountMap[a]!.compareTo(visitCountMap[b]!));

      final leastVisited = sortedKids.take(servantCount).map((kidName) {
        return {...kidDataMap[kidName]!, 'visitCount': visitCountMap[kidName]};
      }).toList();

      debugPrint(
        '✅ Found ${leastVisited.length} least visited kids for $servantCount servants',
      );
      return leastVisited;
    } catch (e) {
      debugPrint('❌ Error getting least visited kids: $e');
      return [];
    }
  }

  /// Generate daily recommendations for all servants in a group
  /// This should be called once per day (e.g., at midnight)
  Future<void> generateDailyRecommendations(
    String groupId,
    String teamId,
  ) async {
    try {
      debugPrint('🔄 Generating daily recommendations for group $groupId...');

      // 1. Get all active servants in the group
      final servantsSnapshot = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        queries: [Query.equal('groupId', groupId), Query.limit(100)],
      );

      if (servantsSnapshot.total == 0) {
        debugPrint('⚠️ No servants found in group $groupId');
        return;
      }

      final servants = servantsSnapshot.documents;
      final servantCount = servants.length;

      debugPrint('👥 Found $servantCount servants in group');

      // 2. Get least visited kids (same count as servants)
      final leastVisitedKids = await getLeastVisitedKids(groupId, servantCount);

      if (leastVisitedKids.isEmpty) {
        debugPrint('⚠️ No kids found for recommendations');
        return;
      }

      // 3. Clear today's pending recommendations (if regenerating)
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final existingRecommendations = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: recommendationsCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('date', todayStr),
          Query.limit(100),
        ],
      );

      for (var doc in existingRecommendations.documents) {
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: recommendationsCollectionId,
          documentId: doc.$id,
        );
      }

      // 🔄 Fetch yesterday's recommendations for rotation logic
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      final yesterdayRecommendations = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: recommendationsCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('date', yesterdayStr),
          Query.limit(100),
        ],
      );

      final Map<String, String> lastAssignments = {}; // servantId -> kidId
      for (var doc in yesterdayRecommendations.documents) {
        final servantId = doc.data['servantId'];
        final kidId = doc.data['kidId'];
        if (servantId != null && kidId != null) {
          lastAssignments[servantId] = kidId;
        }
      }

      // 4. Distribute kids to servants with rotation logic
      // We use a pool of available kids to assign
      List<Map<String, dynamic>> availableKids = List.from(leastVisitedKids);

      // Shuffle servants to ensure fairness in priority pick if needed
      // (Optional, but good for randomness if simple iteration leads to bias)
      // List<Document> shuffledServants = List.from(servants)..shuffle();
      // But preserving order might be better for consistent "least visited" mapping if we didn't rotate.
      // Let's stick to order but rotate the kid selection.

      for (var servant in servants) {
        if (availableKids.isEmpty) break;

        final servantId = servant.$id;
        final lastKidId = lastAssignments[servantId];

        Map<String, dynamic>? selectedKid;

        // Try to find a kid that wasn't assigned to this servant yesterday
        try {
          selectedKid = availableKids.firstWhere((k) => k['id'] != lastKidId);
        } catch (_) {
          // If all available kids were assigned to this servant yesterday (unlikely unless 1 kid),
          // fallback to the first one.
          if (availableKids.isNotEmpty) {
            selectedKid = availableKids.first;
          }
        }

        if (selectedKid != null) {
          availableKids.remove(selectedKid); // Remove from pool

          await _databases.createDocument(
            databaseId: databaseId,
            collectionId: recommendationsCollectionId,
            documentId: ID.unique(),
            data: {
              'groupId': groupId,
              'servantId': servantId,
              'servantName': servant.data['name'] ?? 'خادم',
              'kidId': selectedKid['id'],
              'kidName': selectedKid['name'],
              'kidGrade': selectedKid['grade'],
              'visitCount': selectedKid['visitCount'],
              'date': todayStr,
              'status': 'pending',
              'completedAt': null,
              'teamId': teamId,
            },
            permissions: [Permission.read(Role.team(teamId))],
          );
        }
      }

      debugPrint(
        '✅ Successfully generated ${leastVisitedKids.length} daily recommendations',
      );
    } catch (e) {
      debugPrint('❌ Error generating daily recommendations: $e');
    }
  }

  /// Get today's recommendation for a specific servant
  Future<Map<String, dynamic>?> getTodayRecommendation(
    String servantId,
    String groupId,
  ) async {
    try {
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: recommendationsCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.equal('servantId', servantId),
          Query.equal('date', todayStr),
          Query.limit(1),
        ],
      );

      if (result.total > 0) {
        return result.documents.first.data;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting today\'s recommendation: $e');
      return null;
    }
  }

  /// Mark a recommendation as completed
  Future<void> markRecommendationAsCompleted(String recommendationId) async {
    try {
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: recommendationsCollectionId,
        documentId: recommendationId,
        data: {
          'status': 'completed',
          'completedAt': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('✅ Recommendation marked as completed');
    } catch (e) {
      debugPrint('❌ Error marking recommendation as completed: $e');
    }
  }

  /// Mark a recommendation as skipped
  Future<void> markRecommendationAsSkipped(String recommendationId) async {
    try {
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: recommendationsCollectionId,
        documentId: recommendationId,
        data: {'status': 'skipped'},
      );
      debugPrint('✅ Recommendation marked as skipped');
    } catch (e) {
      debugPrint('❌ Error marking recommendation as skipped: $e');
    }
  }
}
