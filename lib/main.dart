import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/attendance_type_selector_page.dart';
import 'pages/attendance_grade_selector_page.dart';
import 'pages/stats_page.dart';
import 'pages/visited_stats_page.dart';
import 'pages/attendance_stats_page.dart';
import 'pages/study_tracking_page.dart';
import 'pages/preparation_page.dart';
import 'pages/visited_page.dart' show VisitedPage;
import 'pages/meetings_page.dart';
import 'pages/admin_page.dart';
import 'pages/individual_visited_page.dart';
import 'pages/birthdays_page.dart';
import 'pages/absence_page.dart';
import 'pages/create_group_page.dart';
import 'pages/join_group_page.dart';
import 'pages/statuses_page.dart';
import 'services/notification_service.dart';
import 'services/appwrite_service.dart';
import 'services/settings_service.dart';
import 'services/background_task_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Appwrite
  AppwriteService().init();

  await initializeDateFormatting('ar', null);

  // تهيئة الإشعارات المحلية
  await NotificationService().init();
  NotificationService().listenToBroadcasts();

  // تهيئة المهام الخلفية (Background Tasks)
  await BackgroundTaskService.initialize();
  await BackgroundTaskService.scheduleDailyRecommendations();

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  // تهيئة إعدادات التطبيق (مثل حجم الخط)
  await SettingsService().init();

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: SettingsService().fontSizeMultiplier,
      builder: (context, fontSizeMultiplier, child) {
        return MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'خدمتي',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true, // Recommended for better scaling control
          ),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(fontSizeMultiplier)),
              child: child!,
            );
          },
          initialRoute: isLoggedIn ? '/dashboard' : '/login',
          routes: {
            '/login': (context) => const LoginPage(),
            '/dashboard': (context) => const DashboardWrapper(),
            '/visited': (context) => const VisitedPage(),
            '/individual_visited': (context) => const IndividualVisitedPage(),
            '/birthdays': (context) => const BirthdaysPage(),
            '/study_tracking': (context) => const StudyTrackingPage(),
            '/educational_tracker': (context) =>
                const AttendanceGradeSelectorPage(type: 'educational'),
            '/attended': (context) => const AttendanceTypeSelectorPage(),
            '/absence': (context) => const AbsencePage(),
            '/stats': (context) => const StatsHomePage(),
            '/stats/visited': (context) => VisitedStatsPage(),
            '/stats/attendance': (context) => const AttendanceStatsPage(),
            '/preparation': (context) => const PreparationListAndFormPage(),
            '/meetings': (context) => const MeetingsListPage(),
            '/admin': (context) => const AdminPage(),
            '/create_group': (context) => const CreateGroupPage(),
            '/join_group': (context) => const JoinGroupPage(),
            '/statuses': (context) => const StatusesPage(),
          },
        );
      },
    );
  }
}

class DashboardWrapper extends StatefulWidget {
  const DashboardWrapper({super.key});

  @override
  State<DashboardWrapper> createState() => _DashboardWrapperState();
}

class _DashboardWrapperState extends State<DashboardWrapper> {
  // ملاحظة: تم إزالة منطق الإشعارات وأعياد الميلاد مؤقتاً لحين ربطه بـ Appwrite

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: const DashboardPage(),
    );
  }
}
