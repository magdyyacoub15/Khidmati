import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'attendance_grade_selector_page.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:async';
import 'dart:convert';
import '../services/grade_service.dart';
import '../services/ai_insight_service.dart';
import '../services/appwrite_service.dart';
import '../services/permission_service.dart';
import 'package:intl/intl.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service
import '../services/user_service.dart';
import '../services/custom_page_service.dart'; // 🚀 Added Custom Page Service
import '../l10n/app_translations.dart';

class AttendanceTypeSelectorPage extends StatefulWidget {
  const AttendanceTypeSelectorPage({super.key});

  @override
  State<AttendanceTypeSelectorPage> createState() =>
      _AttendanceTypeSelectorPageState();
}

class _AttendanceTypeSelectorPageState
    extends State<AttendanceTypeSelectorPage> {
  late GradeService _gradeService;
  late CustomPageService _customPageService; // 🚀 Service Instance
  List<models.Document> _customPages = [];
  bool _isLoadingCustomPages = true;

  bool _isAdmin = false;
  bool _canWrite = true; // 🚀 Subscription Check
  bool _isLoadingRole = true;
  String _myGroupId = '';
  
  // 🏆 Points System Settings
  bool _pointsSystemEnabled = false;
  List<String> _pointsSystemTypes = [];
  int _pointsPerAttendance = 1;

  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = AppwriteService().realtime;
  final Account _account = AppwriteService().account;
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String attendanceStatusCollectionId = 'attendance_status';
  static const String attendanceRecordsCollectionId = 'attendance_records';

  // 🔄 متغيرات الحفظ
  bool _isSaving = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _weekNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    _weekNameController.dispose();
    _userSubscription?.close();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    // 🚀 1. Try to load from cache IMMEDIATELY (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        _applyUserData(
          cachedCtx['groupId']!,
          cachedCtx['role'] == 'admin' || cachedCtx['role'] == 'super_admin',
        );
      }
    } else {
      // Try global fallback if specific user cache not found
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        _applyUserData(
          lastData['groupId'],
          lastData['role'] == 'admin' || lastData['role'] == 'super_admin',
        );
      }
    }

    // 🚀 2. Background Network Refresh (Silent)
    try {
      final user = await _account.get();
      final userId = user.$id;
      // Fetch actual document to get true role regardless of cache
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );

      // Cache ID for next time
      await UserService().getCurrentUser();

      // Update Cache with fresh data to correct any invalid stored session
      await DataCacheService().cacheUserGroupId(
        userId,
        doc.data['groupId'] ?? '',
        doc.data['teamId'] ?? '',
        doc.data['role'] ?? 'user',
      );

      // Update state directly with fresh data
      _updateState(doc.data);

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
      debugPrint("Network fetch failed (offline mode active): $e");
      // We already loaded cache, so just stop loading if still loading
      if (mounted && _isLoadingRole) {
        setState(() => _isLoadingRole = false);
      }
    }
  }

  void _applyUserData(String groupId, bool isAdmin) async {
    final canWrite = await PermissionService.canWrite(groupId);
    if (mounted) {
      setState(() {
        _myGroupId = groupId;
        _isAdmin = isAdmin;
        _canWrite = canWrite;
        if (_myGroupId.isNotEmpty) {
          _gradeService = GradeService(groupId: _myGroupId);
          // 🚀 Initialize Service & Fetch (Cache path)
          _customPageService = CustomPageService(groupId: _myGroupId);
          _fetchCustomPages();
          _fetchGroupSettings(); // Fetch points settings
        }
        _isLoadingRole = false;
      });
    }
  }

  void _updateState(Map<String, dynamic> data) async {
    final canWrite = await PermissionService.canWrite(data['groupId'] ?? '');
    if (mounted) {
      setState(() {
        _myGroupId = data['groupId'] ?? '';
        _isAdmin = (data['role'] == 'admin' || data['role'] == 'super_admin');
        _canWrite = canWrite;
        if (_myGroupId.isNotEmpty) {
          _gradeService = GradeService(groupId: _myGroupId);
          // 🚀 Initialize Service & Fetch
          _customPageService = CustomPageService(groupId: _myGroupId);
          _fetchCustomPages();
          _fetchGroupSettings(); // Fetch points settings
        }
        _isLoadingRole = false;
      });
    }
  }

  Future<void> _fetchCustomPages() async {
    // 🚀 Load from cache instantly if possible
    if (_myGroupId.isNotEmpty) {
      final cached = await DataCacheService().getCachedCustomPages(_myGroupId);
      if (cached.isNotEmpty && mounted && _customPages.isEmpty) {
        setState(() {
          _customPages = cached.map((m) => models.Document.fromMap(m)).toList();
          _isLoadingCustomPages = false;
        });
      }
    }

    try {
      final pages = await _customPageService.getCustomPages();
      if (mounted) {
        setState(() {
          _customPages = pages;
          _isLoadingCustomPages = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching custom pages: $e");
      if (mounted) setState(() => _isLoadingCustomPages = false);
    }
  }

  Future<void> _fetchGroupSettings() async {
    if (_myGroupId.isEmpty) return;
    try {
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'groups',
        documentId: _myGroupId,
      );
      if (mounted) {
        setState(() {
          _pointsSystemEnabled = doc.data['pointsSystemEnabled'] ?? false;
          _pointsSystemTypes = List<String>.from(doc.data['pointsSystemTypes'] ?? []);
          _pointsPerAttendance = doc.data['pointsPerAttendance'] ?? 1;
        });
      }
    } catch (e) {
      debugPrint("Error fetching group settings: $e");
    }
  }

  Future<void> _showPointsSettingsDialog() async {
    if (!_isAdmin) return;
    bool tempEnabled = _pointsSystemEnabled;
    List<String> tempTypes = List.from(_pointsSystemTypes);
    int tempPoints = _pointsPerAttendance;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.stars, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('إعدادات نظام النقاط'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('تفعيل نظام النقاط'),
                      value: tempEnabled,
                      onChanged: (val) {
                        setDialogState(() => tempEnabled = val);
                      },
                    ),
                    if (tempEnabled) ...[
                      const Divider(),
                      const Text('عدد النقاط لكل حضور:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              if (tempPoints > 1) setDialogState(() => tempPoints--);
                            },
                          ),
                          Text('$tempPoints', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              setDialogState(() => tempPoints++);
                            },
                          ),
                        ],
                      ),
                      const Divider(),
                      const Text('تطبيق النظام على:', style: TextStyle(fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        title: Text('servants_attendance'.tr(context)),
                        value: tempTypes.contains('servants'),
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) { tempTypes.add('servants'); }
                            else { tempTypes.remove('servants'); }
                          });
                        },
                      ),
                      CheckboxListTile(
                        title: Text('served_attendance'.tr(context)),
                        value: tempTypes.contains('attendees'),
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) { tempTypes.add('attendees'); }
                            else { tempTypes.remove('attendees'); }
                          });
                        },
                      ),
                      ..._customPages.map((page) {
                        final pageName = page.data['name'];
                        return CheckboxListTile(
                          title: Text(pageName),
                          value: tempTypes.contains(pageName),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) { tempTypes.add(pageName); }
                              else { tempTypes.remove(pageName); }
                            });
                          },
                        );
                      }),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('cancel'.tr(context)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    try {
                      await _databases.updateDocument(
                        databaseId: databaseId,
                        collectionId: 'groups',
                        documentId: _myGroupId,
                        data: {
                          'pointsSystemEnabled': tempEnabled,
                          'pointsSystemTypes': tempTypes,
                          'pointsPerAttendance': tempPoints,
                        },
                      );
                      if (mounted) {
                        setState(() {
                          _pointsSystemEnabled = tempEnabled;
                          _pointsSystemTypes = tempTypes;
                          _pointsPerAttendance = tempPoints;
                        });
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('تم حفظ إعدادات النقاط بنجاح')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('خطأ في حفظ الإعدادات: $e')),
                        );
                      }
                    }
                  },
                  child: Text('save'.tr(context)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addCustomPage() async {
    if (!_isAdmin) return;
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('add_new_attendance_page'.tr(context)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'page_name_hint'.tr(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(dialogContext); // Close dialog first

              final error = await _customPageService.addCustomPage(
                controller.text.trim(),
              );

              if (!mounted) {
                return; // 🚀 Fix: Check mounted before using context
              }

              if (error != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("❌ $error")));
              } else {
                _fetchCustomPages(); // 🚀 Refresh from cache (Optimistic)
                bool isConnected = true;
                if (!kIsWeb) {
                  try {
                    final result = await InternetAddress.lookup('google.com');
                    isConnected =
                        result.isNotEmpty && result[0].rawAddress.isNotEmpty;
                  } catch (_) {
                    isConnected = false;
                  }
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isConnected
                            ? 'page_added_success'.tr(context)
                            : 'offline_saved'.tr(context),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text('add'.tr(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomPage(String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete_page_title'.tr(context).replaceFirst('%s', name)),
        content: Text('delete_page_confirm'.tr(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr(context)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr(context)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _customPageService.deleteCustomPage(docId);
      if (success) {
        _fetchCustomPages();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('page_deleted_success'.tr(context))),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('page_delete_failed'.tr(context))),
          );
        }
      }
    }
  }

  Future<void> _addPointsForCurrentAttendance(Function(String) onProgress) async {
    if (!_pointsSystemEnabled || _pointsSystemTypes.isEmpty) return;
    
    onProgress('جاري احتساب النقاط...');
    final allGrades = await _gradeService.getGrades();

    for (String type in _pointsSystemTypes) {
      String baseCollection = (type == 'servants' || type == 'خدام') ? 'servants' : 'students';
      
      for (String grade in allGrades) {
        // Fetch status for this grade and type
        final statusResult = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: attendanceStatusCollectionId,
          queries: [
            Query.equal('groupId', _myGroupId),
            Query.equal('grade', grade),
            Query.equal('type', type),
            Query.limit(1000),
          ],
        );

        for (var doc in statusResult.documents) {
          if (doc.data['isPresent'] == true) {
            final name = doc.data['name'];
            
            // Find kid in base collection
            final kidResult = await _databases.listDocuments(
              databaseId: databaseId,
              collectionId: baseCollection,
              queries: [
                Query.equal('groupId', _myGroupId),
                Query.equal('grade', grade),
                Query.equal('name', name),
                Query.limit(1),
              ],
            );
            
            if (kidResult.documents.isNotEmpty) {
              final kidDoc = kidResult.documents.first;
              final currentPoints = kidDoc.data['points'] ?? 0;
              await _databases.updateDocument(
                databaseId: databaseId,
                collectionId: baseCollection,
                documentId: kidDoc.$id,
                data: {
                  'points': currentPoints + _pointsPerAttendance,
                },
              );
            }
          }
        }
      }
    }
  }

  Future<void> _saveAndResetBothTypes(
    String reportName,
    DateTime selectedDate,
    String saveMode,
    Function(String) onProgress,
  ) async {
    if (!_canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('subscription_expired_warning'.tr(context))),
      );
      return;
    }

    try {
      // ----------------------------------------------------------------------
      // 0. Add Points
      // ----------------------------------------------------------------------
      if (_pointsSystemEnabled) {
        await _addPointsForCurrentAttendance(onProgress);
      }

      if (saveMode == 'save_and_reset') {
        // ----------------------------------------------------------------------
        // 1. Save Servants Report (Separately as before)
        // ----------------------------------------------------------------------
        await _saveReportForType(
          reportName,
          selectedDate,
          'servants',
          onProgress,
        );

        // ----------------------------------------------------------------------
        // 2. Save Consolidated Report (Makhdomen + Custom Pages)
        // ----------------------------------------------------------------------
        if (!mounted) return;
        onProgress('preparing_unified_report'.tr(context));

        final allGrades = await _gradeService.getGrades();
        if (!mounted) return;
        final Map<String, List<Map<String, dynamic>>> fullReportData = {};
        int totalOverall = 0;
        int presentOverall = 0;

        // A. Collect "Makhdomen" Data
        for (final grade in allGrades) {
          if (!mounted) return;
          onProgress(
            'processing_attendees_data'.tr(context).replaceFirst('%s', grade),
          );
          final gradeData = await _fetchGradeData(
            grade,
            'attendees',
            'students',
          ); // Helper method
          fullReportData[grade] = gradeData.list;
          totalOverall += gradeData.total;
          presentOverall += gradeData.present;
        }

        // B. Collect Custom Pages Data
        for (var page in _customPages) {
          final pageName = page.data['name'];
          if (!mounted) return;
          onProgress(
            'processing_page_data'.tr(context).replaceFirst('%s', pageName),
          );

          // Check if page has any data first to avoid empty processing
          final hasData = await _checkIfPageHasData(pageName);
          if (!hasData) continue;

          for (final grade in allGrades) {
            final gradeData = await _fetchGradeData(
              grade,
              pageName,
              'students',
            ); // Assume custom pages use 'students' collection for base list

            if (gradeData.total > 0) {
              // Composite Key: "Grade - PageName"
              fullReportData["$grade - $pageName"] = gradeData.list;
              totalOverall += gradeData.total;
              presentOverall += gradeData.present;
            }
          }
        }

        // C. Save Single File & Document
        if (fullReportData.isNotEmpty) {
          await _uploadAndSaveReport(
            reportName,
            selectedDate,
            'attendees', // We save under "attendees" type but it includes everything
            fullReportData,
            totalOverall,
            presentOverall,
            onProgress,
          );
        } else {
          if (!mounted) return;
          onProgress('no_data_to_save'.tr(context));
        }
      }

      // D. Reset Status (Delete Documents)
      if (!mounted) return;
      onProgress('resetting_data'.tr(context));
      final allGradesForReset = await _gradeService.getGrades();
      // Reset Makhdomen
      await _resetStatusForType('attendees', allGradesForReset, onProgress);
      // Reset Custom Pages
      for (var page in _customPages) {
        await _resetStatusForType(page.data['name'], allGradesForReset, onProgress);
      }

      // 💡 Update AI Insights
      if (_myGroupId.isNotEmpty) {
        if (!mounted) return;
        onProgress('updating_ai_insights'.tr(context));
        await AIInsightService(groupId: _myGroupId).generateInsights();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saveMode == 'save_and_reset' 
                ? 'unified_report_saved_success'.tr(context).replaceFirst('%s', reportName)
                : 'تم تحديث النقاط وإعادة التعيين بنجاح',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error in save: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'unified_report_save_failed'
                  .tr(context)
                  .replaceFirst('%s', e.toString()),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // Helper: Check if there is any attendance data for a type
  Future<bool> _checkIfPageHasData(String type) async {
    final result = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: attendanceStatusCollectionId,
      queries: [
        Query.equal('groupId', _myGroupId),
        Query.equal('type', type),
        Query.limit(1),
      ],
    );
    return result.total > 0;
  }

  // Helper Struct
  // ignore: library_private_types_in_public_api
  Future<({List<Map<String, dynamic>> list, int total, int present})>
  _fetchGradeData(String grade, String type, String baseCollectionId) async {
    // 1. Fetch Base List (Students/Servants)
    // Note: Custom pages essentially track "Students" usually.
    // If you want custom pages to track servants, we might need a flag.
    // For now assuming Custom Pages = Sub-groups of Students (like Sunday School).
    final baseListResult = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: baseCollectionId,
      queries: [
        Query.equal('groupId', _myGroupId),
        Query.equal('grade', grade),
        Query.limit(100),
      ],
    );

    // 2. Fetch Status
    final statusResult = await _databases.listDocuments(
      databaseId: databaseId,
      collectionId: attendanceStatusCollectionId,
      queries: [
        Query.equal('groupId', _myGroupId),
        Query.equal('grade', grade),
        Query.equal('type', type),
        Query.limit(1000),
      ],
    );

    final Map<String, models.Document> statusMap = {};
    for (var doc in statusResult.documents) {
      statusMap[doc.data['name']] = doc;
    }

    final List<Map<String, dynamic>> gradeList = [];
    int total = 0;
    int present = 0;

    for (var baseDoc in baseListResult.documents) {
      final name = baseDoc.data['name'];
      bool isPresent = false;
      String markedBy = '';
      String note = '';

      if (statusMap.containsKey(name)) {
        final sData = statusMap[name]!.data;
        isPresent = sData['isPresent'] ?? false;
        markedBy = sData['markedBy'] ?? '';
        note = sData['note'] ?? '';
      }

      if (isPresent) present++;
      total++;

      gradeList.add({
        'name': name,
        'isPresent': isPresent,
        'markedBy': markedBy,
        'note': note,
      });
    }

    return (list: gradeList, total: total, present: present);
  }

  Future<void> _resetStatusForType(
    String type,
    List<String> grades,
    Function(String) onProgress,
  ) async {
    for (var grade in grades) {
      // We can't delete by query easily without cloud functions loop or iterating.
      // So we list and delete.
      // To optimize, we can use the batch method if we had IDs,
      // but here we just query all status docs for this grade/type.

      bool hasMore = true;
      String? cursor;

      while (hasMore) {
        final queries = [
          Query.equal('groupId', _myGroupId),
          Query.equal('grade', grade),
          Query.equal('type', type),
          Query.limit(100),
        ];
        if (cursor != null) queries.add(Query.cursorAfter(cursor));

        final result = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: attendanceStatusCollectionId,
          queries: queries,
        );

        if (result.documents.isEmpty) {
          hasMore = false;
          break;
        }

        // Delete Batch
        // Note: In a real large app, this should be a backend function.
        await Future.wait(
          result.documents.map(
            (doc) => _databases.deleteDocument(
              databaseId: databaseId,
              collectionId: attendanceStatusCollectionId,
              documentId: doc.$id,
            ),
          ),
        );

        if (result.documents.length < 100) {
          hasMore = false;
        } else {
          cursor = result.documents.last.$id;
        }
      }
    }
  }

  Future<void> _uploadAndSaveReport(
    String reportName,
    DateTime selectedDate,
    String type,
    Map<String, List<Map<String, dynamic>>> fullReportData,
    int totalOverall,
    int presentOverall,
    Function(String) onProgress,
  ) async {
    // 4. Save Report (As File)
    if (!mounted) return;
    final String localizedType = type.tr(context);
    onProgress(
      'uploading_report_file'.tr(context).replaceFirst('%s', localizedType),
    );
    String fileId = '';
    try {
      final jsonString = jsonEncode(fullReportData);
      // Create file in Storage
      final fileData = InputFile.fromBytes(
        bytes: utf8.encode(jsonString),
        filename: 'report_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      final uploadedFile = await AppwriteService().storage.createFile(
        bucketId: AppwriteService.attendanceBucketId,
        fileId: ID.unique(),
        file: fileData,
      );
      fileId = uploadedFile.$id;
    } catch (e) {
      debugPrint("Error uploading report file: $e");
      // Fallback: If upload fails, we might throw or continue without fileId
      // For now, let's rethrow to alert user
      if (!mounted) {
        throw Exception("Component unmounted during file upload");
      }
      throw Exception(
        'failed_to_upload_report'.tr(context).replaceFirst('%s', e.toString()),
      );
    }

    if (!mounted) return;
    onProgress('saving_report_record'.tr(context));
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final user = await _account.get();

    // ignore: unused_local_variable
    final currentUserName = user.name;

    await _databases.createDocument(
      databaseId: databaseId,
      collectionId: attendanceRecordsCollectionId,
      documentId: ID.unique(),
      data: {
        'reportName': reportName,
        'date': formattedDate,
        'timestamp': DateTime.now().toIso8601String(),
        'resetBy': user.name,
        'type': type,
        'totalOverall': totalOverall,
        'presentOverall': presentOverall,
        'overallPercentage': totalOverall == 0
            ? 0.0
            : (presentOverall / totalOverall) * 100,
        'groupId': _myGroupId,
        'fileId': fileId, // Save file ID
        'data': '', // Empty data field as we use file now
      },
    );
  }

  Future<void> _saveReportForType(
    String reportName,
    DateTime selectedDate,
    String type,
    Function(String) onProgress,
  ) async {
    final String localizedType = type.tr(context);
    final preparingDataTemplate = 'preparing_data_for'.tr(context);
    final processingTypeGradeTemplate = 'processing_type_grade'.tr(context);
    final uploadingReportFileTemplate = 'uploading_report_file'.tr(context);
    final savingReportRecordMsg = 'saving_report_record'.tr(context);
    final resettingTypeTemplate = 'resetting_type'.tr(context);
    final resettingTypeGradeTemplate = 'resetting_type_grade'.tr(context);
    final failedToUploadTemplate = 'failed_to_upload_report'.tr(context);

    if (!mounted) return;
    onProgress(preparingDataTemplate.replaceFirst('%s', localizedType));
    // 1. Get all grades
    final allGrades = await _gradeService.getGrades();
    if (!mounted) return;

    // We will collect data for all grades in this map
    // Structure: GradeName -> List of Kid Maps
    final Map<String, List<Map<String, dynamic>>> fullReportData = {};

    int totalOverall = 0;
    int presentOverall = 0;

    // Determine collections
    final String collectionId = (type == "خدام" || type == "servants")
        ? 'servants'
        : 'students';

    // 2. Iterate grades to build report
    for (int gIndex = 0; gIndex < allGrades.length; gIndex++) {
      final grade = allGrades[gIndex];
      final progressMsg = processingTypeGradeTemplate
          .replaceFirst('%s', localizedType)
          .replaceFirst('%s', grade)
          .replaceFirst('%d', (gIndex + 1).toString())
          .replaceFirst('%d', allGrades.length.toString());
      onProgress(progressMsg);

      // Fetch base list
      final baseListResult = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('grade', grade),
          Query.limit(100),
        ],
      );

      // Fetch status
      final statusResult = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceStatusCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('grade', grade),
          Query.equal('type', type),
          Query.limit(1000),
        ],
      );

      final Map<String, models.Document> statusMap = {};
      for (var doc in statusResult.documents) {
        statusMap[doc.data['name']] = doc;
      }

      final List<Map<String, dynamic>> gradeList = [];
      for (var baseDoc in baseListResult.documents) {
        final name = baseDoc.data['name'];
        bool isPresent = false;
        String markedBy = '';
        String note = '';

        if (statusMap.containsKey(name)) {
          final sData = statusMap[name]!.data;
          isPresent = sData['isPresent'] ?? false;
          markedBy = sData['markedBy'] ?? '';
          note = sData['note'] ?? '';
        }

        if (isPresent) presentOverall++;
        totalOverall++;

        gradeList.add({
          'name': name,
          'isPresent': isPresent,
          'markedBy': markedBy,
          'note': note,
        });
      }

      fullReportData[grade] = gradeList;
    }

    // 3. Save Report (As File)
    if (!mounted) return;
    onProgress(uploadingReportFileTemplate.replaceFirst('%s', localizedType));
    String fileId = '';
    try {
      final jsonString = jsonEncode(fullReportData);
      // Create file in Storage
      final fileData = InputFile.fromBytes(
        bytes: utf8.encode(jsonString),
        filename: 'report_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      final uploadedFile = await AppwriteService().storage.createFile(
        bucketId: AppwriteService.attendanceBucketId,
        fileId: ID.unique(),
        file: fileData,
      );
      fileId = uploadedFile.$id;
    } catch (e) {
      debugPrint("Error uploading report file: $e");
      // Fallback: If upload fails, we might throw or continue without fileId
      // For now, let's rethrow to alert user
      if (!mounted) {
        throw Exception("Component unmounted during report upload");
      }
      throw Exception(failedToUploadTemplate.replaceFirst('%s', e.toString()));
    }

    if (!mounted) return;
    onProgress(savingReportRecordMsg);
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final user = await _account.get();
    if (!mounted) return;
    final currentUserName = user.name;

    await _databases.createDocument(
      databaseId: databaseId,
      collectionId: attendanceRecordsCollectionId,
      documentId: ID.unique(),
      data: {
        'reportName': reportName,
        'date': formattedDate,
        'timestamp': DateTime.now().toIso8601String(),
        'resetBy': currentUserName,
        'type': type,
        'totalOverall': totalOverall,
        'presentOverall': presentOverall,
        'overallPercentage': totalOverall == 0
            ? 0.0
            : (presentOverall / totalOverall) * 100,
        'groupId': _myGroupId,
        'fileId': fileId, // Save file ID
        'data': '', // Empty data field as we use file now
      },
    );

    // 4. Delete/Reset status for all grades (With Throttling) AFTER saving
    if (!mounted) return;
    onProgress(resettingTypeTemplate.replaceFirst('%s', localizedType));
    for (int gIndex = 0; gIndex < allGrades.length; gIndex++) {
      final grade = allGrades[gIndex];

      final statusResult = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: attendanceStatusCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('grade', grade),
          Query.equal('type', type),
          Query.limit(1000),
        ],
      );

      const int batchSize = 5;
      final docsToDelete = statusResult.documents;
      for (var i = 0; i < docsToDelete.length; i += batchSize) {
        if (docsToDelete.length > 20) {
          final resettingMsg = resettingTypeGradeTemplate
              .replaceFirst('%s', localizedType)
              .replaceFirst('%s', grade)
              .replaceFirst(
                '%d',
                (i + batchSize > docsToDelete.length
                        ? docsToDelete.length
                        : i + batchSize)
                    .toString(),
              )
              .replaceFirst('%d', docsToDelete.length.toString());
          onProgress(resettingMsg);
        }
        final batch = docsToDelete.skip(i).take(batchSize);
        await Future.wait(
          batch.map(
            (doc) => _databases.deleteDocument(
              databaseId: databaseId,
              collectionId: attendanceStatusCollectionId,
              documentId: doc.$id,
            ),
          ),
        );
        // Add a small delay between batches
        if (i + batchSize < docsToDelete.length) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    }
  }

  Future<void> _showManualSaveDialog() async {
    _selectedDate = DateTime.now();
    _weekNameController.text =
        "${'attendance_report_prefix'.tr(context)} ${DateFormat('yyyy-MM-dd').format(_selectedDate)}";

    String savingStatus = 'preparing_save'.tr(context);
    String saveMode = 'save_and_reset'; // 'save_and_reset' or 'points_and_reset'

    await showDialog(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('save_report_and_reset'.tr(context)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_canWrite)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'subscription_expired_warning'.tr(context),
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (saveMode == 'save_and_reset')
                    TextField(
                      controller: _weekNameController,
                      decoration: InputDecoration(
                        labelText: 'unified_report_name'.tr(context),
                        hintText: 'report_name_hint'.tr(context),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  if (saveMode == 'save_and_reset')
                    const SizedBox(height: 16),
                  if (saveMode == 'save_and_reset')
                    Row(
                    children: [
                      Text('report_date'.tr(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                    initialEntryMode:
                                        DatePickerEntryMode.calendar,
                                  );
                                  if (picked != null &&
                                      picked != _selectedDate) {
                                    setDialogState(() {
                                      _selectedDate = picked;
                                      _weekNameController.text =
                                          "${'attendance_report_prefix'.tr(context)} ${DateFormat('yyyy-MM-dd').format(_selectedDate)}";
                                    });
                                  }
                                },
                          child: Text(
                            DateFormat('yyyy-MM-dd').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_pointsSystemEnabled) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    RadioListTile<String>(
                      title: const Text('حفظ التقرير وإضافة النقاط وإعادة التعيين', style: TextStyle(fontSize: 14)),
                      value: 'save_and_reset',
                      groupValue: saveMode,
                      onChanged: (val) {
                        if (val != null) setDialogState(() => saveMode = val);
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('إضافة النقاط فقط وإعادة التعيين', style: TextStyle(fontSize: 14)),
                      value: 'points_and_reset',
                      groupValue: saveMode,
                      onChanged: (val) {
                        if (val != null) setDialogState(() => saveMode = val);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'save_and_reset_warning'.tr(context),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_isSaving) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      savingStatus,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!_isSaving)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('cancel'.tr(context)),
                ),
              ElevatedButton(
                  onPressed: (_isSaving || !_canWrite)
                      ? null
                      : () async {
                          if (saveMode == 'save_and_reset' && _weekNameController.text.trim().isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'enter_report_name_warning'.tr(context),
                                  ),
                                ),
                              );
                            }
                            return;
                          }

                          setDialogState(() => _isSaving = true);
                          await _saveAndResetBothTypes(
                            _weekNameController.text.trim(),
                            _selectedDate,
                            saveMode,
                            (status) {
                              if (context.mounted) {
                                setDialogState(() => savingStatus = status);
                              }
                            },
                          );
                          setDialogState(() => _isSaving = false);
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text('save'.tr(context)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('choose_attendance_type'.tr(context)),
        actions: [
          if (_isAdmin)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.stars, color: Colors.orange, size: 24),
                tooltip: 'إعدادات النقاط',
                onPressed: _showPointsSettingsDialog,
              ),
            ),
          if (_isAdmin)
            IconButton(
              icon: Icon(
                Icons.save,
                color: _canWrite ? Colors.green : Colors.grey,
              ),
              tooltip: _canWrite
                  ? 'save_attendance_report'.tr(context)
                  : 'subscription_expired'.tr(context),
              onPressed: _showManualSaveDialog,
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
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                await _fetchUserData();
                if (_myGroupId.isNotEmpty) await _fetchCustomPages();
              },
              child: Center(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person),
                    label: Text('servants_attendance'.tr(context)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 32,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AttendanceGradeSelectorPage(type: 'servants'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.child_care),
                    label: Text('served_attendance'.tr(context)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 32,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AttendanceGradeSelectorPage(type: 'attendees'),
                        ),
                      );
                    },
                  ),

                  // 🚀 Dynamic Custom Pages List
                  if (_isLoadingCustomPages)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: CircularProgressIndicator(),
                    )
                  else
                    ..._customPages.map((page) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.class_), // Or custom icon
                          label: Text(page.data['name']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.purple, // Distinct color
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 32,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          onLongPress: (_isAdmin && _canWrite)
                              ? () => _deleteCustomPage(
                                  page.$id,
                                  page.data['name'],
                                )
                              : null,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AttendanceGradeSelectorPage(
                                  type: page.data['name'],
                                ),
                                // We use name as type key for simplicity or fetch mapping
                              ),
                            );
                          },
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
        Positioned(
              left: 5,
              bottom: 5,
              child: Opacity(
                opacity: 0.8,
                child: Image.asset(
                  "assets/images/magdi_yacoub.png",
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          (_isAdmin &&
              _canWrite &&
              !_isLoadingCustomPages &&
              _customPages.length < 2)
          ? FloatingActionButton(
              onPressed: _addCustomPage,
              tooltip: 'add_new_page'.tr(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
