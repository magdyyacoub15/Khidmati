import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import '../utils/device_info_util.dart';
import 'appwrite_service.dart';

class ReferralService {
  static final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';
  static const String referralsCollectionId = 'referrals';

  static Future<bool> submitReferral(
    String referralCode,
    String newGroupId,
  ) async {
    try {
      if (referralCode.trim().isEmpty) return false;

      // 1. Get Device ID
      final deviceId = await DeviceInfoUtil.getUniqueDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        debugPrint("Could not get device ID for referral.");
        return false;
      }

      // 2. Find Referrer Group
      final groupQuery = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        queries: [Query.equal('referralCode', referralCode.trim())],
      );

      if (groupQuery.documents.isEmpty) {
        debugPrint("Referral Code not found");
        return false; // Code doesn't exist
      }

      final referrerDoc = groupQuery.documents.first;
      final referrerGroupId = referrerDoc.data['groupId'];
      final referralUses = (referrerDoc.data['referralUses'] as int?) ?? 0;

      // 3. Check Limits
      if (referralUses >= 12) {
        debugPrint("Referral code reached max 12 uses.");
        return false;
      }

      // 4. Check Device ID Fraud
      final deviceCheck = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: referralsCollectionId,
        queries: [Query.equal('deviceId', deviceId)],
      );

      if (deviceCheck.documents.isNotEmpty) {
        debugPrint(
          "Fraud prevented: Device $deviceId already used a referral code.",
        );
        return false;
      }

      // 5. Create Referral Record
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: referralsCollectionId,
        documentId: ID.unique(),
        data: {
          'referrerGroupId': referrerGroupId,
          'referredGroupId': newGroupId,
          'deviceId': deviceId,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      // 6. Increment uses in groups collection
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: referrerDoc.$id,
        data: {'referralUses': referralUses + 1},
      );

      return true;
    } catch (e) {
      debugPrint("Error in submitReferral: $e");
      return false;
    }
  }

  static Future<List<models.Document>> getReferralsForGroup(
    String groupId,
  ) async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: referralsCollectionId,
        queries: [
          Query.equal('referrerGroupId', groupId),
          Query.orderAsc('createdAt'), // Order by oldest
          Query.limit(100),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint("Error getting referrals: $e");
      return [];
    }
  }

  static Future<void> checkAndApplyRewards(String referrerGroupId) async {
    try {
      final referrals = await getReferralsForGroup(referrerGroupId);
      final pendingReferrals = referrals
          .where((r) => r.data['status'] == 'pending')
          .toList();

      if (pendingReferrals.isEmpty) return;

      for (var doc in pendingReferrals) {
        final referredGroupId = doc.data['referredGroupId'];
        if (referredGroupId == null) continue;

        // Fetch attendance records for this group to count active days
        int activeDays = 0;
        try {
          final records = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: 'attendance_records',
            queries: [
              Query.equal('groupId', referredGroupId),
              Query.limit(100), // Get up to 100 recent records
            ],
          );

          final Set<String> uniqueDates = {};
          for (var r in records.documents) {
            final String? ts = r.data['timestamp'];
            if (ts != null) {
              try {
                final dt = DateTime.parse(ts);
                uniqueDates.add("${dt.year}-${dt.month}-${dt.day}");
              } catch (_) {}
            }
          }
          activeDays = uniqueDates.length;
        } catch (e) {
          debugPrint("Error checking active days: \$e");
        }

        if (activeDays >= 10) {
          // Get referrer group to update subscription
          final groupDoc = await _databases.getDocument(
            databaseId: databaseId,
            collectionId: groupsCollectionId,
            documentId: referrerGroupId,
          );

          final subEndStr = groupDoc.data['subscriptionEndDate'];
          DateTime? subEnd;
          if (subEndStr != null) {
            subEnd = DateTime.tryParse(subEndStr);
          }
          final now = DateTime.now();
          if (subEnd == null || subEnd.isBefore(now)) {
            subEnd = now;
          }

          // Add 1 month (approx 30 days)
          final newSubEnd = subEnd.add(const Duration(days: 30));

          // Update group subscription
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: groupsCollectionId,
            documentId: groupDoc.$id,
            data: {'subscriptionEndDate': newSubEnd.toIso8601String()},
          );

          // Update Referral Status
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: referralsCollectionId,
            documentId: doc.$id,
            data: {'status': 'rewarded'},
          );
        }
      }
    } catch (e) {
      debugPrint("Error checkAndApplyRewards: $e");
    }
  }
}
