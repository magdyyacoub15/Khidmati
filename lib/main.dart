import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_localizations/flutter_localizations.dart';

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
import 'services/language_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة اللغات
  await LanguageService().init();

  // تهيئة Appwrite
  AppwriteService().init();

  await initializeDateFormatting('ar', null);

  // تهيئة الإشعارات المحلية
  if (!kIsWeb) {
    await NotificationService().init();
    NotificationService().listenToBroadcasts();
  }

  // تهيئة المهام الخلفية (Background Tasks) - لا تعمل على الويب
  if (!kIsWeb) {
    await BackgroundTaskService.initialize();
    await BackgroundTaskService.scheduleDailyRecommendations();
  }

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
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService().currentLocale,
      builder: (context, currentLang, child) {
        return ValueListenableBuilder<double>(
          valueListenable: SettingsService().fontSizeMultiplier,
          builder: (context, fontSizeMultiplier, child) {
            return MaterialApp(
              navigatorKey: NotificationService.navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'خدمتي',
              theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
              // Force English globally to prevent TimePicker crashes and keep english numerals
              locale: const Locale('en', 'US'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en', 'US')],
              builder: (context, child) {
                // Apply font scaling
                final scaledChild = MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(fontSizeMultiplier)),
                  child: Directionality(
                    // Dynamically set layout direction based on selected language
                    textDirection: currentLang == 'ar'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: child!,
                  ),
                );

                if (kIsWeb) {
                  return Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: scaledChild,
                    ),
                  );
                }

                return scaledChild;
              },
              initialRoute: isLoggedIn ? '/dashboard' : '/login',
              routes: {
                '/login': (context) => const LoginPage(),
                '/dashboard': (context) => const DashboardWrapper(),
                '/visited': (context) => const VisitedPage(),
                '/individual_visited': (context) =>
                    const IndividualVisitedPage(),
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
