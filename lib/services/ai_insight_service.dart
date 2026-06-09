import 'dart:convert';
import 'dart:math'; // Add Random support
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_service.dart';
import '../l10n/app_translations.dart';
import 'language_service.dart';

class AIInsight {
  final String id;
  final String kidName;
  final String type; // 'consecutive_absence' or 'proactive_visit'
  final String message;
  final String assignedTo;
  final DateTime assignedDate;
  final String status; // 'pending', 'completed', 'dismissed'
  final bool isNotificationScheduled;

  AIInsight({
    required this.id,
    required this.kidName,
    required this.type,
    required this.message,
    required this.assignedTo,
    required this.assignedDate,
    this.status = 'pending',
    this.isNotificationScheduled = false,
  });

  factory AIInsight.fromAppwrite(models.Document doc) {
    final data = doc.data;
    return AIInsight(
      id: doc.$id,
      kidName: data['kidName'] ?? '',
      type: data['type'] ?? '',
      message: data['message'] ?? '',
      assignedTo: data['assignedTo'] ?? '',
      assignedDate: data['assignedDate'] != null
          ? DateTime.parse(data['assignedDate'])
          : DateTime.now(),
      status: data['status'] ?? 'pending',
      isNotificationScheduled: data['isNotificationScheduled'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'kidName': kidName,
      'type': type,
      'message': message,
      'assignedTo': assignedTo,
      'assignedDate': assignedDate.toIso8601String(),
      'status': status,
      'isNotificationScheduled': isNotificationScheduled,
    };
  }
}

class AIInsightService {
  final Databases _databases = AppwriteService().databases;
  final String groupId;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String insightsCollectionId = 'ai_insights';
  static const String attendanceCollectionId = 'attendance_records';
  static const String studentsCollectionId = 'students';
  static const String visitsCollectionId = 'individual_visits';

  AIInsightService({required this.groupId});

  /// 🚀 توليد التوصيات الجديدة بناءً على الغياب والزيارات القديمة
  /// Simplified version - uses SharedPreferences for local storage
  Future<void> generateInsights() async {
    try {
      debugPrint("🔄 Starting AI Insights generation (simplified mode)...");

      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month}-${now.day}";

      // Check if we already generated for today
      final prefs = await SharedPreferences.getInstance();
      final lastGenerated = prefs.getString('ai_insights_last_generated');

      if (lastGenerated == todayStr) {
        debugPrint("✅ Insights already generated for today");
        return;
      }

      final List<String> highRiskKids = await _detectConsecutiveAbsences();
      final List<String> leastVisitedKids = await _detectLeastVisitedKids();
      final Set<String> allTargetKids = {...highRiskKids, ...leastVisitedKids};

      debugPrint(
        "🎯 Total candidates: ${allTargetKids.length} (High Risk: ${highRiskKids.length}, Least Visited: ${leastVisitedKids.length})",
      );

      if (allTargetKids.isEmpty) {
        debugPrint("✅ No insights needed - all kids are engaged!");
        // Clear any previous insights
        await prefs.remove('ai_insight_kid_name');
        await prefs.remove('ai_insight_message');
        await prefs.remove('ai_insight_type');
        return;
      }

      // Pick one kid for today (rotate by day)
      final kidsList = allTargetKids.toList();
      final dayIndex = now.day % kidsList.length;
      final selectedKid = kidsList[dayIndex];

      final type = highRiskKids.contains(selectedKid)
          ? 'consecutive_absence'
          : 'least_visited';

      final message = _generateEncouragingMessage(type);

      debugPrint("📌 Selected kid for today: $selectedKid (Type: $type)");

      // Store in SharedPreferences
      await prefs.setString('ai_insight_kid_name', selectedKid);
      await prefs.setString('ai_insight_message', message);
      await prefs.setString('ai_insight_type', type);
      await prefs.setString('ai_insights_last_generated', todayStr);

      // Verify data was saved
      final savedKid = prefs.getString('ai_insight_kid_name');
      final savedMessage = prefs.getString('ai_insight_message');
      debugPrint("✅ Successfully generated and saved insight for $selectedKid");
      debugPrint(
        "🔍 Verification - Saved kid: $savedKid, Message length: ${savedMessage?.length}",
      );
    } catch (e) {
      debugPrint("❌ Error generating AI insights: $e");
    }
  }

  Future<List<String>> _detectConsecutiveAbsences() async {
    try {
      final reportsSnapshot = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.orderDesc('date'),
          Query.limit(2),
        ],
      );

      debugPrint("🔍 Attendance Reports Found: ${reportsSnapshot.total}");
      if (reportsSnapshot.total < 2) return [];

      final report1 = reportsSnapshot.documents[0];
      final report2 = reportsSnapshot.documents[1];

      final absentKids1 = _parseAbsentKids(report1.data['data']);
      final absentKids2 = _parseAbsentKids(report2.data['data']);

      debugPrint(
        "🔍 Absent Last Week: ${absentKids1.length}, Week Before: ${absentKids2.length}",
      );

      final consecutive = absentKids1
          .where((kid) => absentKids2.contains(kid))
          .toList();
      debugPrint("🔍 Consecutive Absences: ${consecutive.length}");

      return consecutive;
    } catch (e) {
      debugPrint("❌ Error detecting absences: $e");
      return [];
    }
  }

  List<String> _parseAbsentKids(dynamic data) {
    if (data == null) return [];
    try {
      // In Appwrite, data might be a JSON string or already a map
      final Map<String, dynamic> attendanceMap = (data is String)
          ? jsonDecode(data)
          : data;
      final List<String> absents = [];

      // Attendance structure: key=grade, value=List of {name, isPresent}
      attendanceMap.forEach((grade, list) {
        if (list is List) {
          for (var entry in list) {
            if (entry['isPresent'] == false) {
              absents.add(entry['name']);
            }
          }
        }
      });
      return absents;
    } catch (e) {
      debugPrint("❌ Error parsing attendance data: $e");
      return [];
    }
  }

  Future<List<String>> _detectLeastVisitedKids() async {
    try {
      final studentsSnapshot = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [Query.equal('groupId', groupId)],
      );

      debugPrint("🔍 Total Students to analyze: ${studentsSnapshot.total}");

      if (studentsSnapshot.total == 0) return [];

      // Fetch all visits to count them
      // Note: For very large datasets, we might need a more optimized query or a counter field.
      final visitsSnapshot = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: visitsCollectionId,
        queries: [
          Query.equal('groupId', groupId),
          Query.limit(5000), // High limit to cover most scenarios
        ],
      );

      debugPrint("🔍 Total Visits Found: ${visitsSnapshot.total}");

      final Map<String, int> visitCountMap = {};
      for (var doc in studentsSnapshot.documents) {
        visitCountMap[doc.data['name']] = 0;
      }

      for (var doc in visitsSnapshot.documents) {
        final kidName = doc.data['name'] ?? doc.data['kidName'];
        if (kidName != null && visitCountMap.containsKey(kidName)) {
          visitCountMap[kidName] = visitCountMap[kidName]! + 1;
        }
      }

      final List<String> sortedKids = visitCountMap.keys.toList();
      sortedKids.sort((a, b) => visitCountMap[a]!.compareTo(visitCountMap[b]!));

      // Return top 10 least visited
      final result = sortedKids.take(10).toList();
      debugPrint("🔍 Least Visited Candidate Count: ${result.length}");
      return result;
    } catch (e) {
      debugPrint("❌ Error detecting least visited kids: $e");
      return [];
    }
  }

  String _generateEncouragingMessage(String type) {
    List<String> encouragements;

    if (type == 'consecutive_absence') {
      encouragements = [
        "consecutive_absence_msg_1",
        "consecutive_absence_msg_2",
        "consecutive_absence_msg_3",
      ];
    } else {
      // least_visited
      encouragements = [
        "least_visited_msg_1",
        "least_visited_msg_2",
        "least_visited_msg_3",
        "least_visited_msg_4",
      ];
    }

    final random = DateTime.now().millisecond;
    final baseMessage = encouragements[random % encouragements.length];
    return baseMessage;
  }

  /// 🚀Force regeneration for debugging
  Future<void> forceGenerateInsights() async {
    debugPrint("⚠️ Force generating insights requested...");

    // Clear the cache to allow regeneration
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_insights_last_generated');
    await prefs.remove('ai_insights_last_scheduled');

    await generateInsights();

    // Also call scheduling immediately
    await schedulePendingNotifications();
  }

  /// 🚀 جدولة الإشعارات - مرتين في اليوم (صباحاً ومساءً) للمخدوم المختار اليوم
  Future<void> schedulePendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month}-${now.day}";

      // Check if we already scheduled for today
      final lastScheduled = prefs.getString('ai_insights_last_scheduled');
      if (lastScheduled == todayStr) {
        debugPrint("✅ Insights already scheduled for today");
        return;
      }

      // Get today's insight (should already be generated)
      final kidName = prefs.getString('ai_insight_kid_name');
      final message = prefs.getString('ai_insight_message');

      if (kidName == null || message == null) {
        debugPrint(
          "⚠️ No insight available to schedule. Generate insights first.",
        );
        return; // Exit gracefully instead of recursive call
      }

      debugPrint("📌 Scheduling notifications for: $kidName");

      debugPrint("📌 Scheduling notifications for: $kidName");

      final baseId = kidName.hashCode.abs() % 100000000;
      final random = Random();

      // Morning Window: 10:00 AM - 1:00 PM (13:00)
      int morningHour = 10 + random.nextInt(3); // 10, 11, 12
      int morningMinute = random.nextInt(60);

      // Evening Window: 6:00 PM (18:00) - 10:00 PM (22:00)
      int eveningHour = 18 + random.nextInt(4); // 18, 19, 20, 21
      int eveningMinute = random.nextInt(60);

      var morningTime = DateTime(
        now.year,
        now.month,
        now.day,
        morningHour,
        morningMinute,
      );
      var eveningTime = DateTime(
        now.year,
        now.month,
        now.day,
        eveningHour,
        eveningMinute,
      );

      // If time has passed today, schedule for tomorrow instead
      if (morningTime.isBefore(now)) {
        morningTime = DateTime(
          now.year,
          now.month,
          now.day + 1,
          morningHour,
          morningMinute,
        );
        debugPrint(
          "⏰ Morning time passed, scheduling for tomorrow: $morningTime",
        );
      }
      if (eveningTime.isBefore(now)) {
        eveningTime = DateTime(
          now.year,
          now.month,
          now.day + 1,
          eveningHour,
          eveningMinute,
        );
        debugPrint(
          "⏰ Evening time passed, scheduling for tomorrow: $eveningTime",
        );
      }

      final languageCode = LanguageService().currentLocale.value;
      final titleMorning = AppTranslations.translateWithoutContext(
        languageCode,
        "morning_reminder_title",
      );
      final titleEvening = AppTranslations.translateWithoutContext(
        languageCode,
        "evening_reminder_title",
      );

      final resolvedBody = AppTranslations.translateWithoutContext(
        languageCode,
        message,
      ).replaceAll('%s', kidName);
      final eveningBodyPart = AppTranslations.translateWithoutContext(
        languageCode,
        "evening_reminder_body",
      ).replaceAll('%s', kidName);

      await NotificationService().scheduleNotification(
        id: baseId + 10,
        title: titleMorning,
        body: resolvedBody,
        scheduledDate: morningTime,
      );

      await NotificationService().scheduleNotification(
        id: baseId + 20,
        title: titleEvening,
        body: eveningBodyPart,
        scheduledDate: eveningTime,
      );

      // Mark as scheduled for today
      await prefs.setString('ai_insights_last_scheduled', todayStr);

      debugPrint(
        "✅ Successfully scheduled AI insight notifications for $kidName",
      );
    } catch (e) {
      debugPrint("❌ Error scheduling AI insights: $e");
    }
  }

  /// 🚀 جلب مخدوم واحد فقط لليوم من SharedPreferences
  Stream<List<AIInsight>> getMyInsights() async* {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Initial load
      yield _loadInsightFromPrefs(prefs);

      // Poll for changes every 30 seconds (simple approach)
      await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
        final refreshedPrefs = await SharedPreferences.getInstance();
        yield _loadInsightFromPrefs(refreshedPrefs);
      }
    } catch (e) {
      debugPrint("❌ Error in getMyInsights stream: $e");
      yield [];
    }
  }

  List<AIInsight> _loadInsightFromPrefs(SharedPreferences prefs) {
    final kidName = prefs.getString('ai_insight_kid_name');
    String? message = prefs.getString('ai_insight_message');
    final type = prefs.getString('ai_insight_type');

    if (kidName == null || message == null || type == null) {
      return [];
    }

    // Migration logic: If the cached message contains spaces (like old Arabic phrases),
    // replace it with the new translation key so it works with all languages.
    if (message.contains(' ')) {
      message = type == 'consecutive_absence'
          ? 'consecutive_absence_msg_1'
          : 'least_visited_msg_1';
      prefs.setString('ai_insight_message', message);
    }

    return [
      AIInsight(
        id: 'daily_${DateTime.now().day}',
        kidName: kidName,
        type: type,
        message: message,
        assignedTo: 'local_user',
        assignedDate: DateTime.now(),
        status: 'pending',
      ),
    ];
  }

  Future<void> completeInsight(String insightId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_insight_kid_name');
    await prefs.remove('ai_insight_message');
    await prefs.remove('ai_insight_type');
    debugPrint("✅ Insight marked as completed (cleared from storage)");
  }

  Future<void> dismissInsight(String insightId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_insight_kid_name');
    await prefs.remove('ai_insight_message');
    await prefs.remove('ai_insight_type');
    debugPrint("✅ Insight dismissed (cleared from storage)");
  }
}
