import 'package:flutter/material.dart';
import '../l10n/app_translations.dart';

class GradeDetailsPage extends StatelessWidget {
  final String grade;
  final String date;
  final List<Map<String, dynamic>> visitedList;
  final int totalInGrade;

  const GradeDetailsPage({
    super.key,
    required this.grade,
    required this.date,
    required this.visitedList,
    required this.totalInGrade,
  });

  @override
  Widget build(BuildContext context) {
    final visitedCount = visitedList.length;
    final unvisitedCount = totalInGrade - visitedCount;
    final String percentageStr = totalInGrade == 0
        ? "0"
        : (visitedCount / totalInGrade * 100).toStringAsFixed(1);

    final visitedNames = visitedList.map((kid) {
      final String name = kid["name"] ?? "";
      final String visitedBy = kid["visitedBy"] ?? "";
      final String label = 'visited_by_label'
          .tr(context)
          .replaceFirst('%s', visitedBy);
      return "$name ($label)";
    }).toList();

    final visitedSet = visitedList.map((kid) => kid["name"]).toSet();

    final String kidLabelBase = 'kid_label'.tr(context).replaceFirst('%s', "");

    final unvisitedNames =
        List.generate(
          totalInGrade,
          (i) => 'kid_label'.tr(context).replaceFirst('%s', (i + 1).toString()),
        ).where((name) {
          final String baseName = name.replaceAll(kidLabelBase, "").trim();
          return !visitedSet.contains(baseName);
        }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "📘 $grade - ${'week_label'.tr(context).replaceFirst('%s', date)}",
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE1F5FE), Color(0xFF81D4FA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'visit_percentage_total'
                  .tr(context)
                  .replaceFirst('%s', percentageStr)
                  .replaceFirst('%s', totalInGrade.toString()),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ExpansionTile(
              title: Text(
                'visited_count_label'
                    .tr(context)
                    .replaceFirst('%s', visitedCount.toString()),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              children: visitedNames
                  .map((name) => ListTile(title: Text("✅ $name")))
                  .toList(),
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              title: Text(
                'not_visited_count_label'
                    .tr(context)
                    .replaceFirst('%s', unvisitedCount.toString()),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              children: unvisitedNames
                  .map((name) => ListTile(title: Text("❌ $name")))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
