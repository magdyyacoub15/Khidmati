import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';

import '../services/data_cache_service.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/grade_service.dart';
import '../l10n/app_translations.dart';

class VisitedStatsPage extends StatefulWidget {
  const VisitedStatsPage({super.key});

  @override
  State<VisitedStatsPage> createState() => _VisitedStatsPageState();
}

class _VisitedStatsPageState extends State<VisitedStatsPage> {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
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
  bool _isSyncing = false; // Flag to show background sync status
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
    _fetchUserData();
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
      debugPrint("Error loading user data in VisitedStatsPage: $e");
      // 🚀 Fallback: Try to get last known group context if account.get fails (offline)
      try {
        final lastData = await DataCacheService().getCachedUserData();
        if (lastData != null && lastData.containsKey('groupId')) {
          if (mounted) {
            setState(() {
              _myGroupId = lastData['groupId'];
              _isAdmin = lastData['role'] == 'admin';
            });
            _fetchReports();
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      } catch (cacheError) {
        if (mounted) setState(() => _isLoading = false);
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

  // 🚀 Offline-First Full Sync Logic
  Future<void> _fetchReports() async {
    // 1. Instant Load From Cache (All available)
    final cached = await DataCacheService().getCachedVisitedReports(_myGroupId);
    if (cached.isNotEmpty) {
      if (mounted) {
        setState(() {
          _reports = cached.map((d) => models.Document.fromMap(d)).toList();
          _isLoading = false; // Show instantly
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = true);
    }

    // 2. Start Background Sync
    _syncReportsBackground();
  }

  Future<void> _syncReportsBackground() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final List<models.Document> allDocuments = [];
      String? lastDocId;
      bool hasMore = true;
      final int batchSize = 100;

      while (hasMore) {
        final List<String> queries = [
          Query.equal('groupId', _myGroupId),
          Query.orderDesc('timestamp'),
          Query.limit(batchSize),
        ];

        if (lastDocId != null) {
          queries.add(Query.cursorAfter(lastDocId));
        }

        final result = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: visitedReportsCollectionId,
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
      if (mounted) {
        final dataToCache = allDocuments.map((d) => d.toMap()).toList();
        await DataCacheService().cacheVisitedReports(_myGroupId, dataToCache);

        setState(() {
          _reports = allDocuments;
          _isLoading = false;
        });
      }

      // 3. Initiate background sync for report details (for offline functionality)
      _syncReportDetailsBackground(allDocuments);
    } catch (e) {
      debugPrint("Error syncing visitation reports: $e");
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncReportDetailsBackground(
    List<models.Document> reports,
  ) async {
    for (var doc in reports) {
      final cachedDetails = await DataCacheService().getCachedVisitedDetails(
        doc.$id,
      );

      // If we already have the details cached, skip
      if (cachedDetails != null && cachedDetails.isNotEmpty) {
        continue;
      }

      // Fetch and cache details silently
      try {
        final List<Map<String, dynamic>> gradesData = [];
        final fileId = doc.data['fileId'] as String?;

        if (fileId != null && fileId.isNotEmpty) {
          // File-based details (New System)
          final byteList = await AppwriteService().storage.getFileDownload(
            bucketId: AppwriteService.attendanceBucketId,
            fileId: fileId,
          );

          if (byteList.isNotEmpty) {
            final jsonString = utf8.decode(byteList);
            if (jsonString.trim().isNotEmpty) {
              final Map<String, dynamic> fullReportData = jsonDecode(
                jsonString,
              );
              fullReportData.forEach((grade, gradeData) {
                final stats = gradeData["stats"] ?? {};
                gradesData.add({
                  "grade": grade,
                  "total": stats["total"] ?? 0,
                  "visitedCount": stats["visitedCount"] ?? 0,
                  "percentage": (stats["percentage"] as num? ?? 0.0).toDouble(),
                  "visitedList": (gradeData["visited"] as List)
                      .map(
                        (k) => k is String
                            ? (jsonDecode(k) as Map? ?? {})
                            : (k as Map? ?? {}),
                      )
                      .toList(),
                  "unvisitedList": (gradeData["unvisited"] as List)
                      .map(
                        (k) => k is String
                            ? (jsonDecode(k) as Map? ?? {})
                            : (k as Map? ?? {}),
                      )
                      .toList(),
                });
              });
            }
          }
        } else {
          // Legacy details (Database)
          final result = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: visitedReportsDetailsCollectionId,
            queries: [Query.equal('reportId', doc.$id), Query.limit(10)],
          );

          for (var detailDoc in result.documents) {
            final data = detailDoc.data;
            gradesData.add({
              "grade": data['grade'],
              "total": data["total"] ?? 0,
              "visitedCount": data["visitedCount"] ?? 0,
              "percentage": (data["percentage"] ?? 0.0).toDouble(),
              "visitedList": (data["visited"] as List? ?? [])
                  .map(
                    (k) => k is String
                        ? (jsonDecode(k) as Map? ?? {})
                        : (k as Map? ?? {}),
                  )
                  .toList(),
              "unvisitedList": (data["unvisited"] as List? ?? [])
                  .map(
                    (k) => k is String
                        ? (jsonDecode(k) as Map? ?? {})
                        : (k as Map? ?? {}),
                  )
                  .toList(),
            });
          }
        }

        if (gradesData.isNotEmpty) {
          await DataCacheService().cacheVisitedDetails(doc.$id, gradesData);
        }

        // Yield temporarily to prevent network flooding and UI freeze
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint("Error syncing detail for ${doc.$id}: $e");
      }
    }
  }

  // Filter variables
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  List<models.Document> _filterReports(List<models.Document> reports) {
    return reports.where((doc) {
      final data = doc.data;
      final timestampStr = data["timestamp"] as String?;
      final timestamp = timestampStr != null
          ? DateTime.parse(timestampStr)
          : null;

      // Filter by date
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
    if (picked != null && mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('unified_visitation_log'.tr(context)),
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _myGroupId.isEmpty
              ? Center(
                  child: Text(
                    'no_group_id_error'.tr(context),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                )
              : _buildReportsList(),
        ),
      ),
    );
  }

  Widget _buildReportsList() {
    if (_reports.isEmpty) {
      return Center(
        child: Text(
          'no_unified_records'.tr(context),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }
    final filteredReports = _filterReports(_reports);

    if (filteredReports.isEmpty) {
      return Center(
        child: Text(
          'no_filter_results'.tr(context),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return Column(
      children: [
        _buildFilterSection(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchReports,
            child: ListView.builder(
            controller: _scrollController,
            itemCount: filteredReports.length,
            itemBuilder: (context, index) {
              return Dismissible(
                key: Key(filteredReports[index].$id),
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
                  final data = filteredReports[index].data;
                  final nestedData = data['data'] as Map<String, dynamic>?;
                  final reportName =
                      data["reportName"] ?? nestedData?["reportName"] ?? "";

                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'delete_report_title'.tr(context),
                        textAlign: TextAlign.right,
                      ),
                      content: Text(
                        'delete_report_message'
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
                    final reportId = filteredReports[index].$id;
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
                    if (context.mounted) {
                      _fetchReports(); // refresh list
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('report_deleted_success'.tr(context)),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'report_delete_failed'
                                .tr(context)
                                .replaceFirst('%s', e.toString()),
                          ),
                        ),
                      );
                      _fetchReports(); // refresh list on error
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
                child: VisitedReportCard(
                  doc: filteredReports[index],
                  isAdmin: _isAdmin,
                  onDelete: () {}, // Handled by dismissible now
                ),
              );
            },
          ),
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

      final List<Map<String, dynamic>> gradesData = [];

      // 2. Check for fileId (New System)
      final actualData = widget.doc.data['data'] is Map<String, dynamic>
          ? widget.doc.data['data']
          : widget.doc.data;
      final fileId = actualData['fileId'] as String?;

      if (fileId != null && fileId.isNotEmpty) {
        try {
          final byteList = await AppwriteService().storage.getFileDownload(
            bucketId: AppwriteService.attendanceBucketId,
            fileId: fileId,
          );

          if (byteList.isNotEmpty) {
            final jsonString = utf8.decode(byteList);
            if (jsonString.trim().isNotEmpty) {
              final Map<String, dynamic> fullReportData = jsonDecode(
                jsonString,
              );

              // Convert Map to List structure
              fullReportData.forEach((grade, gradeData) {
                final stats = gradeData["stats"] ?? {};

                final visitedList = (gradeData["visited"] as List)
                    .map((k) {
                      if (k is String) {
                        try {
                          return jsonDecode(k);
                        } catch (_) {
                          return {};
                        }
                      }
                      return k;
                    })
                    .toList()
                    .cast<Map<String, dynamic>>();

                final unvisitedList = (gradeData["unvisited"] as List)
                    .map((k) {
                      if (k is String) {
                        try {
                          return jsonDecode(k);
                        } catch (_) {
                          return {};
                        }
                      }
                      return k;
                    })
                    .toList()
                    .cast<Map<String, dynamic>>();

                gradesData.add({
                  "grade": grade,
                  "total": stats["total"] ?? 0,
                  "visitedCount": stats["visitedCount"] ?? 0,
                  "percentage": (stats["percentage"] as num? ?? 0.0).toDouble(),
                  "visitedList": visitedList,
                  "unvisitedList": unvisitedList,
                });
              });
            }
          }
        } catch (e) {
          debugPrint("Error fetching file details: $e");
          // Fallback or rethrow? Let's just log and maybe fallback if empty
        }
      }

      // 3. Fallback to Legacy System (if fileId missing or failed/empty)
      if (gradesData.isEmpty) {
        final result = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: visitedReportsDetailsCollectionId,
          queries: [Query.equal('reportId', widget.doc.$id), Query.limit(10)],
        );

        for (var doc in result.documents) {
          final data = doc.data;

          final visitedList = (data["visited"] as List? ?? [])
              .map((k) {
                if (k is String) {
                  if (k.trim().isEmpty) return {};
                  try {
                    return jsonDecode(k);
                  } catch (_) {
                    return {};
                  }
                }
                return k;
              })
              .toList()
              .cast<Map<String, dynamic>>();

          final unvisitedList = (data["unvisited"] as List? ?? [])
              .map((k) {
                if (k is String) {
                  if (k.trim().isEmpty) return {};
                  try {
                    return jsonDecode(k);
                  } catch (_) {
                    return {};
                  }
                }
                return k;
              })
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
      }

      // Sort
      if (!mounted) return;
      final Map<String, int> gradeOrder = {
        'grade_1_name'.tr(context): 1,
        'grade_2_name'.tr(context): 2,
        'grade_3_name'.tr(context): 3,
      };
      gradesData.sort((a, b) {
        final orderA = gradeOrder[a["grade"]] ?? 99;
        final orderB = gradeOrder[b["grade"]] ?? 99;
        return orderA.compareTo(orderB);
      });

      // Update Cache
      if (gradesData.isNotEmpty) {
        await DataCacheService().cacheVisitedDetails(
          widget.doc.$id,
          gradesData,
        );
      }

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
                    final name = kid["name"] ?? 'unknown_name'.tr(context);
                    final address =
                        kid["address"] ?? 'unknown_address'.tr(context);
                    final phones = List<String>.from(kid["phones"] ?? []);
                    final String visitedBy =
                        kid["visitedBy"] ?? 'not_specified'.tr(context);

                    final String statusText = isVisitedList
                        ? 'visited_by_status'
                              .tr(context)
                              .replaceFirst('%s', visitedBy)
                        : 'not_visited_status_text'.tr(context);

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
          'overall_visitation_total'
              .tr(context)
              .replaceFirst('%s', visited.toString())
              .replaceFirst('%s', total.toString()),
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
                  'overall_visitation_percentage'
                      .tr(context)
                      .replaceFirst('%s', percentageText), // عرض النسبة المئوية
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

    // When loaded from SharedPreferences cache, Appwrite's fromMap might nest the data
    final dynamic rawDataField = data['data'];
    final Map<String, dynamic>? nestedData =
        (rawDataField is Map<String, dynamic>) ? rawDataField : null;

    final weekName =
        data["reportName"] ?? nestedData?["reportName"] ?? widget.doc.$id;
    final totalOverall =
        data["totalOverall"] ?? nestedData?["totalOverall"] ?? 0;
    final visitedOverall =
        data["visitedOverall"] ?? nestedData?["visitedOverall"] ?? 0;
    final rawPercentage =
        data["overallPercentage"] ?? nestedData?["overallPercentage"];
    final percentageOverall =
        (rawPercentage as num?)?.toDouble().toStringAsFixed(1) ?? "0.0";

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
            onPressed: () {
              if (!mounted) return;
              _printVisitReport(context, widget.doc);
            },
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
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('no_details_available'.tr(context)),
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
                    'grade_visitation_stats'
                        .tr(context)
                        .replaceFirst('%s', grade)
                        .replaceFirst('%s', visitedCount.toString())
                        .replaceFirst('%s', totalInGrade.toString())
                        .replaceFirst('%s', percentage.toStringAsFixed(1)),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  children: [
                    ListTile(
                      title: Text(
                        'visited_count_details'
                            .tr(context)
                            .replaceFirst('%s', visitedCount.toString()),
                      ),
                      tileColor: Colors.green.shade100,
                      onTap: () => _showDetails(
                        context,
                        'visited_grade'.tr(context).replaceFirst('%s', grade),
                        visitedList,
                        true,
                      ),
                    ),
                    ListTile(
                      title: Text(
                        'unvisited_count_details'
                            .tr(context)
                            .replaceFirst('%s', unvisitedCount.toString()),
                      ),
                      tileColor: Colors.red.shade100,
                      onTap: () => _showDetails(
                        context,
                        'unvisited_grade'.tr(context).replaceFirst('%s', grade),
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

  Future<void> _printVisitReport(
    BuildContext flutterContext,
    models.Document reportDoc,
  ) async {
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

      final reportName =
          reportDoc.data['reportName'] ??
          (flutterContext.mounted
              ? 'visitation_stats_report'.tr(flutterContext)
              : 'Report');
      final timestamp = reportDoc.data['timestamp'] ?? "";

      // Fetch Data (Cache First -> File -> Legacy)
      List<Map<String, dynamic>> gradesData = [];
      bool success = false;

      // 1. Check Cache First (Crucial for Offline PDF)
      final cachedDetails = await DataCacheService().getCachedVisitedDetails(
        reportDoc.$id,
      );
      if (cachedDetails != null && cachedDetails.isNotEmpty) {
        gradesData = List<Map<String, dynamic>>.from(cachedDetails);
        success = true;
      }

      final actualData = reportDoc.data['data'] is Map<String, dynamic>
          ? reportDoc.data['data']
          : reportDoc.data;
      final fileId = actualData['fileId'] as String?;

      if (!success && fileId != null && fileId.isNotEmpty) {
        // 2. File Logic (If not cached)
        try {
          final byteList = await AppwriteService().storage.getFileDownload(
            bucketId: AppwriteService.attendanceBucketId,
            fileId: fileId,
          );

          if (byteList.isNotEmpty) {
            final jsonString = utf8.decode(byteList);
            if (jsonString.trim().isNotEmpty) {
              final Map<String, dynamic> fullReportData = jsonDecode(
                jsonString,
              );

              fullReportData.forEach((grade, gradeData) {
                final visitedList = (gradeData["visited"] as List)
                    .map((k) {
                      if (k is String) {
                        try {
                          return jsonDecode(k);
                        } catch (_) {
                          return {};
                        }
                      }
                      return k;
                    })
                    .toList()
                    .cast<Map<String, dynamic>>();

                final unvisitedList = (gradeData["unvisited"] as List)
                    .map((k) {
                      if (k is String) {
                        try {
                          return jsonDecode(k);
                        } catch (_) {
                          return {};
                        }
                      }
                      return k;
                    })
                    .toList()
                    .cast<Map<String, dynamic>>();

                gradesData.add({
                  "grade": grade,
                  "visitedList": visitedList,
                  "unvisitedList": unvisitedList,
                });
              });
              success = true;

              // Update Cache for future offline use
              await DataCacheService().cacheVisitedDetails(
                reportDoc.$id,
                gradesData,
              );
            }
          }
        } catch (e) {
          debugPrint("Error downloading PDF source file: $e");
        }
      }

      if (!success) {
        // 3. Legacy Logic (If not cached and no file/failed file)
        try {
          final detailsResult = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: visitedReportsDetailsCollectionId,
            queries: [Query.equal('reportId', reportDoc.$id), Query.limit(100)],
          );

          for (var detailDoc in detailsResult.documents) {
            final visitedList = (detailDoc.data['visited'] as List? ?? [])
                .map((k) {
                  if (k is String) {
                    if (k.trim().isEmpty) return {};
                    try {
                      return jsonDecode(k);
                    } catch (_) {
                      return {};
                    }
                  }
                  return k;
                })
                .toList()
                .cast<Map<String, dynamic>>();

            final unvisitedList = (detailDoc.data['unvisited'] as List? ?? [])
                .map((k) {
                  if (k is String) {
                    if (k.trim().isEmpty) return {};
                    try {
                      return jsonDecode(k);
                    } catch (_) {
                      return {};
                    }
                  }
                  return k;
                })
                .toList()
                .cast<Map<String, dynamic>>();

            gradesData.add({
              "grade": detailDoc.data['grade'],
              "visitedList": visitedList,
              "unvisitedList": unvisitedList,
            });
          }
          if (gradesData.isNotEmpty) {
            await DataCacheService().cacheVisitedDetails(
              reportDoc.$id,
              gradesData,
            );
          }
        } catch (e) {
          debugPrint("Error fetching legacy details for PDF: $e");
        }
      }

      // Fetch dynamic grade order
      List<String> dynamicGradeOrder = [];
      try {
        final groupId = reportDoc.data['groupId'] as String?;
        if (groupId != null) {
          dynamicGradeOrder = await GradeService(groupId: groupId).getGrades();
        }
      } catch (_) {}

      // Sort for PDF
      if (!flutterContext.mounted) return;
      gradesData.sort((a, b) {
        if (dynamicGradeOrder.isNotEmpty) {
          final indexA = dynamicGradeOrder.indexOf(a["grade"]);
          final indexB = dynamicGradeOrder.indexOf(b["grade"]);
          final safeIndexA = indexA == -1 ? 999 : indexA;
          final safeIndexB = indexB == -1 ? 999 : indexB;
          return safeIndexA.compareTo(safeIndexB);
        } else {
          // Fallback
          final Map<String, int> fallbackOrder = {
            'grade_1_name'.tr(flutterContext): 1,
            'grade_2_name'.tr(flutterContext): 2,
            'grade_3_name'.tr(flutterContext): 3,
          };
          final orderA = fallbackOrder[a["grade"]] ?? 99;
          final orderB = fallbackOrder[b["grade"]] ?? 99;
          return orderA.compareTo(orderB);
        }
      });

      if (gradesData.isEmpty) {
        if (flutterContext.mounted) {
          throw 'printing_no_data'.tr(flutterContext);
        }
        throw 'No data available for printing';
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape, // 🚀 Landscape
          theme: pw.ThemeData.withFont(
            base: ttf,
            fontFallback: [], // No emoji fallback needed
          ),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            // Provide check/x symbols by drawing them
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
                          'visitation_stats_report'.tr(flutterContext),
                          style: pw.TextStyle(
                            fontSize: 24,
                            font: ttf,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.Text(
                          'group_report_name'
                              .tr(flutterContext)
                              .replaceFirst('%s', reportName),
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
                          'extraction_time'
                              .tr(flutterContext)
                              .replaceFirst('%s', timestamp),
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
            pdfContent.add(pw.SizedBox(height: 15));

            // Generate a separate table for each grade
            for (var gradeItem in gradesData) {
              final gradeName = gradeItem['grade'] ?? "";
              final List<dynamic> visited = gradeItem['visitedList'] ?? [];
              final List<dynamic> unvisited = gradeItem['unvisitedList'] ?? [];

              final List<Map<String, dynamic>> flatList = [];
              for (var v in visited) {
                final mapV = (v is Map) ? v : {'name': v.toString()};
                flatList.add({...mapV, 'isVisited': true});
              }
              for (var u in unvisited) {
                final mapU = (u is Map) ? u : {'name': u.toString()};
                flatList.add({...mapU, 'isVisited': false});
              }

              // Sort: Visited first, then Name
              flatList.sort((a, b) {
                if (a['isVisited'] != b['isVisited']) {
                  return (a['isVisited'] == true) ? -1 : 1;
                }
                return (a['name'] ?? "").compareTo(b['name'] ?? "");
              });

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
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3), // Name
                    1: const pw.FlexColumnWidth(2), // Status
                    2: const pw.FlexColumnWidth(3), // Visited By
                  },
                  children: [
                    // Table Header
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blue800,
                      ),
                      children: [
                        _buildHeaderCell('name'.tr(flutterContext), ttf),
                        _buildHeaderCell('status'.tr(flutterContext), ttf),
                        _buildHeaderCell('by'.tr(flutterContext), ttf),
                      ],
                    ),
                    // Data Rows
                    ...flatList.isEmpty
                        ? [
                            pw.TableRow(
                              children: [
                                _buildDataCell(
                                  'no_data_available_print'.tr(flutterContext),
                                  ttf,
                                ),
                                _buildDataCell("-", ttf),
                                _buildDataCell("-", ttf),
                              ],
                            ),
                          ]
                        : flatList.map((item) {
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    _cleanPdfText(item['name'] ?? ""),
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(fontSize: 9, font: ttf),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Center(
                                    child: getStatusSymbol(
                                      item['isVisited'] == true,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    _cleanPdfText(item['visitedBy'] ?? "-"),
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(fontSize: 9, font: ttf),
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
                          padding: const pw.EdgeInsets.all(6),
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
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            "${flatList.where((e) => e['isVisited'] == true).length} / ${flatList.length}",
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 10,
                              font: ttf,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
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

            // Generate Multi-Colored Bar Chart for Bar comparison at the end
            if (gradesData.isNotEmpty) {
              double maxVal = 0;
              final List<String> gradeLabels = [];
              final List<double> percentages = [];

              for (var gradeItem in gradesData) {
                final gradeName = gradeItem['grade'] ?? "";
                final List<dynamic> visited = gradeItem['visitedList'] ?? [];
                final List<dynamic> unvisited =
                    gradeItem['unvisitedList'] ?? [];

                int gradeTotal = visited.length + unvisited.length;
                int gradeVisited = visited.length;

                double pct = gradeTotal > 0
                    ? (gradeVisited / gradeTotal) * 100
                    : 0;
                if (pct > maxVal) maxVal = pct;

                // Only add if it has a real name
                if (gradeName.isNotEmpty) {
                  gradeLabels.add(gradeName);
                  percentages.add(pct);
                }
              }

              if (maxVal == 0) maxVal = 100;

              // Fix NaN exception in PDF rendering when there is only one grade
              if (gradeLabels.length == 1) {
                gradeLabels.add(" ");
                percentages.add(0.0);
              }

              if (gradeLabels.isNotEmpty) {
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
                  // Keep padding block dataset
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

                pdfContent.add(
                  pw.Center(
                    child: pw.Container(
                      height: 200,
                      width:
                          (gradeLabels.length * 80.0) + 100, // Tighter cluster
                      child: pw.Chart(
                        title: pw.Text(
                          'chart_visitation_comparison'.tr(flutterContext),
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
                pdfContent.add(pw.SizedBox(height: 20));
              }
            }

            return pdfContent;
          },
        ),
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('visitation_stats_report'.tr(context)),
              backgroundColor: Colors.blue.shade800,
            ),
            body: PdfPreview(
              build: (format) async => pdf.save(),
              pdfFileName: 'visits_${reportDoc.$id}.pdf',
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'print_error'.tr(context).replaceFirst('%s', e.toString()),
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
        _cleanPdfText(text),
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
