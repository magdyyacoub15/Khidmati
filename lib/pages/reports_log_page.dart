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
import '../l10n/app_translations.dart';

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
  String _selectedCategory = 'attendance_category'; // الحضور / الافتقاد
  String _selectedType = 'kids_type'; // خدام / مخدومين
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
      final collectionId = _selectedCategory == 'attendance_category'
          ? attendanceRecordsCollectionId
          : visitedReportsCollectionId;

      final queries = [
        Query.equal('groupId', _myGroupId),
        Query.orderDesc('timestamp'),
        Query.limit(100),
      ];

      // Use fixed database strings for query to ensure consistency across languages
      if (_selectedCategory == 'attendance_category') {
        final List<String> typeQueries = [];
        if (_selectedType == 'servants_type') {
          typeQueries.addAll(['servants', 'خدام']);
        } else {
          typeQueries.addAll(['attendees', 'مخدومين']);
        }
        queries.add(
          Query.or(typeQueries.map((t) => Query.equal('type', t)).toList()),
        );
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
      appBar: AppBar(title: Text('historical_reports_log'.tr(context))),
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
        segments: [
          ButtonSegment(
            value: 'attendance_category',
            label: Text('attendance_category'.tr(context)),
            icon: const Icon(Icons.check_circle),
          ),
          ButtonSegment(
            value: 'visitation_category',
            label: Text('visitation_category'.tr(context)),
            icon: const Icon(Icons.search),
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
        segments: [
          ButtonSegment(
            value: 'kids_type',
            label: Text('kids_type'.tr(context)),
          ),
          ButtonSegment(
            value: 'servants_type',
            label: Text('servants_type'.tr(context)),
          ),
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
      return Center(
        child: Text(
          'no_reports_in_section'.tr(context),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchReports,
      child: ListView.builder(
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
            subtitle: Text(
              DateFormat(
                'yyyy/MM/dd HH:mm',
                Localizations.localeOf(context).languageCode,
              ).format(date),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
              onPressed: () => _printReport(context, doc),
            ),
          ),
        );
      },
    ),
    );
  }

  Future<void> _printReport(
    BuildContext flutterContext,
    models.Document reportDoc,
  ) async {
    try {
      if (_selectedCategory == 'attendance_category') {
        await _printAttendanceReport(flutterContext, reportDoc);
      } else {
        await _printVisitReport(flutterContext, reportDoc);
      }
    } catch (e) {
      debugPrint("Error printing report: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'error_printing_report'.tr(context)}: $e')),
        );
      }
    }
  }

  Future<void> _printAttendanceReport(
    BuildContext flutterContext,
    models.Document reportDoc,
  ) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/Alfares.ttf');
    final ttf = pw.Font.ttf(fontData);

    Map<String, dynamic> rawMap = {};
    final fileId = reportDoc.data['fileId'] as String?;

    if (fileId != null && fileId.isNotEmpty) {
      try {
        final byteList = await AppwriteService().storage.getFileDownload(
          bucketId: AppwriteService.attendanceBucketId,
          fileId: fileId,
        );
        final jsonString = utf8.decode(byteList);
        rawMap = jsonDecode(jsonString);
      } catch (e) {
        debugPrint("Error fetching attendance report file: $e");
        if (!flutterContext.mounted) return;
        throw 'failed_to_load_report_file'.tr(flutterContext);
      }
    } else {
      final dynamic dataField = reportDoc.data['data'];
      if (dataField == null) {
        if (!flutterContext.mounted) return;
        throw 'report_data_unavailable'.tr(flutterContext);
      }

      rawMap = (dataField is String)
          ? jsonDecode(dataField)
          : Map<String, dynamic>.from(dataField);
    }

    final reportName =
        reportDoc.data['reportName'] ??
        (flutterContext.mounted
            ? 'attendance_report_default_name'.tr(flutterContext)
            : 'Report');
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
                  'grade_label_pdf'
                      .tr(flutterContext)
                      .replaceFirst('%s', grade),
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
                headers: [
                  'name'.tr(flutterContext),
                  'status'.tr(flutterContext),
                  'by'.tr(flutterContext),
                  'notes'.tr(flutterContext),
                ],
                data: list.map((item) {
                  return [
                    item['name'] ?? "",
                    (item['isPresent'] == true)
                        ? 'present_status'.tr(flutterContext)
                        : 'absent_status'.tr(flutterContext),
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

  Future<void> _printVisitReport(
    BuildContext flutterContext,
    models.Document reportDoc,
  ) async {
    final reportDefaultName = 'visitation_report_default_name'.tr(
      flutterContext,
    );
    final failedLoadReportMsg = 'failed_to_load_report_file'.tr(flutterContext);
    final noReportDataMsg = 'no_report_data'.tr(flutterContext);

    final pdf = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/Alfares.ttf');
    final ttf = pw.Font.ttf(fontData);

    final reportName = reportDoc.data['reportName'] ?? reportDefaultName;
    final timestamp = reportDoc.data['timestamp'] ?? "";
    Map<String, dynamic> fullReportData = {};

    // 1. Try fileId
    final fileId = reportDoc.data['fileId'] as String?;
    if (fileId != null && fileId.isNotEmpty) {
      try {
        final byteList = await AppwriteService().storage.getFileDownload(
          bucketId:
              AppwriteService.attendanceBucketId, // Same bucket as attendance
          fileId: fileId,
        );
        final jsonString = utf8.decode(byteList);
        fullReportData = jsonDecode(jsonString);
      } catch (e) {
        debugPrint("Error fetching visit report file: $e");
        throw failedLoadReportMsg;
      }
    } else {
      // 2. Fallback to legacy `visited_reports_details`
      try {
        final detailsResult = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: visitedReportsDetailsCollectionId,
          queries: [Query.equal('reportId', reportDoc.$id), Query.limit(100)],
        );

        // Convert legacy structure to new structure map
        for (var detailDoc in detailsResult.documents) {
          final grade = detailDoc.data['grade'] ?? "";
          final List<dynamic> visited =
              (detailDoc.data['visited'] as List? ?? [])
                  .map((e) => (e is String) ? jsonDecode(e) : e)
                  .toList();
          final List<dynamic> unvisited =
              (detailDoc.data['unvisited'] as List? ?? [])
                  .map((e) => (e is String) ? jsonDecode(e) : e)
                  .toList();

          fullReportData[grade] = {"visited": visited, "unvisited": unvisited};
        }
      } catch (e) {
        debugPrint("Legacy fetch failed: $e");
      }
    }

    if (fullReportData.isEmpty) {
      throw noReportDataMsg;
    }

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

          // Sort grades if possible (keys are grades)
          final sortedKeys = fullReportData.keys.toList()..sort();

          for (var grade in sortedKeys) {
            final gradeData = fullReportData[grade];
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                child: pw.Text(
                  'grade_label_pdf'
                      .tr(flutterContext)
                      .replaceFirst('%s', grade),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    font: ttf,
                  ),
                ),
              ),
            );

            final List<dynamic> visited = gradeData['visited'] ?? [];
            final List<dynamic> unvisited = gradeData['unvisited'] ?? [];

            final List<List<String>> tableData = [];
            for (var v in visited) {
              tableData.add([
                v['name'] ?? "",
                'visited_status'.tr(flutterContext),
                v['visitedBy'] ?? "",
              ]);
            }
            for (var u in unvisited) {
              tableData.add([
                u['name'] ?? "",
                'not_visited_status'.tr(flutterContext),
                "",
              ]);
            }

            if (tableData.isNotEmpty) {
              widgets.add(
                pw.TableHelper.fromTextArray(
                  headers: [
                    'name'.tr(flutterContext),
                    'status'.tr(flutterContext),
                    'by'.tr(flutterContext),
                  ],
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
            } else {
              widgets.add(
                pw.Text(
                  'no_detailed_data_for_grade'.tr(flutterContext),
                  style: pw.TextStyle(font: ttf),
                ),
              );
            }
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
