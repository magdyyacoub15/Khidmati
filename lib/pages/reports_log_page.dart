import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

class ReportsLogPage extends StatefulWidget {
  const ReportsLogPage({super.key});

  @override
  State<ReportsLogPage> createState() => _ReportsLogPageState();
}

class _ReportsLogPageState extends State<ReportsLogPage> {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String attendanceRecordsCollectionId = 'attendance_records';
  static const String visitedReportsCollectionId = 'visited_reports';
  static const String visitedReportsDetailsCollectionId =
      'visited_reports_details';

  String _myGroupId = '';
  bool _isLoading = true;
  String _selectedCategory = "الحضور"; // الحضور / الافتقاد
  String _selectedType = "مخدومين"; // خدام / مخدومين
  List<models.Document> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );
      if (mounted) {
        setState(() {
          _myGroupId = doc.data['groupId'] ?? '';
        });
        if (_myGroupId.isNotEmpty) {
          _fetchReports();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    try {
      final collectionId = _selectedCategory == "الحضور"
          ? attendanceRecordsCollectionId
          : visitedReportsCollectionId;

      final queries = [
        Query.equal('groupId', _myGroupId),
        Query.orderDesc('timestamp'),
        Query.limit(100),
      ];

      // Only attendance has a 'type' field in the main record for now based on attendance_stats_page.dart
      if (_selectedCategory == "الحضور") {
        queries.add(Query.equal('type', _selectedType));
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: queries,
      );

      if (mounted) {
        setState(() {
          _reports = result.documents;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching reports: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("سجل التقارير التاريخية")),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            _buildCategorySelector(),
            _buildTypeSelector(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _buildReportsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: "الحضور",
            label: Text("الحضور"),
            icon: Icon(Icons.check_circle),
          ),
          ButtonSegment(
            value: "الافتقاد",
            label: Text("الافتقاد"),
            icon: Icon(Icons.search),
          ),
        ],
        selected: {_selectedCategory},
        onSelectionChanged: (val) {
          setState(() {
            _selectedCategory = val.first;
            _reports = [];
          });
          _fetchReports();
        },
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: "مخدومين", label: Text("مخدومين")),
          ButtonSegment(value: "خدام", label: Text("خدام")),
        ],
        selected: {_selectedType},
        onSelectionChanged: (val) {
          setState(() {
            _selectedType = val.first;
            _reports = [];
          });
          _fetchReports();
        },
      ),
    );
  }

  Widget _buildReportsList() {
    if (_reports.isEmpty) {
      return const Center(
        child: Text(
          "لا توجد تقارير في هذا القسم",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (context, index) {
        final doc = _reports[index];
        final name = doc.data['reportName'] ?? doc.$id;
        final timestampStr = doc.data['timestamp'] as String?;
        final date = timestampStr != null
            ? DateTime.parse(timestampStr)
            : DateTime.now();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(date)),
            trailing: IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: () => _printReport(doc),
            ),
          ),
        );
      },
    );
  }

  Future<void> _printReport(models.Document reportDoc) async {
    try {
      if (_selectedCategory == "الحضور") {
        await _printAttendanceReport(reportDoc);
      } else {
        await _printVisitReport(reportDoc);
      }
    } catch (e) {
      debugPrint("Error printing report: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ أثناء طباعة التقرير: $e")),
        );
      }
    }
  }

  Future<void> _printAttendanceReport(models.Document reportDoc) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/Alfares.ttf");
    final ttf = pw.Font.ttf(fontData);

    final dynamic dataField = reportDoc.data['data'];
    if (dataField == null) throw "بيانات التقرير غير متوفرة";

    final Map<String, dynamic> rawMap = (dataField is String)
        ? jsonDecode(dataField)
        : Map<String, dynamic>.from(dataField);

    final reportName = reportDoc.data['reportName'] ?? "تقرير حضور";
    final timestamp = reportDoc.data['timestamp'] ?? "";

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: ttf),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          List<pw.Widget> widgets = [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    reportName,
                    style: pw.TextStyle(fontSize: 20, font: ttf),
                  ),
                  pw.Text(
                    timestamp,
                    style: pw.TextStyle(fontSize: 12, font: ttf),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
          ];

          rawMap.forEach((grade, listDynamic) {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Text(
                  "🔹 فصل: $grade",
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    font: ttf,
                  ),
                ),
              ),
            );

            final List<dynamic> list = listDynamic as List<dynamic>;
            widgets.add(
              pw.TableHelper.fromTextArray(
                headers: ['الاسم', 'الحالة', 'بواسطة', 'ملاحظات'],
                data: list.map((item) {
                  return [
                    item['name'] ?? "",
                    (item['isPresent'] == true) ? "✅ حاضر" : "❌ غائب",
                    item['markedBy'] ?? "",
                    item['note'] ?? "",
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  font: ttf,
                ),
                cellStyle: pw.TextStyle(font: ttf),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellAlignment: pw.Alignment.center,
              ),
            );
          });

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'attendance_${reportDoc.$id}.pdf',
    );
  }

  Future<void> _printVisitReport(models.Document reportDoc) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/Alfares.ttf");
    final ttf = pw.Font.ttf(fontData);

    // Visit reports store details in visited_reports_details collection
    final detailsResult = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: visitedReportsDetailsCollectionId,
      queries: [Query.equal('reportId', reportDoc.$id), Query.limit(100)],
    );

    final reportName = reportDoc.data['reportName'] ?? "تقرير افتقاد";
    final timestamp = reportDoc.data['timestamp'] ?? "";

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: ttf),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          List<pw.Widget> widgets = [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    reportName,
                    style: pw.TextStyle(fontSize: 20, font: ttf),
                  ),
                  pw.Text(
                    timestamp,
                    style: pw.TextStyle(fontSize: 12, font: ttf),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
          ];

          for (var detailDoc in detailsResult.documents) {
            final grade = detailDoc.data['grade'] ?? "";
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Text(
                  "🔹 فصل: $grade",
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    font: ttf,
                  ),
                ),
              ),
            );

            final List<dynamic> visited =
                (detailDoc.data['visited'] as List? ?? [])
                    .map((e) => (e is String) ? jsonDecode(e) : e)
                    .toList();
            final List<dynamic> unvisited =
                (detailDoc.data['unvisited'] as List? ?? [])
                    .map((e) => (e is String) ? jsonDecode(e) : e)
                    .toList();

            final List<List<String>> tableData = [];
            for (var v in visited) {
              tableData.add([
                v['name'] ?? "",
                "✅ تم افتقاده",
                v['visitedBy'] ?? "",
              ]);
            }
            for (var u in unvisited) {
              tableData.add([u['name'] ?? "", "❌ لم يتم افتقاده", ""]);
            }

            widgets.add(
              pw.TableHelper.fromTextArray(
                headers: ['الاسم', 'الحالة', 'بواسطة'],
                data: tableData,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  font: ttf,
                ),
                cellStyle: pw.TextStyle(font: ttf),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellAlignment: pw.Alignment.center,
              ),
            );
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'visits_${reportDoc.$id}.pdf',
    );
  }
}
