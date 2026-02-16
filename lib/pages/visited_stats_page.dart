import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import '../services/permission_service.dart';
import '../services/data_cache_service.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

class VisitedStatsPage extends StatefulWidget {
  const VisitedStatsPage({super.key});

  @override
  State<VisitedStatsPage> createState() => _VisitedStatsPageState();
}

class _VisitedStatsPageState extends State<VisitedStatsPage> {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Client _client = AppwriteService().client;
  late Realtime _realtime;
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String visitedReportsCollectionId = 'visited_reports';
  static const String visitedReportsDetailsCollectionId =
      'visited_reports_details';

  String _myGroupId = '';
  bool _isAdmin = false;
  bool _isLoading = true;
  List<models.Document> _reports = [];
  bool _isFetchingMore = false;
  bool _hasNextPage = true;
  final int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _realtime = Realtime(_client);
    _fetchUserData();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasNextPage &&
        !_isLoading) {
      _fetchReports(isLoadMore: true);
    }
  }

  @override
  void dispose() {
    _userSubscription?.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = await _account.get();

      // 1. Check Cache
      final cachedCtx = await DataCacheService().getCachedUserGroupId(user.$id);
      if (cachedCtx != null) {
        if (mounted) {
          setState(() {
            _myGroupId = cachedCtx['groupId']!;
            _isAdmin = cachedCtx['role'] == 'admin';
            // Don't set isLoading false yet, wait for reports
          });
          if (_myGroupId.isNotEmpty) _fetchReports();
        }
      }

      // 2. Initial Fetch
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      _updateState(doc.data);
      // Update Cache
      await DataCacheService().cacheUserGroupId(
        user.$id,
        doc.data['groupId'],
        doc.data['teamId'], // 🆕 Pass Team ID from User Doc
        doc.data['role'],
      );

      // 3. Realtime Listener
      _userSubscription?.close();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);

      _userSubscription!.stream.listen((event) {
        if (mounted) {
          _updateState(event.payload);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _updateState(Map<String, dynamic> data) {
    if (mounted) {
      setState(() {
        _myGroupId = data['groupId'] ?? '';
        _isAdmin = data['role'] == 'admin';
      });
      if (_myGroupId.isNotEmpty) {
        _fetchReports();
      }
    }
  }

  Future<void> _fetchReports({bool isLoadMore = false}) async {
    if (isLoadMore) {
      if (!_hasNextPage) return;
      setState(() => _isFetchingMore = true);
    } else {
      // 1. Check Cache (Only for first page)
      final cached = await DataCacheService().getCachedVisitedReports(
        _myGroupId,
      );
      if (cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            _reports = cached.map((d) => models.Document.fromMap(d)).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = true);
      }
      _hasNextPage = true;
    }

    try {
      final List<String> queries = [
        Query.equal('groupId', _myGroupId),
        Query.orderDesc('timestamp'),
        Query.limit(_pageSize),
      ];

      if (isLoadMore && _reports.isNotEmpty) {
        queries.add(Query.cursorAfter(_reports.last.$id));
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: visitedReportsCollectionId,
        queries: queries,
      );

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _reports.addAll(result.documents);
            _isFetchingMore = false;
          } else {
            _reports = result.documents;
            _isLoading = false;

            // Cache only the first page
            final dataToCache = result.documents.map((d) => d.toMap()).toList();
            DataCacheService().cacheVisitedReports(_myGroupId, dataToCache);
          }
          _hasNextPage = result.documents.length == _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  // 🔍 متغيرات الفلترة
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  List<models.Document> _filterReports(List<models.Document> reports) {
    return reports.where((doc) {
      final data = doc.data;
      final timestampStr = data["timestamp"] as String?;
      final timestamp = timestampStr != null
          ? DateTime.parse(timestampStr)
          : null;

      // فلترة حسب التاريخ
      bool matchesDate = true;
      if (_selectedStartDate != null && timestamp != null) {
        matchesDate = matchesDate && timestamp.isAfter(_selectedStartDate!);
      }
      if (_selectedEndDate != null && timestamp != null) {
        final endDate = DateTime(
          _selectedEndDate!.year,
          _selectedEndDate!.month,
          _selectedEndDate!.day,
          23,
          59,
          59,
        );
        matchesDate = matchesDate && timestamp.isBefore(endDate);
      }

      return matchesDate;
    }).toList();
  }

  // 🔍 دالة اختيار التاريخ
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _selectedStartDate = picked;
        } else {
          _selectedEndDate = picked;
        }
      });
    }
  }

  // 🔍 دالة مسح الفلترة
  void _clearFilters() {
    setState(() {
      _selectedStartDate = null;
      _selectedEndDate = null;
    });
  }

  // 🔍 شريط الفلترة
  Widget _buildFilterSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedStartDate == null
                                  ? "من التاريخ"
                                  : DateFormat(
                                      'yyyy/MM/dd',
                                    ).format(_selectedStartDate!),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedEndDate == null
                                  ? "إلى التاريخ"
                                  : DateFormat(
                                      'yyyy/MM/dd',
                                    ).format(_selectedEndDate!),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_selectedStartDate != null || _selectedEndDate != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.clear_all),
                  label: const Text("مسح الفلترة"),
                  onPressed: _clearFilters,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteReport(String reportId, String reportName) async {
    // 🔐 Security Check
    final hasPermission = await PermissionService.canWrite(_myGroupId);
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "⚠️ الخدمة مجمدة مؤقتاً (راجع الاشتراك أو الإنترنت)",
            ),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف التقرير", textAlign: TextAlign.right),
        content: Text(
          "هل أنت متأكد من حذف تقرير '$reportName'؟ سيتم حذف جميع التفاصيل المرتبطة به.",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("حذف"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 1. حذف التفاصيل المرتبطة
        final details = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: visitedReportsDetailsCollectionId,
          queries: [Query.equal('reportId', reportId)],
        );

        for (var doc in details.documents) {
          await _databases.deleteDocument(
            databaseId: databaseId,
            collectionId: visitedReportsDetailsCollectionId,
            documentId: doc.$id,
          );
        }

        // 2. حذف التقرير الرئيسي
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: visitedReportsCollectionId,
          documentId: reportId,
        );

        setState(() {}); // refresh list
        if (mounted) {
          _fetchReports(); // refresh list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ تم حذف التقرير بنجاح")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("❌ فشل في الحذف: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("📋 سجل الافتقاد الموحد")),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _myGroupId.isEmpty
              ? const Center(
                  child: Text(
                    "⚠️ خطأ: لم يتم العثور على رمز المجموعة.",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                )
              : _buildReportsList(),
        ),
      ),
    );
  }

  Widget _buildReportsList() {
    if (_reports.isEmpty) {
      return const Center(
        child: Text(
          "⚠️ لا توجد سجلات افتقاد موحدة متاحة.",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }
    final filteredReports = _filterReports(_reports);

    if (filteredReports.isEmpty) {
      return const Center(
        child: Text(
          "⚠️ لا توجد نتائج تطابق الفلترة",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return Column(
      children: [
        _buildFilterSection(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: filteredReports.length + (_hasNextPage ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == filteredReports.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              }
              return VisitedReportCard(
                doc: filteredReports[index],
                isAdmin: _isAdmin,
                onDelete: () => _confirmDeleteReport(
                  filteredReports[index].$id,
                  filteredReports[index].data["reportName"] ?? "",
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------
// 🧱 VisitedReportCard (Lazy Loading)
// -------------------------------------------------------------------

class VisitedReportCard extends StatefulWidget {
  final models.Document doc;
  final bool isAdmin;
  final VoidCallback onDelete;

  const VisitedReportCard({
    super.key,
    required this.doc,
    required this.isAdmin,
    required this.onDelete,
  });

  @override
  State<VisitedReportCard> createState() => _VisitedReportCardState();
}

class _VisitedReportCardState extends State<VisitedReportCard> {
  bool _isLoadingDetails = false;
  List<Map<String, dynamic>> _details = [];
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String visitedReportsDetailsCollectionId =
      'visited_reports_details';

  @override
  void initState() {
    super.initState();
    // Pre-check for cached details
    _checkCache();
  }

  Future<void> _checkCache() async {
    final cached = await DataCacheService().getCachedVisitedDetails(
      widget.doc.$id,
    );
    if (cached != null && cached.isNotEmpty) {
      if (mounted) {
        setState(() {
          _details = List<Map<String, dynamic>>.from(cached);
        });
      }
    }
  }

  Future<void> _fetchDetails() async {
    if (_details.isNotEmpty) {
      return; // Already loaded (from cache or previous fetch)
    }

    setState(() => _isLoadingDetails = true);

    try {
      // 1. Check cache again just in case
      final cached = await DataCacheService().getCachedVisitedDetails(
        widget.doc.$id,
      );
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _details = List<Map<String, dynamic>>.from(cached);
          _isLoadingDetails = false;
        });
        return;
      }

      // 2. Fetch
      final List<Map<String, dynamic>> gradesData = [];
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: visitedReportsDetailsCollectionId,
        queries: [Query.equal('reportId', widget.doc.$id), Query.limit(10)],
      );

      for (var doc in result.documents) {
        final data = doc.data;
        final visitedList = (data["visited"] as List? ?? [])
            .map((k) => (k is String) ? jsonDecode(k) : k)
            .toList()
            .cast<Map<String, dynamic>>();

        final unvisitedList = (data["unvisited"] as List? ?? [])
            .map((k) => (k is String) ? jsonDecode(k) : k)
            .toList()
            .cast<Map<String, dynamic>>();

        gradesData.add({
          "grade": doc.data['grade'],
          "total": data["total"] ?? 0,
          "visitedCount": data["visitedCount"] ?? 0,
          "percentage": (data["percentage"] ?? 0.0).toDouble(),
          "visitedList": visitedList,
          "unvisitedList": unvisitedList,
        });
      }

      // Sort
      final Map<String, int> gradeOrder = {
        "سنة أولى": 1,
        "سنة تانية": 2,
        "سنة تالتة": 3,
      };
      gradesData.sort((a, b) {
        final orderA = gradeOrder[a["grade"]] ?? 99;
        final orderB = gradeOrder[b["grade"]] ?? 99;
        return orderA.compareTo(orderB);
      });

      // Update Cache
      await DataCacheService().cacheVisitedDetails(widget.doc.$id, gradesData);

      if (mounted) {
        setState(() {
          _details = gradesData;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      debugPrint("Error details: $e");
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  void _showDetails(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> list,
    bool isVisitedList,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final kid = list[index];
                    final name = kid["name"] ?? "اسم غير معروف";
                    final address = kid["address"] ?? "عنوان غير معروف";
                    final phones = List<String>.from(kid["phones"] ?? []);
                    final String visitedBy = kid["visitedBy"] ?? "غير محدد";

                    final String statusText = isVisitedList
                        ? "✅ تم الافتقاد بواسطة: $visitedBy"
                        : "❌ لم يتم الافتقاد";

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          isVisitedList ? Icons.check_circle : Icons.cancel,
                          color: isVisitedList ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusText,
                              style: TextStyle(
                                color: isVisitedList
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              "📍 $address",
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (phones.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "📞 ${phones.join(', ')}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 💡 الدالة الجديدة لبناء مؤشر النسبة الإجمالي
  Widget _buildOverallStats(int visited, int total, String percentageText) {
    final double percentageValue = total == 0 ? 0.0 : (visited / total);
    final Color progressColor = percentageValue >= 1.0
        ? Colors.green.shade700
        : Colors.blue.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "🔥 الإجمالي الكلي للافتقاد: $visited من $total",
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 30, // ارتفاع شريط التقدم
                child: LinearProgressIndicator(
                  value: percentageValue, // القيمة بين 0.0 و 1.0
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 30,
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Text(
                  "$percentageText%", // عرض النسبة المئوية
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data;
    final weekName = data["reportName"] ?? widget.doc.$id;
    final totalOverall = data["totalOverall"] ?? 0;
    final visitedOverall = data["visitedOverall"] ?? 0;
    final percentageOverall =
        (data["overallPercentage"] as num?)?.toDouble().toStringAsFixed(1) ??
        "0.0";

    return GestureDetector(
      onLongPress: widget.isAdmin ? widget.onDelete : null,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: Colors.white,
        child: ExpansionTile(
          collapsedBackgroundColor: Colors.blue.shade50,
          backgroundColor: Colors.blue.shade100,
          title: Text(
            "📅 $weekName",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
            onPressed: () => _printVisitReport(widget.doc),
          ),
          onExpansionChanged: (expanded) {
            if (expanded && _details.isEmpty) {
              _fetchDetails();
            }
          },
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: _buildOverallStats(
                visitedOverall,
                totalOverall,
                percentageOverall,
              ),
            ),
            const Divider(thickness: 2),
            if (_isLoadingDetails)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_details.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("لا توجد تفاصيل متاحة"),
              )
            else
              ..._details.map((gradeData) {
                final grade = gradeData["grade"] as String;
                final int totalInGrade = gradeData["total"];
                final int visitedCount = gradeData["visitedCount"];
                final double percentage = (gradeData["percentage"] as num)
                    .toDouble();
                final List<Map<String, dynamic>> visitedList =
                    List<Map<String, dynamic>>.from(gradeData["visitedList"]);
                final List<Map<String, dynamic>> unvisitedList =
                    List<Map<String, dynamic>>.from(gradeData["unvisitedList"]);
                final unvisitedCount = totalInGrade - visitedCount;

                return ExpansionTile(
                  title: Text(
                    "🔹 $grade - افتقاد: $visitedCount من $totalInGrade (${percentage.toStringAsFixed(1)}%)",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  children: [
                    ListTile(
                      title: Text(
                        "✅ تم افتقاده ($visitedCount) - اضغط للتفاصيل",
                      ),
                      tileColor: Colors.green.shade100,
                      onTap: () => _showDetails(
                        context,
                        "تم افتقاد - $grade",
                        visitedList,
                        true,
                      ),
                    ),
                    ListTile(
                      title: Text(
                        "❌ لم يتم افتقاد ($unvisitedCount) - اضغط للتفاصيل",
                      ),
                      tileColor: Colors.red.shade100,
                      onTap: () => _showDetails(
                        context,
                        "لم يتم افتقاد - $grade",
                        unvisitedList,
                        false,
                      ),
                    ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _printVisitReport(models.Document reportDoc) async {
    try {
      final pdf = pw.Document();
      final fontData = await rootBundle.load("assets/fonts/Alfares.ttf");
      final ttf = pw.Font.ttf(fontData);

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
                tableData.add([u['name'] ?? "", "❌ لم يتم افتقاد", ""]);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ حدث خطأ أثناء الطباعة: $e")));
      }
    }
  }
}
