// ignore_for_file: deprecated_member_use
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
import '../services/grade_service.dart';
import '../services/data_cache_service.dart';
import '../services/custom_page_service.dart'; // 🚀 Added Custom Service
import '../l10n/app_translations.dart';

class DetailedReportPage extends StatefulWidget {
  const DetailedReportPage({super.key});

  @override
  State<DetailedReportPage> createState() => _DetailedReportPageState();
}

class _DetailedReportPageState extends State<DetailedReportPage> {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
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

  String _selectedScope = "all";
  String _selectedTargetCategory = "attendees";
  String? _selectedGrade;
  List<String> _selectedPeopleNames = [];
  DateTimeRange? _selectedDateRange;

  List<String> _allGrades = [];
  List<String> _availablePeople = [];
  List<String> _customPageTypes = []; // 🚀
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
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
        await _fetchCustomPages(); // 🚀
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
      try {
        final cached = await DataCacheService().getCachedKidsList(
          _myGroupId,
          'students',
        );
        if (cached.isNotEmpty && mounted) {
          final names = cached.map((k) => k.name).toList();
          names.sort();
          setState(() {
            _availablePeople = names;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchCustomPages() async {
    if (_myGroupId.isEmpty) return;
    try {
      final pages = await CustomPageService(
        groupId: _myGroupId,
      ).getCustomPages();
      if (mounted) {
        setState(() {
          _customPageTypes = pages
              .map((doc) => doc.data['name'] as String)
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching custom pages: $e");
      try {
        final cached = await DataCacheService().getCachedCustomPages(
          _myGroupId,
        );
        if (cached.isNotEmpty && mounted) {
          setState(() {
            _customPageTypes = cached.map((c) => c['name'] as String).toList();
          });
        }
      } catch (_) {}
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
        appBar: AppBar(title: Text('detailed_reports'.tr(context))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0288D1),
      appBar: AppBar(title: Text('detailed_reports'.tr(context))),
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
        child: RefreshIndicator(
          onRefresh: () async {
            if (_myGroupId.isNotEmpty) {
              await _fetchGrades();
              await _fetchPeople();
              await _fetchCustomPages();
            } else {
              await _loadUserData();
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle('target_group'.tr(context)),
              _buildTypeSelector(),
              const SizedBox(height: 20),
              _buildSectionTitle('search_scope_title'.tr(context)),
              _buildScopeSelector(),
              if (_selectedScope == "grade") ...[
                const SizedBox(height: 10),
                _buildGradeSelector(),
              ],
              if (_selectedScope == "people") ...[
                const SizedBox(height: 10),
                _buildPeopleSelector(),
              ],
              const SizedBox(height: 20),

              _buildSectionTitle('search_period_title'.tr(context)),
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
                label: Text(
                  'generate_pdf_btn'.tr(context),
                  style: const TextStyle(fontSize: 18),
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

  Widget _buildTypeSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          RadioListTile<String>(
            title: Text('served_label'.tr(context)),
            value: "attendees",
            groupValue: _selectedTargetCategory,
            onChanged: (val) => setState(() => _selectedTargetCategory = val!),
          ),
          RadioListTile<String>(
            title: Text('servants_label'.tr(context)),
            value: "servants",
            groupValue: _selectedTargetCategory,
            onChanged: (val) => setState(() => _selectedTargetCategory = val!),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          RadioListTile<String>(
            title: Text('scope_all'.tr(context)),
            value: "all",
            groupValue: _selectedScope,
            onChanged: (val) => setState(() => _selectedScope = val!),
          ),
          RadioListTile<String>(
            title: Text('scope_specific_grade'.tr(context)),
            value: "grade",
            groupValue: _selectedScope,
            onChanged: (val) => setState(() => _selectedScope = val!),
          ),
          RadioListTile<String>(
            title: Text('scope_specific_people'.tr(context)),
            value: "people",
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
            hint: Text('select_grade_hint'.tr(context)),
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
              child: Text('select_names_button'.tr(context)),
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
              title: Text('choose_names_title'.tr(context)),
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
                  child: Text('cancel_btn'.tr(context)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedPeopleNames = tempSelected);
                    Navigator.pop(context);
                  },
                  child: Text('done_btn'.tr(context)),
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
              ? 'select_period_hint'.tr(context)
              : "${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}",
        ),
        trailing: const Icon(Icons.edit),
      ),
    );
  }

  Future<void> _generateAndDownloadReport() async {
    if (_selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_select_period'.tr(context))),
      );
      return;
    }
    if (_selectedScope == "grade" && _selectedGrade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_select_grade'.tr(context))),
      );
      return;
    }
    if (_selectedScope == "people" && _selectedPeopleNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_select_person'.tr(context))),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Structure: Category -> {Name -> Summary}
      final Map<String, Map<String, PersonSummary>> groupedResults = {};

      // 1. تحديد أسماء المستهدفين
      Set<String>? filterNames;
      if (_selectedScope == "people") {
        filterNames = _selectedPeopleNames.toSet();
      }

      // ----------------------------------------------------------------------
      // 2. جلب وتجميع سجلات الحضور (مخدومين، خدام، وصفحات مخصصة)
      // ----------------------------------------------------------------------
      final typesToFetch = _selectedTargetCategory == "servants"
          ? ['servants', 'خدام']
          : ['attendees', 'مخدومين', ..._customPageTypes];

      for (var type in typesToFetch) {
        final category = type; // e.g. "مخدومين" or "servants"

        models.DocumentList? attendanceSnap;
        try {
          attendanceSnap = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: attendanceRecordsCollectionId,
            queries: [
              Query.equal('groupId', _myGroupId),
              Query.equal('type', type),
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
        } catch (e) {
          debugPrint("Offline or error fetching attendance list for $type: $e");
          // Fallback to cache (first page only usually)
          final cached = await DataCacheService().getCachedAttendanceReports(
            _myGroupId,
            type, // Arabic types won't be in recent offline cache, but fallback is safe
          );
          if (cached.isNotEmpty) {
            final filtered = cached
                .where((docMap) {
                  final ts = docMap['timestamp'] as String?;
                  if (ts == null) return false;
                  final dt = DateTime.parse(ts);
                  return dt.isAfter(_selectedDateRange!.start) &&
                      dt.isBefore(
                        _selectedDateRange!.end.add(const Duration(days: 1)),
                      );
                })
                .map((m) => models.Document.fromMap(m))
                .toList();
            attendanceSnap = models.DocumentList(
              total: filtered.length,
              documents: filtered,
            );
          }
        }

        if (attendanceSnap == null) {
          continue;
        }

        for (var reportDoc in attendanceSnap.documents) {
          final timestampStr = reportDoc.data['timestamp'] as String;
          final dateStr = DateFormat(
            'yyyy/MM/dd',
          ).format(DateTime.parse(timestampStr));

          Map<String, dynamic> rawMap = {};

          // A. Check for File (New System)
          final fileId = reportDoc.data['fileId'] as String?;
          if (fileId != null && fileId.isNotEmpty) {
            try {
              // 🚀 Try Cache First
              final cachedContent = await DataCacheService()
                  .getCachedReportContent(fileId);
              if (cachedContent != null) {
                rawMap = cachedContent;
              } else {
                final byteList = await AppwriteService().storage
                    .getFileDownload(
                      bucketId: AppwriteService.attendanceBucketId,
                      fileId: fileId,
                    );
                if (byteList.isNotEmpty) {
                  final jsonString = utf8.decode(byteList);
                  if (jsonString.trim().isNotEmpty) {
                    rawMap = jsonDecode(jsonString);
                    // Cache it for next time
                    await DataCacheService().cacheReportContent(fileId, rawMap);
                  }
                }
              }
            } catch (e) {
              debugPrint("Error reading attendance file $fileId: $e");
            }
          }

          // B. Fallback to 'data' field (Legacy)
          if (rawMap.isEmpty) {
            final dynamic dataField = reportDoc.data['data'];
            if (dataField != null) {
              if (dataField is String && dataField.trim().isNotEmpty) {
                try {
                  rawMap = jsonDecode(dataField);
                } catch (_) {}
              } else if (dataField is Map) {
                rawMap = Map<String, dynamic>.from(dataField);
              }
            }
          }

          if (rawMap.isEmpty) {
            continue;
          }

          // Process Data
          rawMap.forEach((key, listDynamic) {
            // Logic to assign correct category from Merged Keys:
            String actualCategory = category;
            String actualGrade = key;

            if (key.contains(" - ")) {
              final parts = key.split(" - ");
              if (parts.length > 1) {
                actualGrade = parts[0];
                actualCategory = parts.sublist(1).join(" - ");
              }
            }

            // 🚀 Unify Legacy Arabic Types to Standard English Types
            if (actualCategory == 'مخدومين') actualCategory = 'attendees';
            if (actualCategory == 'خدام') actualCategory = 'servants';

            if (_selectedScope == "grade" && actualGrade != _selectedGrade) {
              return;
            }

            // Init Category Map
            if (!groupedResults.containsKey(actualCategory)) {
              groupedResults[actualCategory] = {};
            }

            List<dynamic> list = [];
            if (listDynamic is List) {
              list = listDynamic;
            } else if (listDynamic is String && listDynamic.trim().isNotEmpty) {
              try {
                final decoded = jsonDecode(listDynamic);
                if (decoded is List) list = decoded;
              } catch (_) {}
            }

            for (var itemDynamic in list) {
              if (itemDynamic is! Map) continue;
              final item = itemDynamic;
              final name =
                  item['name'] as String? ?? 'unknown_person'.tr(context);
              if (filterNames != null && !filterNames.contains(name)) continue;

              final summary = groupedResults[actualCategory]!.putIfAbsent(
                name,
                () => PersonSummary(name),
              );
              if (actualCategory == 'attendees' ||
                  actualCategory == 'servants') {
                summary.grade = actualGrade;
              }
              summary.totalSessions++;
              if (item['isPresent'] == true) {
                summary.attendanceCount++;
                summary.attendanceDates.add(dateStr);
              }
            }
          });
        }
      }

      // ----------------------------------------------------------------------
      // 3. جلب وتجميع سجلات الافتقاد (Typically mostly for Makhdomen)
      // ----------------------------------------------------------------------
      models.DocumentList? visitsSnap;
      if (_selectedTargetCategory != 'servants') {
        try {
          visitsSnap = await _databases.listDocuments(
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
        } catch (e) {
          debugPrint("Offline or error fetching visitation list: $e");
          // Fallback to cache (first page)
          final cached = await DataCacheService().getCachedVisitedReports(
            _myGroupId,
          );
          if (cached.isNotEmpty) {
            final filtered = cached
                .where((docMap) {
                  final ts = docMap['timestamp'] as String?;
                  if (ts == null) return false;
                  final dt = DateTime.parse(ts);
                  return dt.isAfter(_selectedDateRange!.start) &&
                      dt.isBefore(
                        _selectedDateRange!.end.add(const Duration(days: 1)),
                      );
                })
                .map((m) => models.Document.fromMap(m))
                .toList();
            visitsSnap = models.DocumentList(
              total: filtered.length,
              documents: filtered,
            );
          }
        }
      }

      if (visitsSnap != null) {
        for (var reportDoc in visitsSnap.documents) {
          final timestampStr = reportDoc.data['timestamp'] as String;
          final dateStr = DateFormat(
            'yyyy/MM/dd',
          ).format(DateTime.parse(timestampStr));

          Future<void> processGradeData(
            String grade,
            List<dynamic> visited,
            List<dynamic> unvisited,
          ) async {
            if (_selectedScope == "فصل محدد" ||
                (_selectedScope == "grade" && grade != _selectedGrade)) {
              return;
            }

            // Put into attendees/servants category (standardized)
            if (!groupedResults.containsKey(_selectedTargetCategory)) {
              groupedResults[_selectedTargetCategory] = {};
            }
            final categoryResults = groupedResults[_selectedTargetCategory]!;

            void updateSummary(dynamic itemData, bool isVisited) {
              final item = (itemData is String)
                  ? (itemData.trim().isNotEmpty ? jsonDecode(itemData) : {})
                  : itemData;
              if (item is! Map) return;

              final name = item['name'] as String?;
              if (name == null) {
                return;
              }
              if (filterNames != null && !filterNames.contains(name)) {
                return;
              }

              final summary = categoryResults.putIfAbsent(
                name,
                () => PersonSummary(name),
              );
              summary.grade = grade;
              summary.totalVisitOpportunities++;
              if (isVisited) {
                summary.visitCount++;
                summary.visitDates.add(dateStr);
              }
            }

            for (var item in visited) {
              updateSummary(item, true);
            }
            for (var item in unvisited) {
              updateSummary(item, false);
            }
          }

          // A. Check for File (New System)
          final fileId = reportDoc.data['fileId'] as String?;
          bool processedFromFile = false;

          if (fileId != null && fileId.isNotEmpty) {
            try {
              // 🚀 Try Cache First
              final cachedContent = await DataCacheService()
                  .getCachedReportContent(fileId);
              Map<String, dynamic>? fullReportData;

              if (cachedContent != null) {
                fullReportData = cachedContent;
              } else {
                final byteList = await AppwriteService().storage
                    .getFileDownload(
                      bucketId: AppwriteService.attendanceBucketId,
                      fileId: fileId,
                    );
                if (byteList.isNotEmpty) {
                  final jsonString = utf8.decode(byteList);
                  if (jsonString.trim().isNotEmpty) {
                    fullReportData = jsonDecode(jsonString);
                    // Cache it
                    await DataCacheService().cacheReportContent(
                      fileId,
                      fullReportData!,
                    );
                  }
                }
              }

              if (fullReportData != null) {
                for (var entry in fullReportData.entries) {
                  final grade = entry.key;
                  final gradeData = entry.value;
                  final visited = (gradeData["visited"] as List? ?? []);
                  final unvisited = (gradeData["unvisited"] as List? ?? []);
                  await processGradeData(grade, visited, unvisited);
                }
                processedFromFile = true;
              }
            } catch (e) {
              debugPrint("Error reading visited file $fileId: $e");
            }
          }

          // B. Fallback to 'visited_reports_details' collection (Legacy)
          if (!processedFromFile) {
            try {
              final detailsResult = await _databases.listDocuments(
                databaseId: databaseId,
                collectionId: visitedReportsDetailsCollectionId,
                queries: [
                  Query.equal('reportId', reportDoc.$id),
                  Query.limit(100),
                ],
              );

              for (var detailDoc in detailsResult.documents) {
                await processGradeData(
                  detailDoc.data['grade'],
                  detailDoc.data['visited'] as List? ?? [],
                  detailDoc.data['unvisited'] as List? ?? [],
                );
              }
            } catch (e) {
              debugPrint("Error reading legacy visited details: $e");
            }
          }
        }
      }

      if (groupedResults.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('no_data_for_period'.tr(context))),
          );
        }
      } else {
        if (mounted) {
          await _generatePdf(groupedResults, context);
        }
      }
    } catch (e) {
      debugPrint("Error generating report: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'error_gathering_data'
                  .tr(context)
                  .replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _generatePdf(
    Map<String, Map<String, PersonSummary>> groupedResults,
    BuildContext context,
  ) async {
    final pdf = pw.Document();

    // Load a highly stable font for Arabic
    pw.Font ttf;
    try {
      ttf = await PdfGoogleFonts.cairoRegular();
    } catch (e) {
      debugPrint(
        "Warning: Cairo font not available via Google Fonts, falling back to local Alfares: $e",
      );
      final fontData = await rootBundle.load("assets/fonts/Alfares.ttf");
      ttf = pw.Font.ttf(fontData);
    }

    pw.Font? emoji;
    try {
      // Only load emoji if available, but prioritize regular characters in ttf
      emoji = await PdfGoogleFonts.notoColorEmoji();
    } catch (e) {
      debugPrint("Warning: Emoji font could not be loaded: $e");
    }

    final String dateRangeStr = _selectedDateRange == null
        ? ""
        : "${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}";

    // Sort keys (attendees/servants first)
    final sortedKeys = groupedResults.keys.toList();
    if (sortedKeys.contains(_selectedTargetCategory)) {
      sortedKeys.remove(_selectedTargetCategory);
      sortedKeys.insert(0, _selectedTargetCategory);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(
          base: ttf,
          fontFallback: emoji != null ? [emoji] : [],
        ),
        textDirection:
            pw.TextDirection.rtl, // Fix for disconnected Arabic letters
        build: (pw.Context pdfContext) {
          // 1. Pivot Data by Grade
          final Map<String, Set<String>> namesByGrade = {};
          final List<String> customCategories = sortedKeys
              .where((k) => k != _selectedTargetCategory)
              .toList();

          for (var categoryMap in groupedResults.values) {
            for (var entry in categoryMap.entries) {
              final name = entry.key;
              final summary = entry.value;
              final grade = summary
                  .grade; // we assigned grade mostly to the target category
              namesByGrade.putIfAbsent(grade, () => {}).add(name);
            }
          }

          // Sort grades
          final sortedGradeKeys = namesByGrade.keys.toList();
          if (_allGrades.isNotEmpty) {
            sortedGradeKeys.sort((a, b) {
              final indexA = _allGrades.indexOf(a);
              final indexB = _allGrades.indexOf(b);
              final safeIndexA = indexA == -1 ? 999 : indexA;
              final safeIndexB = indexB == -1 ? 999 : indexB;
              return safeIndexA.compareTo(safeIndexB);
            });
          } else {
            sortedGradeKeys.sort();
          }

          // 2. Col Widths (Removed Grade column since each table is for a grade)
          // Name: 3, Att: 1.5, [Visit: 1.5], Each Custom: 1.5
          final Map<int, pw.TableColumnWidth> colWidths = {
            0: const pw.FlexColumnWidth(3), // Name
            1: const pw.FlexColumnWidth(1.5), // Att (General)
          };
          int colIndex = 2;
          if (_selectedTargetCategory != 'servants') {
            colWidths[colIndex++] = const pw.FlexColumnWidth(
              1.5,
            ); // Visit (General)
          }
          for (int i = 0; i < customCategories.length; i++) {
            colWidths[colIndex++] = const pw.FlexColumnWidth(1.5);
          }

          final List<pw.Widget> content = [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'detailed_report_table_title'.tr(context),
                    style: pw.TextStyle(
                      fontSize: 22,
                      font: ttf,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    DateFormat('yyyy/MM/dd').format(DateTime.now()),
                    style: pw.TextStyle(font: ttf),
                  ),
                ],
              ),
            ),
            pw.Paragraph(
              text: "${'search_period_title'.tr(context)}: $dateRangeStr",
              style: pw.TextStyle(font: ttf, fontSize: 10),
            ),
            pw.SizedBox(height: 10),
          ];

          for (String gradeName in sortedGradeKeys) {
            final sortedNames = namesByGrade[gradeName]!.toList()..sort();

            content.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
                child: pw.Center(
                  child: pw.Text(
                    gradeName,
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                ),
              ),
            );

            content.add(
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: colWidths,
                children: [
                  // Table Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue800,
                    ),
                    children: [
                      _buildHeaderCell('name_col'.tr(context), ttf),
                      _buildHeaderCell(
                        _selectedTargetCategory == 'servants'
                            ? 'servants_attendance'.tr(context)
                            : 'makhdomen_attendance_col'.tr(context),
                        ttf,
                      ),
                      if (_selectedTargetCategory != 'servants')
                        _buildHeaderCell(
                          'makhdomen_visitation_col'.tr(context),
                          ttf,
                        ),
                      ...customCategories.map(
                        (cat) => _buildHeaderCell(
                          (cat == _selectedTargetCategory)
                              ? (_selectedTargetCategory == 'servants'
                                    ? 'servants_attendance'.tr(context)
                                    : 'makhdomen_attendance_col'.tr(context))
                              : cat,
                          ttf,
                        ),
                      ),
                    ],
                  ),
                  // Data Rows
                  ...sortedNames.isEmpty
                      ? [
                          pw.TableRow(
                            children: [
                              _buildDataCell(
                                'no_data_available_for_period_pdf'.tr(context),
                                ttf,
                              ),
                              _buildDataCell("-", ttf),
                              if (_selectedTargetCategory != 'servants')
                                _buildDataCell("-", ttf),
                              ...customCategories.map(
                                (_) => _buildDataCell("-", ttf),
                              ),
                            ],
                          ),
                        ]
                      : sortedNames.map((name) {
                          final mStats =
                              groupedResults[_selectedTargetCategory]?[name];

                          // Target Category Stats
                          final mAtt = mStats == null
                              ? "-"
                              : "${mStats.attendanceCount}/${mStats.totalSessions}";
                          final mVis = mStats == null
                              ? "-"
                              : "${mStats.visitCount}/${mStats.totalVisitOpportunities}";

                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  _cleanPdfText(name),
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(fontSize: 10, font: ttf),
                                ),
                              ),
                              _buildDataCell(mAtt, ttf),
                              if (_selectedTargetCategory != 'servants')
                                _buildDataCell(mVis, ttf),
                              ...customCategories.map((cat) {
                                final cStats = groupedResults[cat]?[name];
                                return _buildDataCell(
                                  cStats == null
                                      ? "-"
                                      : "${cStats.attendanceCount}/${cStats.totalSessions}",
                                  ttf,
                                );
                              }),
                            ],
                          );
                        }).toList(),
                ],
              ),
            );
            content.add(pw.SizedBox(height: 10));
          }

          return content;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'detailed_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  pw.Widget _buildHeaderCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 10,
          font: font,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _buildDataCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        _cleanPdfText(text),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 9, font: font),
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

class PersonSummary {
  final String name;
  String grade = "-";
  int attendanceCount = 0;
  int totalSessions = 0;
  int visitCount = 0;
  int totalVisitOpportunities = 0;
  List<String> attendanceDates = [];
  List<String> visitDates = [];

  PersonSummary(this.name);
}
