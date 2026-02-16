import 'package:flutter/material.dart';

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
    final percentage = totalInGrade == 0 ? 0 : (visitedCount / totalInGrade * 100).toStringAsFixed(1);

    final visitedNames = visitedList.map((kid) => "${kid["name"]} (افتقده: ${kid["visitedBy"]})").toList();
    final visitedSet = visitedList.map((kid) => kid["name"]).toSet();

    // توليد أسماء غير المفتقدين بشكل مؤقت
    final unvisitedNames = List.generate(totalInGrade, (i) => "مخدوم ${i + 1}")
        .where((name) => !visitedSet.contains(name.replaceAll("مخدوم ", "")))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text("📘 $grade - أسبوع $date")),
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
              "نسبة الافتقاد: $percentage% من أصل $totalInGrade",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            ExpansionTile(
              title: Text("✅ تم افتقاد $visitedCount", style: const TextStyle(fontWeight: FontWeight.bold)),
              children: visitedNames.map((name) => ListTile(title: Text("✅ $name"))).toList(),
            ),

            const SizedBox(height: 10),

            ExpansionTile(
              title: Text("❌ لم يتم افتقاد $unvisitedCount", style: const TextStyle(fontWeight: FontWeight.bold)),
              children: unvisitedNames.map((name) => ListTile(title: Text("❌ $name"))).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
