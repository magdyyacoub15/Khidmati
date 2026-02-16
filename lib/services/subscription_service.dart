import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../services/appwrite_service.dart';
import 'data_cache_service.dart';

class SubscriptionService {
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';

  // Securely fetch server time (Approximated using local time for now as Appwrite has no direct server time API)
  // In a stricter system, you'd use a Cloud Function to get time or trust the updatedAt of a fresh write.
  Future<DateTime?> getServerTime(String groupId) async {
    return _fetchRealTime();
  }

  // Caching variables
  SubscriptionStatus? _cachedStatus;
  DateTime? _lastCheckTime;
  static const Duration _cacheDuration = Duration(minutes: 30);

  // Check subscription status
  // Securely fetch network time
  Future<DateTime?> _fetchRealTime() async {
    try {
      // 1. Try WorldTimeAPI
      final response = await http.get(
        Uri.parse('http://worldtimeapi.org/api/timezone/Etc/UTC'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['utc_datetime']).toLocal();
      }
    } catch (e) {
      // Fallback or just continue
    }

    try {
      // 2. Fallback to Google Head (Date Header)
      final response = await http.head(Uri.parse('https://www.google.com'));
      if (response.headers['date'] != null) {
        return HttpDate.parse(response.headers['date']!).toLocal();
      }
    } catch (e) {
      debugPrint("Network time fetch failed: $e");
    }
    return null;
  }

  Future<SubscriptionStatus> checkSubscriptionStatus(
    String groupId, {
    bool forceRefresh = false,
  }) async {
    // 1. Check Connectivity First (Native dart:io check)
    bool isOffline = false;
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        isOffline = true;
      }
    } catch (_) {
      isOffline = true;
    }

    if (isOffline) {
      final cached = await DataCacheService().getCachedSubscriptionStatus(
        groupId,
      );
      if (cached != null) {
        final statusStr = cached['status'];
        if (statusStr == 'active') return SubscriptionStatus.active;
        if (statusStr == 'trial') return SubscriptionStatus.trial;
        if (statusStr == 'expired') return SubscriptionStatus.expired;
      }
      return SubscriptionStatus.offline;
    }

    // 2. Return cached status if valid AND network time was verified recently
    if (!forceRefresh &&
        _cachedStatus != null &&
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedStatus!;
    }

    try {
      // 3. Get Real Time (NOT Local Device Time)
      final DateTime? networkNow = await _fetchRealTime();
      if (networkNow == null) {
        // If we can't get real time, we can't verify subscription securely.
        // Option: Block access or fallback to local if diff is small?
        // User requested "Non-manipulatable", so we must validitate.
        // Strict Mode: Return offline/error if time unknown.
        return SubscriptionStatus.offline;
      }

      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
      );

      final data = doc.data;
      if (!data.containsKey('subscriptionEndDate') ||
          data['subscriptionEndDate'] == null) {
        _cachedStatus = SubscriptionStatus.expired;
        _lastCheckTime = DateTime.now();
        return _cachedStatus!;
      }

      final String endDateStr = data['subscriptionEndDate'];
      final DateTime endDate = DateTime.parse(endDateStr);

      SubscriptionStatus status;
      if (endDate.isAfter(networkNow)) {
        final bool isTrial = data['isTrial'] ?? false;
        status = isTrial ? SubscriptionStatus.trial : SubscriptionStatus.active;
      } else {
        status = SubscriptionStatus.expired;
      }

      _cachedStatus = status;
      _lastCheckTime =
          DateTime.now(); // Cache timestamp (local) is fine for short duration

      // Update persistent cache
      await DataCacheService().cacheSubscriptionStatus(groupId, {
        'status': status.name,
        'lastCheck': _lastCheckTime!.toIso8601String(),
      });

      return status;
    } catch (e) {
      debugPrint("Error checking subscription: $e");
      return SubscriptionStatus.offline;
    }
  }

  // Get days remaining (Secure)
  Future<int> getDaysRemaining(String groupId) async {
    try {
      final DateTime? networkNow = await _fetchRealTime();
      if (networkNow == null) return 0;

      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
      );

      final data = doc.data;
      if (!data.containsKey('subscriptionEndDate') ||
          data['subscriptionEndDate'] == null) {
        return 0;
      }

      final String endDateStr = data['subscriptionEndDate'];
      final DateTime endDate = DateTime.parse(endDateStr);

      if (endDate.isBefore(networkNow)) return 0;

      return endDate.difference(networkNow).inDays;
    } catch (e) {
      return 0;
    }
  }

  // Extend subscription
  Future<void> extendSubscription(
    String groupId,
    int days, {
    bool isTrial = false,
  }) async {
    try {
      // Fetch current to calculate new end date
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
      );

      final DateTime? networkNow = await _fetchRealTime();
      if (networkNow == null) throw Exception("Network time unavailable");

      DateTime currentEnd = networkNow;
      if (doc.data['subscriptionEndDate'] != null) {
        final existing = DateTime.parse(doc.data['subscriptionEndDate']);
        if (existing.isAfter(networkNow)) {
          currentEnd = existing;
        }
      }

      final DateTime newEnd = currentEnd.add(Duration(days: days));

      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
        data: {
          'subscriptionEndDate': newEnd.toIso8601String(),
          'isTrial': isTrial,
        },
      );
    } catch (e) {
      debugPrint("Error extending subscription: $e");
      rethrow;
    }
  }

  // Update subscription date manually
  Future<void> updateSubscriptionDate(String groupId, DateTime newDate) async {
    await _databases.updateDocument(
      databaseId: databaseId,
      collectionId: groupsCollectionId,
      documentId: groupId,
      data: {
        'subscriptionEndDate': newDate.toIso8601String(),
        'isTrial': false,
      },
    );
  }

  // Cancel subscription
  Future<void> cancelSubscription(String groupId) async {
    final DateTime? networkNow = await _fetchRealTime();
    final DateTime cancelDate = (networkNow ?? DateTime.now()).subtract(
      const Duration(days: 1),
    );

    await _databases.updateDocument(
      databaseId: databaseId,
      collectionId: groupsCollectionId,
      documentId: groupId,
      data: {
        'subscriptionEndDate': cancelDate.toIso8601String(),
        'isTrial': false,
      },
    );
  }
}

enum SubscriptionStatus { active, trial, expired, offline }
