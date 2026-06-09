import 'package:flutter/material.dart';
import 'dart:math'; // Fix: Import Random
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'dart:async';
import 'appwrite_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final Random _random = Random();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 🚀 أضف مفتاح الانتقال العالمي
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final Realtime _realtime = AppwriteService().realtime;
  StreamSubscription? _realtimeSubscription;

  Future<void> init() async {
    if (kIsWeb) return; // ⚡ Skip on Web
    // 1. تهيئة المنطقة الزمنية
    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint("⚠️ Could not get local timezone, falling back to UTC: $e");
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    // 2. إعدادات الأندرويد
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 3. إعدادات iOS
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload == 'statuses') {
          navigatorKey.currentState?.pushNamed('/statuses');
        }
      },
    );

    // Request permissions explicitly
    await checkAndRequestPermissions();
    await requestExactAlarmPermission();
  }

  Future<void> checkAndRequestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      final bool? granted = await androidImplementation
          ?.requestNotificationsPermission();
      debugPrint("🔔 Notification permission granted: $granted");
    }
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (kIsWeb) return [];
    return await _notificationsPlugin.pendingNotificationRequests();
  }

  /// Request Exact Alarm Permission (Android 12+)
  Future<void> requestExactAlarmPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Check if permission is needed and request if not granted
      final bool? canScheduleExact = await androidImplementation
          ?.canScheduleExactNotifications();

      debugPrint("🔔 Can schedule exact alarms: $canScheduleExact");

      if (canScheduleExact == false) {
        debugPrint("⚠️ Requesting exact alarm permission...");
        await androidImplementation?.requestExactAlarmsPermission();
      }
    }
  }

  void listenToBroadcasts() {
    _realtimeSubscription?.cancel();

    // سنستمع لإضافات المستندات في مجموعة الإشعارات
    final channel =
        'databases.${AppwriteService.databaseId}.collections.notifications.documents';

    _realtimeSubscription = _realtime.subscribe([channel]).stream.listen((
      message,
    ) {
      if (message.events.any((e) => e.contains('.create'))) {
        final data = message.payload;

        // إظهار الإشعار محلياً
        showNotificationNow(
          id: DateTime.now().millisecond,
          title: data['title'] ?? 'إعلان جديد 📢',
          body: data['body'] ?? 'لديك رسالة جديدة من الإدارة.',
        );
      }
    });
  }

  Future<void> showNotificationNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'birthday_channel',
        'Birthdays',
        channelDescription: 'Notifications for birthdays',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (kIsWeb) return;
    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'birthday_channel',
          'Birthdays',
          channelDescription: 'Notifications for birthdays',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    debugPrint("📅 Scheduled notification (ID: $id) at $scheduledDate");
  }

  Future<void> scheduleBirthdayNotification({
    required int id,
    required String title,
    required String body,
    required DateTime birthDate,
    int hour = 9,
    int minute = 0,
  }) async {
    final now = DateTime.now();

    // 1. Create candidate date for THIS year
    var scheduledDate = DateTime(
      now.year,
      birthDate.month,
      birthDate.day,
      hour,
      minute,
    );

    // 2. Check if it's in the past
    if (scheduledDate.isBefore(now)) {
      // If it resembles today (same day/month/year) but earlier time,
      // AND we are within the same day (e.g. it's 2 PM, scheduled was 9 AM),
      // we skip it and schedule for next year instead.
      if (scheduledDate.year == now.year &&
          scheduledDate.month == now.month &&
          scheduledDate.day == now.day) {
        // It's today, but we missed the time. Schedule for next year.
        debugPrint(
          "⏰ Missed birthday alert for today ($title). Scheduling for next year.",
        );
        scheduledDate = DateTime(
          now.year + 1,
          birthDate.month,
          birthDate.day,
          hour,
          minute,
        );
      } else {
        // It's a past date (yesterday or earlier), schedule for next year
        scheduledDate = DateTime(
          now.year + 1,
          birthDate.month,
          birthDate.day,
          hour,
          minute,
        );
      }
    }

    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
    );
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _notificationsPlugin.cancelAll();
  }

  Future<void> syncAllBirthdays(List<dynamic> kids) async {
    // 1. مسح الجدولة القديمة لتجنب التكرار
    await cancelAll();

    // 2. جدولة أعياد الميلاد القادمة (مرتين يومياً بأوقات عشوائية)
    int scheduledCount = 0;

    // Define windows: Morning (8-11 AM), Evening (4-7 PM)
    // We use a seed based on kid ID to ensure consistency if re-run on same day,
    // or just Random() for pure variety every sync. User asked for "different times",
    // so pure Random() is better for variety.

    for (var kid in kids) {
      if (kid.dateOfBirth != null) {
        final int baseId = kid.id.hashCode.abs() % 100000;

        // إشعار الصباح (عشوائي بين 8 و 11)
        final morningTime = _getRandomTimeInWindow(
          DateTime(
            DateTime.now().year,
            kid.dateOfBirth!.month,
            kid.dateOfBirth!.day,
          ),
          8,
          11,
        );

        await scheduleBirthdayNotification(
          id: baseId,
          title: "عيد ميلاد سعيد! 🎉",
          body: "اليوم هو عيد ميلاد المخدوم ${kid.name}. لا تنسى تهنئته! 🎂",
          birthDate: kid.dateOfBirth!,
          hour: morningTime.hour,
          minute: morningTime.minute,
        );

        // إشعار المساء (عشوائي بين 16 و 19 - أي 4 و 7 م)
        final eveningTime = _getRandomTimeInWindow(
          DateTime(
            DateTime.now().year,
            kid.dateOfBirth!.month,
            kid.dateOfBirth!.day,
          ),
          16,
          19,
        );

        await scheduleBirthdayNotification(
          id: baseId + 50000,
          title: "تذكير: عيد ميلاد! 🎂",
          body: "لا تنسى تهنئة ${kid.name} بعيد ميلاده اليوم! 🎉",
          birthDate: kid.dateOfBirth!,
          hour: eveningTime.hour,
          minute: eveningTime.minute,
        );

        scheduledCount += 2;
      }
    }
    debugPrint(
      "✅ تم جدولة $scheduledCount إشعار لـ ${kids.length} عيد ميلاد (أوقات عشوائية).",
    );

    // Debugging: Print the first 5 scheduled dates to verify
    if (kids.isNotEmpty) {
      debugPrint("🔍 Sample Birthday Scheduling Data:");
      for (var i = 0; i < (kids.length > 3 ? 3 : kids.length); i++) {
        debugPrint(" - Kid: ${kids[i].name}, DOB: ${kids[i].dateOfBirth}");
      }
    }
  }

  Future<void> sendBroadcast(
    String title,
    String body, {
    String? teamId,
  }) async {
    try {
      await AppwriteService().databases.createDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.notificationsCollectionId,
        documentId: ID.unique(),
        data: {
          'title': title,
          'body': body,
          'createdAt': DateTime.now().toIso8601String(),
        },
        permissions: teamId != null
            ? [Permission.read(Role.team(teamId))]
            : null,
      );
      debugPrint("✅ تم إرسال الإعلان بنجاح لجميع المتصلين.");
    } catch (e) {
      debugPrint("❌ فشل إرسال الإعلان: $e");
      rethrow;
    }
  }

  DateTime _getRandomTimeInWindow(DateTime date, int startHour, int endHour) {
    // Ensure valid range
    if (startHour >= endHour) endHour = startHour + 1;

    final hour = startHour + _random.nextInt(endHour - startHour);
    final minute = _random.nextInt(60);

    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
