// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/grade_service.dart';
import '../services/data_cache_service.dart';

class DetailedReportPage extends StatefulWidget {
  const DetailedReportPage({super.key});

  @override
  State<DetailedReportPage> createState() => _DetailedReportPageState();
}

class _DetailedReportPageState extends State<DetailedReportPage> {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Client _client = AppwriteService().client;
  late Realtime _realtime;
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String studentsCollectionId = 'students';
  static const String visitedReportsCollectionId = 'visited_reports';
  static const String visitedReportsDetailsCollectionId =
      'visited_reports_details';
  static const String attendanceRecordsCollectionId = 'attendance_records';

  String _myGroupId = '';
  bool _isLoading = true;

  final String _selectedType = "مخدومين";
  String _selectedScope = "الكل";
  String? _selectedGrade;
  List<String> _selectedPeopleNames = [];
  DateTimeRange? _selectedDateRange;

  List<String> _allGrades = [];
  List<String> _availablePeople = [];
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _realtime = Realtime(_client);
    _loadUserData();
  }

  @override
  void dispose() {
    _userSubscription?.close();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();
      final userId = user.$id;

      // 1. Check Cache
      final cachedCtx = await DataCacheService().getCachedUserGroupId(userId);
      if (cachedCtx != null) {
        _applyUserData(cachedCtx['groupId']!);
      }

      // 2. Initial Fetch
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );

      _updateState(doc.data);
      // Update Cache
      await DataCacheService().cacheUserGroupId(
        userId,
        doc.data['groupId'],
        doc.data['teamId'],
        doc.data['role'],
      );

      // 3. Realtime Listener
      _userSubscription?.close();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.$userId',
      ]);

      _userSubscription!.stream.listen((event) {
        if (mounted) {
          _updateState(event.payload);
        }
      });
    } catch (e) {
      debugPrint(
        "Error loading user data in DetailedReportPage: $e. Trying global cache.",
      );
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        _applyUserData(lastData['groupId']);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _applyUserData(String groupId) {
    if (mounted) {
      setState(() {
        _myGroupId = groupId;
      });
      if (_myGroupId.isNotEmpty) {
        _fetchGrades();
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateState(Map<String, dynamic> data) async {
    if (mounted) {
      setState(() {
        _myGroupId = data['groupId'] ?? '';
      });
      if (_myGroupId.isNotEmpty) {
        await _fetchGrades();
        await _fetchPeople();
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchGrades() async {
    try {
      final grades = await GradeService(groupId: _myGroupId).getGrades();
      if (mounted) {
        setState(() {
          _allGrades = grades;
        });
      }
    } catch (e) {
      debugPrint("Error fetching grades: $e");
    }
  }

  Future<void> _fetchPeople() async {
    if (_myGroupId.isEmpty) return;
    try {
      final collectionId = studentsCollectionId;
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [Query.equal('groupId', _myGroupId), Query.limit(1000)],
      );

      final names = result.documents
          .map((doc) => doc.data['name'] as String)
          .toList();
      names.sort();

      if (mounted) {
        setState(() {
          _availablePeople = names;
        });
      }
    } catch (e) {
      debugPrint("Error fetching people: $e");
    }
  }

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("التقارير التفصيلية")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0288D1),
      appBar: AppBar(title: const Text("التقارير التفصيلية")),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // _buildSectionTitle("1. نوع التقرير"),
              // _buildTypeSelector(),
              // const SizedBox(height: 20),
              _buildSectionTitle("1. نطاق البحث"),
              _buildScopeSelector(),
              if (_selectedScope == "فصل محدد") ...[
                const SizedBox(height: 10),
                _buildGradeSelector(),
              ],
              if (_selectedScope == "أشخاص محددون") ...[
                const SizedBox(height: 10),
                _buildPeopleSelector(),
              ],
              const SizedBox(height: 20),

              _buildSectionTitle("3. الفترة الزمنية"),
              _buildDateRangeSelector(),
              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: _isExporting ? null : _generateAndDownloadReport,
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: const Text(
                  "توليد ملف PDF",
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildScopeSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          RadioListTile<String>(
            title: const Text("الكل"),
            value: "الكل",
            groupValue: _selectedScope,
            onChanged: (val) => setState(() => _selectedScope = val!),
          ),
          RadioListTile<String>(
            title: const Text("فصل محدد"),
            value: "فصل محدد",
            groupValue: _selectedScope,
            onChanged: (val) => setState(() => _selectedScope = val!),
          ),
          RadioListTile<String>(
            title: const Text("أشخاص محددون"),
            value: "أشخاص محددون",
            groupValue: _selectedScope,
            onChanged: (val) => setState(() => _selectedScope = val!),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            hint: const Text("اختر الفصل"),
            isExpanded: true,
            value: _selectedGrade,
            items: _allGrades
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: (val) => setState(() => _selectedGrade = val),
          ),
        ),
      ),
    );
  }

  Widget _buildPeopleSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            OutlinedButton(
              onPressed: _showMultiSelectPeople,
              child: const Text("اختيار الأسماء"),
            ),
            if (_selectedPeopleNames.isNotEmpty)
              Wrap(
                spacing: 8,
                children: _selectedPeopleNames
                    .map(
                      (name) => Chip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        onDeleted: () =>
                            setState(() => _selectedPeopleNames.remove(name)),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _showMultiSelectPeople() {
    showDialog(
      context: context,
      builder: (context) {
        List<String> tempSelected = List.from(_selectedPeopleNames);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("اختر الأسماء"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availablePeople.length,
                  itemBuilder: (context, index) {
                    final name = _availablePeople[index];
                    final isSelected = tempSelected.contains(name);
                    return CheckboxListTile(
                      title: Text(name),
                      value: isSelected,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            tempSelected.add(name);
                          } else {
                            tempSelected.remove(name);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedPeopleNames = tempSelected);
                    Navigator.pop(context);
                  },
                  child: const Text("تم"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        onTap: _pickDateRange,
        leading: const Icon(Icons.date_range),
        title: Text(
          _selectedDateRange == null
              ? "اختر الفترة"
              : "${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}",
        ),
        trailing: const Icon(Icons.edit),
      ),
    );
  }

  Future<void> _generateAndDownloadReport() async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى اختيار الفترة الزمنية أولاً")),
      );
      return;
    }
    if (_selectedScope == "فصل محدد" && _selectedGrade == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("يرجى اختيار الفصل أولاً")));
      return;
    }
    if (_selectedScope == "أشخاص محددون" && _selectedPeopleNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى اختيار شخص واحد على الأقل")),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final Map<String, PersonSummary> results = {};

      // 1. تحديد أسماء المستهدفين
      Set<String>? filterNames;
      if (_selectedScope == "أشخاص محددون") {
        filterNames = _selectedPeopleNames.toSet();
      }

      // 2. جلب وتجميع سجلات الحضور
      final attendanceSnap = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceRecordsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('type', 'مخدومين'),
          Query.greaterThanEqual(
            'timestamp',
            _selectedDateRange!.start.toIso8601String(),
          ),
          Query.lessThanEqual(
            'timestamp',
            _selectedDateRange!.end
                .add(const Duration(days: 1))
                .toIso8601String(),
          ),
          Query.limit(100),
        ],
      );

      for (var reportDoc in attendanceSnap.documents) {
        final timestampStr = reportDoc.data['timestamp'] as String;
        final dateStr = DateFormat(
          'yyyy/MM/dd',
        ).format(DateTime.parse(timestampStr));

        // In the new unified records, data is stored as a JSON map in the document
        final dynamic dataField = reportDoc.data['data'];
        if (dataField == null) continue;

        final Map<String, dynamic> rawMap = (dataField is String)
            ? jsonDecode(dataField)
            : Map<String, dynamic>.from(dataField);

        rawMap.forEach((grade, listDynamic) {
          if (_selectedScope == "فصل محدد" && grade != _selectedGrade) {
            return;
          }

          final List<dynamic> list = listDynamic as List<dynamic>;
          for (var item in list) {
            final name = item['name'] as String;
            if (filterNames != null && !filterNames.contains(name)) continue;

            final summary = results.putIfAbsent(
              name,
              () => PersonSummary(name),
            );
            summary.totalSessions++;
            if (item['isPresent'] == true) {
              summary.attendanceCount++;
              summary.attendanceDates.add(dateStr);
            }
          }
        });
      }

      // 3. جلب وتجميع سجلات الافتقاد
      final visitsSnap = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: visitedReportsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.greaterThanEqual(
            'timestamp',
            _selectedDateRange!.start.toIso8601String(),
          ),
          Query.lessThanEqual(
            'timestamp',
            _selectedDateRange!.end
                .add(const Duration(days: 1))
                .toIso8601String(),
          ),
          Query.limit(100),
        ],
      );

      for (var reportDoc in visitsSnap.documents) {
        final timestampStr = reportDoc.data['timestamp'] as String;
        final dateStr = DateFormat(
          'yyyy/MM/dd',
        ).format(DateTime.parse(timestampStr));

        final detailsResult = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: visitedReportsDetailsCollectionId,
          queries: [Query.equal('reportId', reportDoc.$id), Query.limit(100)],
        );

        for (var detailDoc in detailsResult.documents) {
          if (_selectedScope == "فصل محدد" &&
              detailDoc.data['grade'] != _selectedGrade) {
            continue;
          }

          final List<dynamic> visitedList =
              (detailDoc.data['visited'] as List? ?? [])
                  .map((item) => jsonDecode(item))
                  .toList();
          final List<dynamic> unvisitedList =
              (detailDoc.data['unvisited'] as List? ?? [])
                  .map((item) => jsonDecode(item))
                  .toList();

          for (var item in visitedList) {
            final name = item['name'] as String;
            if (filterNames != null && !filterNames.contains(name)) continue;

            final summary = results.putIfAbsent(
              name,
              () => PersonSummary(name),
            );
            summary.totalVisitOpportunities++;
            summary.visitCount++;
            summary.visitDates.add(dateStr);
          }
          for (var item in unvisitedList) {
            final name = item['name'] as String;
            if (filterNames != null && !filterNames.contains(name)) continue;

            final summary = results.putIfAbsent(
              name,
              () => PersonSummary(name),
            );
            summary.totalVisitOpportunities++;
          }
        }
      }

      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("لا توجد بيانات للفترة المحددة")),
          );
        }
      } else {
        await _generatePdf(results);
      }
    } catch (e) {
      debugPrint("Error generating report: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ أثناء تجميع البيانات: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _generatePdf(Map<String, PersonSummary> results) async {
    final pdf = pw.Document();

    // تحميل الخط العربي
    final fontData = await rootBundle.load("assets/fonts/Alfares.ttf");
    final ttf = pw.Font.ttf(fontData);

    final String dateRangeStr = _selectedDateRange == null
        ? ""
        : "${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}";

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: ttf),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "تقرير تفصيلي - $_selectedType",
                    style: pw.TextStyle(fontSize: 24, font: ttf),
                  ),
                  pw.Text(
                    DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    style: pw.TextStyle(font: ttf),
                  ),
                ],
              ),
            ),
            pw.Paragraph(
              text: "الفترة: $dateRangeStr",
              style: pw.TextStyle(font: ttf),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['الاسم', 'الحضور', 'الغياب', 'الافتقاد'],
              data: results.values.map((p) {
                final absentCount = p.totalSessions - p.attendanceCount;
                return [
                  p.name,
                  "${p.attendanceCount} / ${p.totalSessions}",
                  "$absentCount",
                  "${p.visitCount} / ${p.totalVisitOpportunities}",
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
            if (results.length == 1) ...[
              pw.SizedBox(height: 30),
              pw.Text(
                "تفاصيل التواريخ:",
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  font: ttf,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "تواريخ الحضور:",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: ttf,
                          ),
                        ),
                        ...results.values.first.attendanceDates.map(
                          (d) =>
                              pw.Text("- $d", style: pw.TextStyle(font: ttf)),
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "تواريخ الافتقاد:",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: ttf,
                          ),
                        ),
                        ...results.values.first.visitDates.map(
                          (d) =>
                              pw.Text("- $d", style: pw.TextStyle(font: ttf)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'detailed_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}

class PersonSummary {
  final String name;
  int attendanceCount = 0;
  int totalSessions = 0;
  int visitCount = 0;
  int totalVisitOpportunities = 0;
  List<String> attendanceDates = [];
  List<String> visitDates = [];

  PersonSummary(this.name);
}
