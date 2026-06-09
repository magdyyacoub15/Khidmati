import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/appwrite_service.dart';
import 'data_cache_service.dart';

class SubscriptionService {
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';

  // Securely fetch server time
  Future<DateTime?> getServerTime(String groupId) async {
    return _fetchRealTime();
  }

  // Caching variables
  SubscriptionStatus? _cachedStatus;
  DateTime? _lastCheckTime;
  static const Duration _cacheDuration = Duration(hours: 24);

  // Securely fetch network time
  Future<DateTime?> _fetchRealTime() async {
    try {
      // 1. Try WorldTimeAPI (Use HTTPS for Web)
      final response = await http
          .get(Uri.parse('https://worldtimeapi.org/api/timezone/Etc/UTC'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['utc_datetime']).toLocal();
      }
    } catch (e) {
      debugPrint("WorldTimeAPI fetch failed: $e");
    }

    try {
      // 2. Fallback to Google Head (Date Header) - Likely fails on Web due to CORS
      final response = await http
          .head(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      final dateHeader = response.headers['date'];
      if (dateHeader != null) {
        final parsed = _parseHttpDate(dateHeader);
        if (parsed != null) return parsed;
      }
    } catch (e) {
      debugPrint("Network time fetch (Google) failed: $e");
    }

    try {
      // 3. Fallback to TimeApi.io (cors friendly)
      final response = await http
          .get(
            Uri.parse('https://timeapi.io/api/Time/current/zone?timeZone=UTC'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['dateTime']).toLocal();
      }
    } catch (e) {
      debugPrint("TimeApi.io fetch failed: $e");
    }

    // 🚀 We no longer fallback to device time directly for Web.
    // Device time can be manipulated by users (tampering).
    // If all APIs fail, it returns null and triggers Offline mode logic with checks.
    return null;
  }

  /// Manually parse HTTP Date header (Web Compatible alternative to HttpDate.parse)
  DateTime? _parseHttpDate(String date) {
    try {
      final parts = date.split(' ');
      if (parts.length >= 5) {
        // "Tue, 15 Feb 2022 17:15:30 GMT"
        final day = parts[1];
        final monthStr = parts[2];
        final year = parts[3];
        final time = parts[4];

        final months = {
          'Jan': 1,
          'Feb': 2,
          'Mar': 3,
          'Apr': 4,
          'May': 5,
          'Jun': 6,
          'Jul': 7,
          'Aug': 8,
          'Sep': 9,
          'Oct': 10,
          'Nov': 11,
          'Dec': 12,
        };

        final month = months[monthStr] ?? 1;
        final isoString =
            "$year-${month.toString().padLeft(2, '0')}-${day.padLeft(2, '0')}T${time}Z";
        return DateTime.parse(isoString).toLocal();
      }
    } catch (e) {
      debugPrint("Error manual parsing HTTP date: $e");
    }
    return null;
  }

  Future<SubscriptionStatus> checkSubscriptionStatus(
    String groupId, {
    bool forceRefresh = false,
  }) async {
    // 1. Return cached status if valid
    if (!forceRefresh &&
        _cachedStatus != null &&
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedStatus!;
    }

    try {
      // 2. Get Real Time (Implicit Connectivity Check)
      final DateTime? networkNow = await _fetchRealTime();

      if (networkNow == null) {
        // Fallback to cache if network time fails (Offline or CORS issue)
        final cached = await DataCacheService().getCachedSubscriptionStatus(
          groupId,
        );
        if (cached != null) {
          final String statusStr = cached['status'];
          final String? lastCheckStr = cached['lastCheck'];

          // 🚀 Security Fix: 48-Hour Max Offline Limit
          if (lastCheckStr != null) {
            final DateTime lastCheckData = DateTime.parse(lastCheckStr);
            if (DateTime.now().difference(lastCheckData) >
                const Duration(hours: 48)) {
              debugPrint(
                "Offline grace period expired (48h exceeded). Defaulting to expired.",
              );
              return SubscriptionStatus.expired;
            }
          }

          if (statusStr == 'active') return SubscriptionStatus.active;
          if (statusStr == 'trial') return SubscriptionStatus.trial;
          if (statusStr == 'expired') return SubscriptionStatus.expired;
        }
        return SubscriptionStatus.offline;
      }

      // 3. Fetch from Appwrite
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
      _lastCheckTime = DateTime.now();

      // Update persistent cache
      await DataCacheService().cacheSubscriptionStatus(groupId, {
        'status': status.name,
        'lastCheck': _lastCheckTime!.toIso8601String(),
      });

      return status;
    } catch (e) {
      debugPrint("Error checking subscription: $e");
      // Fallback from cache on error
      final cached = await DataCacheService().getCachedSubscriptionStatus(
        groupId,
      );
      if (cached != null) {
        final String statusStr = cached['status'];
        final String? lastCheckStr = cached['lastCheck'];

        // 🚀 Security Fix: 48-Hour Max Offline Limit (Error Path)
        if (lastCheckStr != null) {
          final DateTime lastCheckData = DateTime.parse(lastCheckStr);
          if (DateTime.now().difference(lastCheckData) >
              const Duration(hours: 48)) {
            return SubscriptionStatus.expired;
          }
        }

        if (statusStr == 'active') return SubscriptionStatus.active;
        if (statusStr == 'trial') return SubscriptionStatus.trial;
        if (statusStr == 'expired') return SubscriptionStatus.expired;
      }
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
      final DateTime? networkNow = await _fetchRealTime();
      if (networkNow == null) throw Exception("Network time unavailable");

      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
      );

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
