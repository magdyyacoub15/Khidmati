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
import '../l10n/app_translations.dart';

class AttendanceStatsPage extends StatefulWidget {
  const AttendanceStatsPage({super.key});

  @override
  State<AttendanceStatsPage> createState() => _AttendanceStatsPageState();
}

class _AttendanceStatsPageState extends State<AttendanceStatsPage> {
  String? selectedType; // Localization is handled via tr()
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
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
  bool _isSyncing = false; // Flag to show background sync status
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
    _loadUserData();
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

  // 🚀 Offline-First Full Sync Logic
  Future<void> _fetchReports(String type) async {
    setState(() {
      selectedType = type;
      _isLoadingReports = true;
      _reports = [];
    });

    // 1. Instant Load From Cache (All available)
    final cached = await DataCacheService().getCachedAttendanceReports(
      _myGroupId,
      type,
    );
    if (cached.isNotEmpty) {
      if (mounted) {
        setState(() {
          _reports = cached.map((d) => models.Document.fromMap(d)).toList();
          _isLoadingReports = false; // Show instantly
        });
      }
    }

    // 2. Start Background Sync
    _syncReportsBackground(type);
  }

  Future<void> _syncReportsBackground(String type) async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final String legacyType = type == 'servants' ? 'خدام' : 'مخدومين';

      final List<models.Document> allDocuments = [];
      String? lastDocId;
      bool hasMore = true;
      final int batchSize = 100; // Large batches to reduce requests

      while (hasMore) {
        final List<String> queries = [
          Query.equal('groupId', _myGroupId),
          Query.equal('type', [
            type,
            legacyType,
          ]), // Allow both new English and old Arabic types
          Query.orderDesc('timestamp'),
          Query.limit(batchSize),
        ];

        if (lastDocId != null) {
          queries.add(Query.cursorAfter(lastDocId));
        }

        final result = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: attendanceRecordsCollectionId,
          queries: queries,
        );

        allDocuments.addAll(result.documents);

        if (result.documents.length < batchSize) {
          hasMore = false;
        } else {
          lastDocId = result.documents.last.$id;
        }
      }

      // Update Cache and UI
      if (mounted && selectedType == type) {
        // Convert to Map for caching
        final dataToCache = allDocuments.map((d) => d.toMap()).toList();
        await DataCacheService().cacheAttendanceReports(
          _myGroupId,
          type,
          dataToCache,
        );

        setState(() {
          _reports = allDocuments;
          _isLoadingReports = false;
        });
      }

      // 3. Initiate background sync for file contents
      _syncReportDetailsBackground(allDocuments);
    } catch (e) {
      debugPrint("Error syncing reports: $e");
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncReportDetailsBackground(
    List<models.Document> reports,
  ) async {
    for (var doc in reports) {
      final fileId = doc.data['fileId'] as String?;
      if (fileId != null && fileId.isNotEmpty) {
        // Check if we already have it
        final cached = await DataCacheService().getCachedReportContent(fileId);
        if (cached == null) {
          // Download and cache silently
          try {
            await _fetchFileContent(fileId);
            // Small delay to prevent network congestion
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (_) {
            // Ignore background errors
          }
        }
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

      for (final grade in rawMap.keys) {
        if (grade.startsWith('\$')) continue; // Skip Appwrite internal fields
        final dynamic listDynamic = rawMap[grade];

        List<dynamic> list = [];
        if (listDynamic is List) {
          list = listDynamic;
        } else if (listDynamic is String && listDynamic.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(listDynamic);
            if (decoded is List) list = decoded;
          } catch (_) {}
        }

        // Filter out non-map items (like Appwrite permission strings) to avoid UI crashes
        list = list.whereType<Map>().toList();

        final int total = list.length;
        int presentCount = 0;
        for (var item in list) {
          if ((item as Map)['isPresent'] == true) {
            presentCount++;
          }
        }
        final double percentage = total == 0 ? 0 : (presentCount / total) * 100;

        processedMap[grade] = {
          "total": total,
          "presentCount": presentCount,
          "percentage": percentage,
          "list": list,
        };
      }

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
                      final marker =
                          item["markedBy"] ?? 'unknown_person'.tr(context);
                      statusText = 'present_by'
                          .tr(context)
                          .replaceFirst('%s', marker.toString());
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                    } else {
                      statusText = note.isNotEmpty
                          ? 'absent_with_note'.tr(context)
                          : 'absent_without_note'.tr(context);
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
                          item["name"] ?? 'unknown_person'.tr(context),
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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
          title: Text('unified_attendance_log'.tr(context)),
          leading: selectedType != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => selectedType = null),
                )
              : null,
          actions: [
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
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
          Text(
            'select_attendance_type'.tr(context),
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: () => _fetchReports('servants'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
              ),
              child: Text(
                'servants_attendance'.tr(context),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: () => _fetchReports('attendees'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
              ),
              child: Text(
                'served_attendance'.tr(context),
                style: const TextStyle(fontSize: 18),
              ),
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
                                  ? 'from_date'.tr(context)
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
                                  ? 'to_date'.tr(context)
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
                  label: Text('clear_filters'.tr(context)),
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
          'no_attendance_reports'
              .tr(context)
              .replaceFirst(
                '%s',
                selectedType == 'servants'
                    ? 'servants_label'.tr(context)
                    : 'served_label'.tr(context),
              ),
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
          Expanded(
            child: Center(
              child: Text(
                'no_filter_results'.tr(context),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (selectedType != null) {
                  await _fetchReports(selectedType!);
                }
              },
              child: ListView.builder(
              controller: _scrollController,
              itemCount: filteredReports.length,
              itemBuilder: (context, index) {
                final doc = filteredReports[index];
                final data = doc.data;
                final reportId = doc.$id;

                // When loaded from SharedPreferences cache, Appwrite's fromMap might nest the data
                final dynamic rawDataField = data['data'];
                final Map<String, dynamic>? nestedData =
                    (rawDataField is Map<String, dynamic>)
                    ? rawDataField
                    : null;
                final String reportName =
                    data["reportName"] ?? nestedData?["reportName"] ?? doc.$id;

                return Dismissible(
                  key: Key(reportId),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) async {
                    if (!_isAdmin) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("⚠️ ليس لديك صلاحية الحذف"),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return false;
                    }
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          'delete_report_title'.tr(context),
                          textAlign: TextAlign.right,
                        ),
                        content: Text(
                          'delete_report_warning'
                              .tr(context)
                              .replaceFirst('%s', reportName),
                          textAlign: TextAlign.right,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text('cancel'.tr(context)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: Text('delete'.tr(context)),
                          ),
                        ],
                      ),
                    );
                    return confirmed == true;
                  },
                  onDismissed: (direction) async {
                    try {
                      await _databases.deleteDocument(
                        databaseId: databaseId,
                        collectionId: attendanceRecordsCollectionId,
                        documentId: reportId,
                      );
                      if (context.mounted) {
                        _fetchReports(selectedType!);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('delete_success'.tr(context))),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'delete_error'
                                  .tr(context)
                                  .replaceFirst('%s', e.toString()),
                            ),
                          ),
                        );
                        _fetchReports(selectedType!); // Refresh on error
                      }
                    }
                  },
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
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
                      onExpansionChanged: (expanded) {
                        if (expanded && _canWrite) {
                          // Pre-check if context is still valid if needed,
                          // though ExpansionTile handles its own state.
                        }
                      },
                      trailing: IconButton(
                        icon: Icon(
                          Icons.picture_as_pdf,
                          color: _canWrite ? Colors.blueAccent : Colors.grey,
                        ),
                        onPressed: () {
                          if (!mounted) return;
                          if (_canWrite) {
                            _printAttendanceReport(context, doc);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'print_subscribers_only'.tr(context),
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                      ),
                      children: [
                        // Side-by-side view
                        FutureBuilder<Map<String, dynamic>>(
                          future: _getGradesData(doc),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text(
                                    'error_loading_data'
                                        .tr(context)
                                        .replaceFirst(
                                          '%s',
                                          snapshot.error.toString(),
                                        ),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              );
                            }

                            final gradesMap = snapshot.data ?? {};
                            if (gradesMap.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text('no_detailed_data'.tr(context)),
                                ),
                              );
                            }

                            // 1. Sort Entries
                            final sortedEntries = _sortGradesData(gradesMap);

                            // 2. Group Data (Makhdomen vs Custom Pages)
                            final String defaultGroupLabel =
                                (selectedType == 'servants')
                                ? 'servants_attendance'.tr(context)
                                : 'served_attendance'.tr(context);

                            final Map<String, List<MapEntry<String, dynamic>>>
                            groupedData = {};
                            final List<String> groupOrder = [defaultGroupLabel];

                            for (var entry in sortedEntries) {
                              final key = entry.key;
                              String groupName = defaultGroupLabel;
                              String displayName = key;

                              if (key.contains(" - ")) {
                                final parts = key.split(" - ");
                                if (parts.length > 1) {
                                  displayName = parts[0];
                                  groupName = parts.sublist(1).join(" - ");
                                }
                              }

                              if (!groupedData.containsKey(groupName)) {
                                groupedData[groupName] = [];
                                if (!groupOrder.contains(groupName)) {
                                  groupOrder.add(groupName);
                                }
                              }
                              groupedData[groupName]!.add(
                                MapEntry(displayName, entry.value),
                              );
                            }

                            // 3. Tab-based UI
                            String selectedGroup = groupOrder.first;

                            return StatefulBuilder(
                              builder: (context, setTabState) {
                                final entries = groupedData[selectedGroup]!;

                                // Calculate Group Stats
                                int present = 0;
                                int total = 0;
                                for (var e in entries) {
                                  final gradeStats =
                                      e.value as Map<String, dynamic>;
                                  total += (gradeStats['total'] as int);
                                  present +=
                                      (gradeStats['presentCount'] as int);
                                }
                                double percent = total == 0
                                    ? 0.0
                                    : (present / total);

                                return Column(
                                  children: [
                                    // A. Tabs Row
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: groupOrder.map((group) {
                                          final isSelected =
                                              group == selectedGroup;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: ChoiceChip(
                                              label: Text(
                                                group,
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              ),
                                              selected: isSelected,
                                              selectedColor: Colors.blue,
                                              backgroundColor:
                                                  Colors.grey.shade200,
                                              onSelected: (bool selected) {
                                                if (selected) {
                                                  setTabState(() {
                                                    selectedGroup = group;
                                                  });
                                                }
                                              },
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),

                                    // B. Content for Selected Group (No Box around Header)
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        children: [
                                          // 1. Header (Pie Chart) - Compact & Clean
                                          const SizedBox(height: 10),
                                          Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SizedBox(
                                                width: 90,
                                                height: 90,
                                                child: CircularProgressIndicator(
                                                  value: percent,
                                                  backgroundColor:
                                                      Colors.grey.shade200,
                                                  color: percent >= 1
                                                      ? Colors.green
                                                      : Colors.blue,
                                                  strokeWidth: 9,
                                                  strokeCap: StrokeCap
                                                      .round, // Rounded ends for better look
                                                ),
                                              ),
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    "${(percent * 100).toStringAsFixed(1)}%",
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            "$present / $total",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          const Divider(),

                                          // 2. Detailed List
                                          ListView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: entries.length,
                                            itemBuilder: (context, index) {
                                              final entry = entries[index];
                                              final grade = entry.key;
                                              final gradeStats =
                                                  entry.value
                                                      as Map<String, dynamic>;
                                              final int totalInGrade =
                                                  gradeStats["total"] ?? 0;
                                              final int presentCount =
                                                  gradeStats["presentCount"] ??
                                                  0;
                                              final list =
                                                  gradeStats["list"]
                                                      as List<dynamic>;
                                              final allPresent = list
                                                  .where(
                                                    (it) =>
                                                        it is Map &&
                                                        it["isPresent"] == true,
                                                  )
                                                  .toList();
                                              final allAbsent = list
                                                  .where(
                                                    (it) =>
                                                        it is Map &&
                                                        it["isPresent"] ==
                                                            false,
                                                  )
                                                  .toList();
                                              final percentage =
                                                  gradeStats["percentage"]
                                                      ?.toStringAsFixed(1) ??
                                                  "0.0";

                                              return Card(
                                                margin: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                elevation: 0,
                                                color: Colors.blue.shade50
                                                    .withValues(alpha: 0.5),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  side: BorderSide(
                                                    color: Colors.blue.shade100,
                                                  ),
                                                ),
                                                child: ExpansionTile(
                                                  title: Text(
                                                    grade,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    "$presentCount / $totalInGrade ($percentage%)",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.grey.shade800,
                                                    ),
                                                  ),
                                                  children: [
                                                    ListTile(
                                                      dense: true,
                                                      title: Text(
                                                        'present_count'
                                                            .tr(context)
                                                            .replaceFirst(
                                                              '%s',
                                                              allPresent.length
                                                                  .toString(),
                                                            ),
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      tileColor:
                                                          Colors.green.shade50,
                                                      onTap: () =>
                                                          _showAttendanceDetails(
                                                            context,
                                                            'present_list_title'
                                                                .tr(context)
                                                                .replaceFirst(
                                                                  '%s',
                                                                  selectedGroup,
                                                                )
                                                                .replaceFirst(
                                                                  '%s',
                                                                  grade,
                                                                ),
                                                            allPresent,
                                                          ),
                                                    ),
                                                    ListTile(
                                                      dense: true,
                                                      title: Text(
                                                        'absent_count'
                                                            .tr(context)
                                                            .replaceFirst(
                                                              '%s',
                                                              allAbsent.length
                                                                  .toString(),
                                                            ),
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      tileColor:
                                                          Colors.red.shade50,
                                                      onTap: () =>
                                                          _showAttendanceDetails(
                                                            context,
                                                            'absent_list_title'
                                                                .tr(context)
                                                                .replaceFirst(
                                                                  '%s',
                                                                  selectedGroup,
                                                                )
                                                                .replaceFirst(
                                                                  '%s',
                                                                  grade,
                                                                ),
                                                            allAbsent,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
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
          ),
      ],
    );
  }

  // 🚀 Helper to fix Appwrite SDK nesting quirk when loading from SharedPrefs
  Map<String, dynamic> _getActualData(models.Document doc) {
    final rawDataField = doc.data['data'];
    if (rawDataField is Map<String, dynamic>) {
      // The document was loaded from cache and nested
      return rawDataField;
    }
    return doc.data;
  }

  Future<Map<String, dynamic>> _getGradesData(models.Document reportDoc) async {
    final actualData = _getActualData(reportDoc);

    // 1. Try fileId First (New System)
    final fileId = actualData['fileId'] as String?;
    if (fileId != null && fileId.isNotEmpty) {
      // 🚀 Check Cache First (Crucial for Offline PDF)
      final cached = await DataCacheService().getCachedReportContent(fileId);
      if (cached != null && cached.isNotEmpty) {
        return parseGradesData(cached);
      }

      // Try fetching if not cached
      final rawData = await _fetchFileContent(fileId);
      if (rawData.isNotEmpty) {
        return parseGradesData(rawData);
      }
    }

    // 2. Fallback to data field (Legacy System or Failed Download)
    final dynamic gradesPayload = actualData['data'];
    if (gradesPayload != null) {
      if (gradesPayload is String && gradesPayload.trim().isEmpty) {
        return {}; // Prevent parsing empty strings
      }
      return parseGradesData(gradesPayload);
    }

    return {};
  }

  Future<Map<String, dynamic>> _fetchFileContent(String fileId) async {
    try {
      final byteList = await AppwriteService().storage.getFileDownload(
        bucketId: AppwriteService.attendanceBucketId,
        fileId: fileId,
      );
      final jsonString = utf8.decode(byteList);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      // 🚀 Save to Cache
      await DataCacheService().cacheReportContent(fileId, decoded);

      return decoded;
    } catch (e) {
      debugPrint("Error fetching report file: $e");
      return {};
    }
  }

  Future<void> _printAttendanceReport(
    BuildContext flutterContext,
    models.Document reportDoc,
  ) async {
    if (!_canWrite) return;
    try {
      final pdf = pw.Document();

      // Load a highly stable font for Arabic (Local Offline Font)
      pw.Font ttf;
      try {
        final fontData = await rootBundle.load("assets/fonts/Alfares.ttf");
        ttf = pw.Font.ttf(fontData);
      } catch (e) {
        debugPrint(
          "Critical Error: Local font Alfares.ttf could not be loaded: $e",
        );
        rethrow;
      }

      // Skip Emoji font completely to ensure offline stability

      // 1. Get Processed Data
      final Map<String, dynamic> processedMap = await _getGradesData(reportDoc);

      if (!flutterContext.mounted) return;

      if (processedMap.isEmpty) {
        throw 'report_data_unavailable'.tr(flutterContext);
      }

      final reportName =
          reportDoc.data['reportName'] ??
          'attendance_report_default'.tr(flutterContext);

      // 1. Get Sorted Entries
      final sortedEntries = _sortGradesData(processedMap);

      // 2. Calculate Grand Totals (Needed for Summary Table)
      int grandTotal = 0;
      int grandPresent = 0;
      for (var entry in sortedEntries) {
        final stats = entry.value as Map<String, dynamic>;
        grandTotal += (stats['total'] as int? ?? 0);
        grandPresent += (stats['presentCount'] as int? ?? 0);
      }
      double grandPercent = grandTotal == 0 ? 0.0 : (grandPresent / grandTotal);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: pw.ThemeData.withFont(
            base: ttf,
            fontFallback: [], // No emoji fallback needed
          ),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            // 1. Group Data by Grade and Category
            final Map<String, Map<String, dynamic>> gradesDataMap = {};
            final String primaryCategory = (selectedType == 'servants')
                ? 'servants_label'.tr(flutterContext)
                : 'served_label'.tr(flutterContext);

            for (var entry in sortedEntries) {
              final rawKey = entry.key;
              String currentGrade = rawKey;
              String currentCategory = primaryCategory;

              if (rawKey.contains(" - ")) {
                final parts = rawKey.split(" - ");
                if (parts.length > 1) {
                  currentGrade = parts[0];
                  currentCategory = parts.sublist(1).join(" - ");
                }
              }

              if (!gradesDataMap.containsKey(currentGrade)) {
                gradesDataMap[currentGrade] = {};
              }

              final stats = entry.value as Map<String, dynamic>;
              final List<dynamic> list = stats['list'] is List
                  ? stats['list']
                  : [];

              for (var itemDynamic in list) {
                if (itemDynamic is! Map) continue;
                final item = itemDynamic;
                final name =
                    item['name'] as String? ??
                    'unknown_person'.tr(flutterContext);

                if (!gradesDataMap[currentGrade]!.containsKey(name)) {
                  gradesDataMap[currentGrade]![name] = <String, dynamic>{
                    'notes': <dynamic>[],
                  };
                }

                gradesDataMap[currentGrade]![name]![currentCategory] =
                    item['isPresent'];

                if (item['note'] != null &&
                    item['note'].toString().isNotEmpty) {
                  gradesDataMap[currentGrade]![name]!['notes'].add(
                    item['note'],
                  );
                }
              }
            }

            // Provide check/x symbols by drawing them instead of relying on fonts
            pw.Widget getStatusSymbol(bool? isPresent) {
              if (isPresent == null) {
                return pw.Text("-", style: pw.TextStyle(font: ttf));
              }

              if (isPresent) {
                return pw.SizedBox(
                  width: 12,
                  height: 12,
                  child: pw.CustomPaint(
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      canvas.setStrokeColor(PdfColors.blue);
                      canvas.setLineWidth(2.0);
                      // PDF Canvas (0,0) is bottom-left.
                      canvas.moveTo(2, size.y - (size.y / 2));
                      canvas.lineTo(size.x / 2.5, size.y - (size.y - 2));
                      canvas.lineTo(size.x - 2, size.y - 2);
                      canvas.strokePath();
                    },
                  ),
                );
              } else {
                return pw.SizedBox(
                  width: 10,
                  height: 10,
                  child: pw.CustomPaint(
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      canvas.setStrokeColor(PdfColors.red);
                      canvas.setLineWidth(2.0);
                      canvas.moveTo(0, 0);
                      canvas.lineTo(size.x, size.y);
                      canvas.moveTo(size.x, 0);
                      canvas.lineTo(0, size.y);
                      canvas.strokePath();
                    },
                  ),
                );
              }
            }

            final List<pw.Widget> pdfContent = [];

            pdfContent.add(
              // --- Premium Header ---
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'attendance_stats_report'.tr(flutterContext),
                          style: pw.TextStyle(
                            fontSize: 22,
                            font: ttf,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.Text(
                          '${'target_group'.tr(flutterContext)}: $selectedType',
                          style: pw.TextStyle(
                            fontSize: 14,
                            font: ttf,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          DateFormat('yyyy/MM/dd').format(DateTime.now()),
                          style: pw.TextStyle(fontSize: 12, font: ttf),
                        ),
                        pw.Text(
                          'file_name'
                              .tr(flutterContext)
                              .replaceFirst('%s', reportName),
                          style: pw.TextStyle(
                            fontSize: 10,
                            font: ttf,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
            pdfContent.add(pw.SizedBox(height: 10));

            // --- Overall Summary Table ---
            pdfContent.add(
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue800,
                    ),
                    children: [
                      _buildHeaderCell('target_group'.tr(flutterContext), ttf),
                      _buildHeaderCell('total_count'.tr(flutterContext), ttf),
                      _buildHeaderCell(
                        'attendance_count'.tr(flutterContext),
                        ttf,
                      ),
                      _buildHeaderCell('percentage'.tr(flutterContext), ttf),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildDataCell(
                        selectedType ?? 'unknown_person'.tr(flutterContext),
                        ttf,
                        isBold: true,
                      ),
                      _buildDataCell("$grandTotal", ttf),
                      _buildDataCell("$grandPresent", ttf),
                      _buildDataCell(
                        "${(grandPercent * 100).toStringAsFixed(1)}%",
                        ttf,
                        isBold: true,
                      ),
                    ],
                  ),
                ],
              ),
            );

            pdfContent.add(pw.SizedBox(height: 20));

            // Move chart logic to the end
            final sortedGradeKeys = gradesDataMap.keys.toList();
            if (_gradeOrder.isNotEmpty) {
              sortedGradeKeys.sort((a, b) {
                final indexA = _gradeOrder.indexOf(a);
                final indexB = _gradeOrder.indexOf(b);
                final safeIndexA = indexA == -1 ? 999 : indexA;
                final safeIndexB = indexB == -1 ? 999 : indexB;
                return safeIndexA.compareTo(safeIndexB);
              });
            } else {
              sortedGradeKeys.sort();
            }

            for (String gradeName in sortedGradeKeys) {
              final studentMap = gradesDataMap[gradeName]!;
              final sortedStudentNames = studentMap.keys.toList()..sort();

              // Get categories specific to this grade (e.g., standard attendance + any custom page)
              final Set<String> gradeCategoriesFound = {};
              for (var sData in studentMap.values) {
                gradeCategoriesFound.addAll(
                  sData.keys.where((k) => k != 'notes'),
                );
              }
              final sortedCategories = gradeCategoriesFound.toList()..sort();
              if (sortedCategories.contains(primaryCategory)) {
                sortedCategories.remove(primaryCategory);
                sortedCategories.insert(0, primaryCategory);
              }

              final Map<int, pw.TableColumnWidth> colWidths = {
                0: const pw.FlexColumnWidth(3), // Name
              };
              for (int i = 0; i < sortedCategories.length; i++) {
                colWidths[1 + i] = const pw.FlexColumnWidth(
                  1,
                ); // Category columns
              }
              colWidths[1 + sortedCategories.length] = const pw.FlexColumnWidth(
                2,
              ); // Notes

              pdfContent.add(
                pw.Center(
                  child: pw.Text(
                    gradeName,
                    style: pw.TextStyle(
                      fontSize: 16,
                      font: ttf,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey800,
                    ),
                  ),
                ),
              );
              pdfContent.add(pw.SizedBox(height: 8));

              pdfContent.add(
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  columnWidths: colWidths,
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blue800,
                      ),
                      children: [
                        _buildHeaderCell('name'.tr(flutterContext), ttf),
                        ...sortedCategories.map(
                          (cat) => _buildHeaderCell(cat, ttf),
                        ),
                        _buildHeaderCell('notes'.tr(flutterContext), ttf),
                      ],
                    ),
                    // Data Rows
                    ...sortedStudentNames.isEmpty
                        ? [
                            pw.TableRow(
                              children: [
                                _buildDataCell(
                                  'no_data_available_print'.tr(flutterContext),
                                  ttf,
                                ),
                                ...sortedCategories.map(
                                  (_) => _buildDataCell("-", ttf),
                                ),
                                _buildDataCell("-", ttf),
                              ],
                            ),
                          ]
                        : sortedStudentNames.map((name) {
                            final data = studentMap[name]!;
                            final List<String> notes = List<String>.from(
                              data['notes'],
                            );

                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(
                                    vertical: 3,
                                    horizontal: 5,
                                  ),
                                  child: pw.Text(
                                    _cleanPdfText(name),
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(fontSize: 9, font: ttf),
                                  ),
                                ),
                                ...sortedCategories.map((cat) {
                                  final isPresent = data[cat];
                                  return pw.Padding(
                                    padding: const pw.EdgeInsets.symmetric(
                                      vertical: 3,
                                      horizontal: 5,
                                    ),
                                    child: pw.Center(
                                      child: getStatusSymbol(isPresent),
                                    ),
                                  );
                                }),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(
                                    vertical: 3,
                                    horizontal: 5,
                                  ),
                                  child: pw.Text(
                                    _cleanPdfText(notes.join(" | ")),
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(fontSize: 8, font: ttf),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                    // --- Total Row ---
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 5,
                          ),
                          child: pw.Text(
                            'total'.tr(flutterContext),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 10,
                              font: ttf,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ),
                        ...sortedCategories.map((cat) {
                          int totalPresent = 0;
                          for (var name in sortedStudentNames) {
                            if (studentMap[name]![cat] == true) {
                              totalPresent++;
                            }
                          }
                          return pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 5,
                            ),
                            child: pw.Text(
                              "$totalPresent / ${sortedStudentNames.length}",
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 10,
                                font: ttf,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue900,
                              ),
                            ),
                          );
                        }),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 5,
                          ),
                          child: pw.Text(
                            "",
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 10, font: ttf),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              pdfContent.add(pw.SizedBox(height: 15));
            }

            // Generate Multi-Colored Bar Chart at the end
            if (sortedGradeKeys.isNotEmpty) {
              double maxVal = 0;
              final List<String> gradeLabels = [];
              final List<double> percentages = [];

              for (int i = 0; i < sortedGradeKeys.length; i++) {
                final gradeName = sortedGradeKeys[i];
                final studentMap = gradesDataMap[gradeName]!;

                int gradeTotal = 0;
                int gradePresent = 0;

                // Rebuild sortedCategories to evaluate total presence for chart bars
                final Set<String> gradeCategoriesFound = {};
                for (var sData in studentMap.values) {
                  gradeCategoriesFound.addAll(
                    sData.keys.where((k) => k != 'notes'),
                  );
                }
                final sortedCategories = gradeCategoriesFound.toList()..sort();
                if (sortedCategories.contains(primaryCategory)) {
                  sortedCategories.remove(primaryCategory);
                  sortedCategories.insert(0, primaryCategory);
                }

                for (var sData in studentMap.values) {
                  for (var cat in sortedCategories) {
                    if (sData.containsKey(cat)) {
                      gradeTotal++;
                      if (sData[cat] == true) {
                        gradePresent++;
                      }
                    }
                  }
                }

                double pct = gradeTotal > 0
                    ? (gradePresent / gradeTotal) * 100
                    : 0;
                if (pct > maxVal) maxVal = pct;
                gradeLabels.add(gradeName);
                percentages.add(pct);
              }

              if (maxVal == 0) maxVal = 100;

              // Fix NaN exception in PDF rendering when there is only one grade
              if (gradeLabels.length == 1) {
                gradeLabels.add(" ");
                percentages.add(0.0);
              }

              // Predefined distinct colors for bars
              final List<PdfColor> barColors = [
                PdfColors.blue,
                PdfColors.orange,
                PdfColors.green,
                PdfColors.red,
                PdfColors.purple,
                PdfColors.teal,
                PdfColors.pink,
                PdfColors.cyan,
                PdfColors.indigo,
                PdfColors.amber,
              ];

              final List<pw.Dataset> datasets = [];
              for (int i = 0; i < percentages.length; i++) {
                // Keep the padded blank space dataset so the chart bounds evaluate correctly (x=0 to x=1).
                final isPadding =
                    gradeLabels[i] == " " && percentages[i] == 0.0;

                datasets.add(
                  pw.BarDataSet(
                    color: isPadding
                        ? PdfColors.white
                        : barColors[i % barColors.length],
                    width: 40,
                    data: [pw.PointChartValue(i.toDouble(), percentages[i])],
                  ),
                );
              }

              pdfContent.add(pw.SizedBox(height: 20));
              pdfContent.add(
                pw.Center(
                  child: pw.Container(
                    height: 200,
                    width: (gradeLabels.length * 80.0) + 100, // Tighter cluster
                    child: pw.Chart(
                      title: pw.Text(
                        'chart_attendance_comparison'.tr(flutterContext),
                        style: pw.TextStyle(
                          font: ttf,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      grid: pw.CartesianGrid(
                        xAxis: pw.FixedAxis.fromStrings(
                          List<String>.generate(
                            gradeLabels.length,
                            (index) => _cleanPdfText(gradeLabels[index]),
                          ),
                          marginStart: 20,
                          marginEnd: 20,
                          ticks: true,
                          textStyle: pw.TextStyle(font: ttf, fontSize: 8),
                        ),
                        yAxis: pw.FixedAxis(
                          [0, if (maxVal > 0) maxVal / 2, maxVal],
                          format: (v) => '${v.toInt()}%',
                          ticks: true,
                          textStyle: pw.TextStyle(font: ttf, fontSize: 8),
                        ),
                      ),
                      datasets: datasets,
                    ),
                  ),
                ),
              );
            }

            return pdfContent;
          },
        ),
      );

      if (!flutterContext.mounted) return;

      Navigator.push(
        flutterContext,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('attendance_report_default'.tr(context)),
              backgroundColor: Colors.blue.shade800,
            ),
            body: PdfPreview(
              build: (format) async => pdf.save(),
              pdfFileName: 'attendance_${reportDoc.$id}.pdf',
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } catch (e) {
      if (flutterContext.mounted) {
        ScaffoldMessenger.of(flutterContext).showSnackBar(
          SnackBar(
            content: Text(
              'print_error'.tr(flutterContext).replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  pw.Widget _buildHeaderCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          color: PdfColors.white,
          font: font,
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  pw.Widget _buildDataCell(String text, pw.Font font, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        _cleanPdfText(text),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontSize: 9,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  String _cleanPdfText(String? text) {
    if (text == null || text.isEmpty) return "-";
    // Robust cleaning logic to remove emojis and unsupported Unicode that crash TtfWriter
    // We allow Arabic characters, basic alphanumeric, and simple punctuation.
    try {
      final safeText = text.replaceAll(
        RegExp(
          r'[^\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFFa-zA-Z0-9\s\.\,\-\_\:\;\!\?\#\%\&\(\)\[\]\/\|]',
        ),
        '',
      );
      return safeText.trim().isEmpty ? "-" : safeText;
    } catch (_) {
      return "-";
    }
  }
}
