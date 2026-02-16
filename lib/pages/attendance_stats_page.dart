import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import '../services/appwrite_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import '../services/grade_service.dart';
import '../services/permission_service.dart';
import '../services/data_cache_service.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

class AttendanceStatsPage extends StatefulWidget {
  const AttendanceStatsPage({super.key});

  @override
  State<AttendanceStatsPage> createState() => _AttendanceStatsPageState();
}

class _AttendanceStatsPageState extends State<AttendanceStatsPage> {
  String? selectedType; // "خدام" أو "مخدومين"
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Client _client = AppwriteService().client;
  late Realtime _realtime;
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String attendanceRecordsCollectionId = 'attendance_records';

  // 🔍 متغيرات الفلترة
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  // -------------------------------------------------------------------------
  // ## دوال الفرز والترتيب
  // -------------------------------------------------------------------------

  List<String> _gradeOrder = [];
  String _myGroupId = '';
  bool _isAdmin = false;
  bool _canWrite = true;

  // 🚀 State for Reports List
  List<models.Document> _reports = [];
  bool _isLoadingReports = false;
  bool _isFetchingMore = false;
  bool _hasNextPage = true;
  final int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _realtime = Realtime(_client);
    _loadUserData();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasNextPage &&
        !_isLoadingReports) {
      if (selectedType != null) {
        _fetchReports(selectedType!, isLoadMore: true);
      }
    }
  }

  @override
  void dispose() {
    _userSubscription?.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();
      final userId = user.$id;

      // 1. Check Cache
      final cachedCtx = await DataCacheService().getCachedUserGroupId(userId);
      if (cachedCtx != null) {
        _applyUserData(cachedCtx['groupId']!, cachedCtx['role'] == 'admin');
      }

      // 2. Fetch Fresh
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );

      _updateState(doc.data);
      // Update cache
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
      _userSubscription!.stream.listen((event) => _updateState(event.payload));
    } catch (e) {
      debugPrint("Error loading user data: $e. Trying global cache.");
      // 🚀 Fallback: Try to get last known group context if account.get fails (offline)
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        _applyUserData(lastData['groupId'], lastData['role'] == 'admin');
      }
    }
  }

  void _applyUserData(String groupId, bool isAdmin) {
    if (mounted) {
      setState(() {
        _myGroupId = groupId;
        _isAdmin = isAdmin;
      });
      if (_myGroupId.isNotEmpty) {
        _fetchGradeOrder();
        PermissionService.canWrite(_myGroupId).then((val) {
          if (mounted) setState(() => _canWrite = val);
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
        _fetchGradeOrder();
        PermissionService.canWrite(_myGroupId).then((val) {
          if (mounted) setState(() => _canWrite = val);
        });
      }
    }
  }

  Future<void> _fetchGradeOrder() async {
    // 1. Check Cache
    try {
      final cachedGrades = await DataCacheService().getCachedGrades(_myGroupId);
      if (cachedGrades.isNotEmpty) {
        if (mounted) setState(() => _gradeOrder = cachedGrades);
      }
    } catch (_) {}

    // 2. Refresh
    try {
      final grades = await GradeService(groupId: _myGroupId).getGrades();
      await DataCacheService().cacheGrades(_myGroupId, grades);
      if (mounted) {
        setState(() {
          _gradeOrder = grades; // تأتي مرتبة من السيرفس
        });
      }
    } catch (e) {
      // ignore
    }
  }

  List<MapEntry<String, dynamic>> _sortGradesData(
    Map<String, dynamic> gradesMap,
  ) {
    // If no specific order, sort alphabetically
    if (_gradeOrder.isEmpty) {
      final list = gradesMap.entries.toList();
      list.sort((a, b) => a.key.compareTo(b.key));
      return list;
    }

    final List<MapEntry<String, dynamic>> sortedEntries = gradesMap.entries
        .toList();
    sortedEntries.sort((a, b) {
      final indexA = _gradeOrder.indexOf(a.key);
      final indexB = _gradeOrder.indexOf(b.key);
      // If not found in order list, put at end
      final safeIndexA = indexA == -1 ? 999 : indexA;
      final safeIndexB = indexB == -1 ? 999 : indexB;
      return safeIndexA.compareTo(safeIndexB);
    });

    return sortedEntries;
  }

  // -------------------------------------------------------------------------
  // ## دوال جلب البيانات
  // -------------------------------------------------------------------------

  // 🚀 Modified to fetch and set state with pagination support
  Future<void> _fetchReports(String type, {bool isLoadMore = false}) async {
    if (isLoadMore) {
      if (!_hasNextPage) return;
      setState(() => _isFetchingMore = true);
    } else {
      setState(() {
        selectedType = type;
        _isLoadingReports = true;
        _reports = [];
        _hasNextPage = true;
      });

      // 1. Check Cache (Only for the first page)
      final cached = await DataCacheService().getCachedAttendanceReports(
        _myGroupId,
        type,
      );
      if (cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            _reports = cached.map((d) => models.Document.fromMap(d)).toList();
            _isLoadingReports = false; // Show cached immediately
          });
        }
      }
    }

    try {
      final List<String> queries = [
        Query.equal('groupId', _myGroupId),
        Query.equal('type', type),
        Query.orderDesc('timestamp'),
        Query.limit(_pageSize),
      ];

      if (isLoadMore && _reports.isNotEmpty) {
        queries.add(Query.cursorAfter(_reports.last.$id));
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceRecordsCollectionId,
        queries: queries,
      );

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _reports.addAll(result.documents);
            _isFetchingMore = false;
          } else {
            _reports = result.documents;
            _isLoadingReports = false;

            // Update Cache for the first page
            final dataToCache = result.documents.map((d) => d.toMap()).toList();
            DataCacheService().cacheAttendanceReports(
              _myGroupId,
              type,
              dataToCache,
            );
          }
          _hasNextPage = result.documents.length == _pageSize;
        });
      }
    } catch (e) {
      // debugPrint("Error fetching reports: $e");
      if (mounted) {
        setState(() {
          _isLoadingReports = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  // Helper to parse data from the document itself
  Map<String, dynamic> parseGradesData(dynamic dataField) {
    if (dataField == null) return {};
    try {
      final Map<String, dynamic> rawMap = (dataField is String)
          ? jsonDecode(dataField)
          : dataField;

      final Map<String, dynamic> processedMap = {};

      rawMap.forEach((grade, listDynamic) {
        final List<dynamic> list = listDynamic as List<dynamic>;
        final int total = list.length;
        final int presentCount = list
            .where((x) => x['isPresent'] == true)
            .length;
        final double percentage = total == 0 ? 0 : (presentCount / total) * 100;

        processedMap[grade] = {
          "total": total,
          "presentCount": presentCount,
          "percentage": percentage,
          "list": list,
        };
      });

      return processedMap;
    } catch (e) {
      debugPrint("Error parsing grades data: $e");
      return {};
    }
  }

  List<models.Document> _filterReports(List<models.Document> reports) {
    return reports.where((doc) {
      final data = doc.data;
      final timestampStr = data["timestamp"] as String?;
      final timestamp = timestampStr != null
          ? DateTime.parse(timestampStr)
          : null;
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

  void _clearFilters() {
    setState(() {
      _selectedStartDate = null;
      _selectedEndDate = null;
    });
  }

  // -------------------------------------------------------------------------
  // ## UI Builders
  // -------------------------------------------------------------------------

  Widget _buildOverallStats(int present, int total, String percentageText) {
    final double percentageValue = total == 0 ? 0.0 : (present / total);
    final Color progressColor = percentageValue >= 1.0
        ? Colors.green.shade700
        : Colors.blue.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "🔥 الإجمالي الكلي للحضور: $present من $total",
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
                height: 30,
                child: LinearProgressIndicator(
                  value: percentageValue,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 30,
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Text(
                  "$percentageText%",
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

  void _showAttendanceDetails(
    BuildContext context,
    String title,
    List<dynamic> list,
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
                    final item = list[index];
                    final bool isPresent = item["isPresent"] == true;
                    final note = item["note"] ?? "";
                    String statusText;
                    Color statusColor;
                    IconData statusIcon;

                    if (isPresent) {
                      final marker = item["markedBy"] ?? "غير معروف";
                      statusText = "✅ حضر بواسطة: $marker";
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                    } else {
                      statusText = note.isNotEmpty
                          ? "📝 غاب (بملاحظة)"
                          : "❌ غاب (بدون ملاحظة)";
                      statusColor = note.isNotEmpty
                          ? Colors.orange.shade800
                          : Colors.red.shade800;
                      statusIcon = note.isNotEmpty
                          ? Icons.warning
                          : Icons.cancel;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(statusIcon, color: statusColor),
                        title: Text(
                          item["name"] ?? "اسم غير معروف",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (note.toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "📝 $note",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: selectedType == null,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (selectedType != null) {
          setState(() {
            selectedType = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("📋 سجل الحضور الموحد"),
          leading: selectedType != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => selectedType = null),
                )
              : null,
        ),
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
            child: selectedType == null
                ? _buildTypeSelection()
                : _buildReportsList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelection() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "اختر نوع الحضور",
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: () => _fetchReports("خدام"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
              ),
              child: const Text("خدام", style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: () => _fetchReports("مخدومين"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
              ),
              child: const Text("مخدومين", style: TextStyle(fontSize: 18)),
            ),
          ),
          // Add AI Insights Button maybe? Not requested but AIInsightService is related.
        ],
      ),
    );
  }

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

  Widget _buildReportsList() {
    if (_isLoadingReports && _reports.isEmpty) {
      // Show spinner only if no cached data
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Text(
          "⚠️ لا توجد تقارير حضور موحدة لـ ${selectedType!}.",
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    final filteredReports = _filterReports(_reports);

    return Column(
      children: [
        _buildFilterSection(),
        if (filteredReports.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                "⚠️ لا توجد نتائج تطابق الفلترة",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          )
        else
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
                final doc = filteredReports[index];
                final data = doc.data;
                final reportId = doc.$id;
                final reportName = data["reportName"] ?? doc.$id;
                final totalOverall = data["totalOverall"] ?? 0;
                final presentOverall = data["presentOverall"] ?? 0;
                final percentageOverall =
                    ((data["overallPercentage"] as num?)?.toDouble())
                        ?.toStringAsFixed(1) ??
                    "0.0";

                return GestureDetector(
                  onLongPress: _isAdmin
                      ? () => _confirmDeleteReport(reportId, reportName)
                      : null,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.white,
                    child: ExpansionTile(
                      collapsedBackgroundColor: Colors.blue.shade50,
                      backgroundColor: Colors.blue.shade100,
                      title: Text(
                        "📅 $reportName",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.picture_as_pdf,
                          color: _canWrite ? Colors.blueAccent : Colors.grey,
                        ),
                        onPressed: () {
                          if (_canWrite) {
                            _printAttendanceReport(doc);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "⚠️ ميزة الطباعة متاحة للمشتركين فقط",
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          child: _buildOverallStats(
                            presentOverall,
                            totalOverall,
                            percentageOverall,
                          ),
                        ),
                        // Truly lazy builder
                        StatefulBuilder(
                          builder: (context, setStateTile) {
                            return ExpansionTile(
                              title: const Text("توزيع الحضور حسب الفصل"),
                              children: [
                                Builder(
                                  builder: (context) {
                                    final Map<String, dynamic> gradesMap =
                                        parseGradesData(data['data']);
                                    if (gradesMap.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child: Text("لا توجد بيانات تفصيلية"),
                                        ),
                                      );
                                    }
                                    final sortedGradesEntries = _sortGradesData(
                                      gradesMap,
                                    );
                                    return Column(
                                      children: sortedGradesEntries.map((
                                        entry,
                                      ) {
                                        final grade = entry.key;
                                        final gradeStats =
                                            entry.value as Map<String, dynamic>;
                                        // ... existing details UI ...
                                        final int totalInGrade =
                                            gradeStats["total"] ?? 0;
                                        final int presentCount =
                                            gradeStats["presentCount"] ?? 0;
                                        final list =
                                            gradeStats["list"] as List<dynamic>;
                                        final allPresent = list
                                            .where(
                                              (it) => it["isPresent"] == true,
                                            )
                                            .toList();
                                        final allAbsent = list
                                            .where(
                                              (it) => it["isPresent"] == false,
                                            )
                                            .toList();
                                        final percentage =
                                            gradeStats["percentage"]
                                                ?.toStringAsFixed(1) ??
                                            "0.0";

                                        return ExpansionTile(
                                          title: Text(
                                            "🔹 $grade - حضور: $presentCount من $totalInGrade ($percentage%)",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          children: [
                                            ListTile(
                                              title: Text(
                                                "✅ الحاضرين (${allPresent.length})",
                                              ),
                                              tileColor: Colors.green.shade50,
                                              onTap: () =>
                                                  _showAttendanceDetails(
                                                    context,
                                                    "قائمة الحاضرين - $grade",
                                                    allPresent,
                                                  ),
                                            ),
                                            ListTile(
                                              title: Text(
                                                "❌ الغائبين (${allAbsent.length})",
                                              ),
                                              tileColor: Colors.red.shade50,
                                              onTap: () =>
                                                  _showAttendanceDetails(
                                                    context,
                                                    "قائمة الغائبين - $grade",
                                                    allAbsent,
                                                  ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
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
          "هل أنت متأكد من حذف تقرير '$reportName'؟ لا يمكن التراجع عن هذا الإجراء.",
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
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: attendanceRecordsCollectionId,
          documentId: reportId,
        );
        if (mounted) {
          _fetchReports(selectedType!); // Refresh list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ تم حذف التقرير بنجاح")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("❌ حدث خطأ أثناء الحذف: $e")));
        }
      }
    }
  }

  Future<void> _printAttendanceReport(models.Document reportDoc) async {
    if (!_canWrite) return;
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ حدث خطأ أثناء الطباعة: $e")));
      }
    }
  }
}
