import 'package:flutter/material.dart';
import 'visited_stats_page.dart';
import 'attendance_stats_page.dart';
import 'detailed_report_page.dart';
import '../l10n/app_translations.dart';

class StatsHomePage extends StatelessWidget {
  const StatsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF81D4FA), Color(0xFF0277BD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'statistics_title'.tr(context),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildButton(
                          context,
                          'visitation_statistics'.tr(context),
                          Icons.search,
                          VisitedStatsPage(),
                        ),
                        const SizedBox(height: 30),
                        _buildButton(
                          context,
                          'attendance_statistics'.tr(context),
                          Icons.check_circle,
                          const AttendanceStatsPage(),
                        ),
                        const SizedBox(height: 30),
                        _buildButton(
                          context,
                          'detailed_reports'.tr(context),
                          Icons.picture_as_pdf,
                          const DetailedReportPage(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 5,
              bottom: 5,
              child: Opacity(
                opacity: 0.8,
                child: Image.asset(
                  "assets/images/magdi_yacoub.png",
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    String title,
    IconData icon,
    Widget page,
  ) {
    return ElevatedButton.icon(
      onPressed: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      icon: Icon(icon, size: 28),
      label: Text(title, style: const TextStyle(fontSize: 20)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blueAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 4,
      ),
    );
  }
}
