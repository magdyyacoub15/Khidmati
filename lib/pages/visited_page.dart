import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';
import 'kids_list_page.dart';
import '../services/grade_service.dart';
import '../services/user_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import '../services/image_service.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service
import '../services/permission_service.dart';
import 'package:universal_io/io.dart';
import '../l10n/app_translations.dart';

const String studentsCollection = "students";
const String servantsCollection = "servants";

class VisitedPage extends StatefulWidget {
  const VisitedPage({super.key});

  @override
  State<VisitedPage> createState() => _VisitedPageState();
}

class _VisitedPageState extends State<VisitedPage> {
  late GradeService _gradeService;
  bool _isAdmin = false;
  bool _isLoadingRole = true;
  String _myGroupId = '';
  String? _teamId;

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Client _client = AppwriteService().client;
  late Realtime _realtime;
  RealtimeSubscription? _userSubscription;
  StreamSubscription<List<String>>?
  _gradesSubscription; // 🚀 Grades Subscription

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String studentsCollectionId = 'students';
  static const String visitedReportsCollectionId =
      'visited_reports'; // 🚀 Fixed collection Id reference inconsistency (if any) or just kept same.
  // Actually, keeping lines consistent with existing code is key.
  // The original code had:
  // static const String visitedReportsCollectionId = 'visited_reports';

  // 🚀 State for Grades
  List<String> _grades = [];
  bool _isLoadingGrades = true;

  // 🔄 متغيرات الترحيل
  static const String _promotionPassword = '123456';

  // متغيرات حفظ تقرير الافتقاد
  bool _isSaving = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _weekNameController = TextEditingController();
  bool _canWrite = true; // 🚀 Subscription Check

  String get studentsCollection => "groups/$_myGroupId/students";
  String get visitedReportsCollection => "groups/$_myGroupId/visited_reports";

  // تم نقل دوال حفظ التقرير إلى صفحة AttendanceTypeSelectorPage (حضور)
  // بينما تم نقل "حفظ الافتقاد" إلى هنا (VisitedPage)

  // -------------------------------------------------------------------------
  // ## دوال حفظ تقارير الافتقاد لجميع السنوات
  // -------------------------------------------------------------------------

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showManualSaveDialogForAllGrades() async {
    _weekNameController.text = 'visit_report_weekly'
        .tr(context)
        .replaceFirst('%s', DateFormat('yyyy-MM-dd').format(_selectedDate));

    String savingStatus = 'preparing_status'.tr(context);

    await showDialog(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('save_stats_all_years'.tr(context)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_canWrite)
                    Text(
                      'subscription_read_only_warning'.tr(context),
                      style: const TextStyle(color: Colors.red),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    enabled: _canWrite,
                    controller: _weekNameController,
                    decoration: InputDecoration(
                      labelText: 'unified_report_name'.tr(context),
                      hintText: 'example_report_name'.tr(context),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text("${'report_date'.tr(context)}:"),
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
                                          'visit_report_weekly'
                                              .tr(context)
                                              .replaceFirst(
                                                '%s',
                                                DateFormat(
                                                  'yyyy-MM-dd',
                                                ).format(_selectedDate),
                                              );
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'save_stats_warning'.tr(context),
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
                        if (await _checkInternet() == false) {
                          return;
                        }

                        if (_weekNameController.text.trim().isEmpty) {
                          return;
                        }

                        setDialogState(() => _isSaving = true);
                        await _saveAllGradesStatsAndReset(
                          _weekNameController.text.trim(),
                          _selectedDate,
                          (status) {
                            if (context.mounted) {
                              setDialogState(() => savingStatus = status);
                            }
                          },
                        );
                        setDialogState(() => _isSaving = false);

                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
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
                    : Text('save_and_reset_all'.tr(context)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveAllGradesStatsAndReset(
    String weekName,
    DateTime selectedDate,
    Function(String) onProgress,
  ) async {
    if (!_canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('subscription_expired'.tr(context))),
      );
      return;
    }
    setState(() => _isSaving = true);
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final formattedDateTime = DateFormat(
      'yyyy-MM-dd_HH-mm-ss',
    ).format(DateTime.now());
    final reportDocumentId = "Report_$formattedDateTime";

    final currentUser = await UserService().getCurrentUserName();
    if (!mounted) return;

    // { "Grade Name": { "visited": [...], "unvisited": [...], "stats": {...} } }
    final Map<String, dynamic> fullReportData = {};
    final List<Map<String, dynamic>> summaryData =
        []; // For legacy/quick view if needed

    int totalOverall = 0;
    int visitedOverall = 0;

    try {
      final allGrades = await _gradeService.getGrades();
      if (!mounted) return;
      final List<String> allVisitedIdsToReset =
          []; // 🚀 القائمة المُجمعة لكل معرفات المخدومين المطلوب تصفيرهم

      for (int gIndex = 0; gIndex < allGrades.length; gIndex++) {
        final grade = allGrades[gIndex];
        if (!mounted) {
          return;
        }
        final gatheringDataMsg = 'gathering_grade_data'.tr(context);
        onProgress(
          "$gatheringDataMsg $grade (${gIndex + 1}/${allGrades.length})...",
        );

        final List<Map<String, dynamic>> visitedKids = [];
        final List<Map<String, dynamic>> unvisitedKids = [];

        String? lastId;
        bool hasMore = true;

        while (hasMore) {
          List<String> queries = [
            Query.equal('groupId', _myGroupId),
            Query.equal('grade', grade),
            Query.limit(100), // Process in chunks of 100
          ];
          if (lastId != null) {
            queries.add(Query.cursorAfter(lastId));
          }

          final result = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: studentsCollectionId,
            queries: queries,
          );

          if (result.documents.isEmpty) {
            hasMore = false;
            break;
          }

          lastId = result.documents.last.$id;

          for (var doc in result.documents) {
            final data = doc.data;
            final bool isVisited = data['isVisited'] ?? false;
            final String name = data['name'] ?? '';
            final String visitedBy = data['visitedBy'] ?? '';
            final String address = data['address'] ?? '';
            // Only store essential fields to save memory
            final String? phoneRequired = data['phoneRequired'];

            final kidData = {
              "name": name,
              "address": address,
              "phoneRequired": phoneRequired,
            };

            if (isVisited) {
              visitedKids.add({
                ...kidData,
                "visitedBy": visitedBy.isNotEmpty ? visitedBy : currentUser,
              });
              allVisitedIdsToReset.add(
                doc.$id,
              ); // 🚀 تجميع المعرفات هنا بدلاً من تصفيرها فوراً
            } else {
              unvisitedKids.add(kidData);
            }
          }

          if (result.documents.length < 100) {
            hasMore = false;
          }
        } // End while loop

        final int currentGradeTotal = visitedKids.length + unvisitedKids.length;
        final int currentGradeVisited = visitedKids.length;

        totalOverall += currentGradeTotal;
        visitedOverall += currentGradeVisited;

        final double percentage = currentGradeTotal == 0
            ? 0.0
            : (currentGradeVisited / currentGradeTotal) * 100;

        // Add to Full Report Data
        fullReportData[grade] = {
          "visited": visitedKids,
          "unvisited": unvisitedKids,
          "stats": {
            "total": currentGradeTotal,
            "visitedCount": currentGradeVisited,
            "percentage": percentage,
          },
        };

        // Add to summary (lightweight)
        summaryData.add({
          "grade": grade,
          "total": currentGradeTotal,
          "visitedCount": currentGradeVisited,
          "percentage": percentage,
        });
      }

      if (!mounted) {
        return;
      }
      // Save Report File
      onProgress('uploading_report_file'.tr(context));
      String fileId = '';
      try {
        final jsonString = jsonEncode(fullReportData);
        final fileData = InputFile.fromBytes(
          bytes: utf8.encode(jsonString),
          filename:
              'visit_report_${DateTime.now().millisecondsSinceEpoch}.json',
        );

        // Reuse the same attendance bucket
        final uploadedFile = await AppwriteService().storage.createFile(
          bucketId: AppwriteService.attendanceBucketId,
          fileId: ID.unique(),
          file: fileData,
        );
        fileId = uploadedFile.$id;
      } catch (e) {
        debugPrint("Error uploading visit report file: $e");
        if (!mounted) {
          throw Exception("Component unmounted during upload");
        }
        throw Exception("${'upload_report_failed'.tr(context)}: $e");
      }

      if (!mounted) {
        return;
      }
      onProgress('saving_report_record'.tr(context));
      // Save the main report document
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: visitedReportsCollectionId,
        documentId: reportDocumentId,
        data: {
          "groupId": _myGroupId,
          "reportName": weekName,
          "date": formattedDate,
          "timestamp": DateTime.now().toIso8601String(),
          "resetBy": currentUser,
          "totalOverall": totalOverall,
          "visitedOverall": visitedOverall,
          "overallPercentage": totalOverall == 0
              ? 0.0
              : (visitedOverall / totalOverall) * 100,
          "summary": summaryData.map((s) => jsonEncode(s)).toList(),
          "fileId": fileId, // New field
        },
        permissions: _teamId != null
            ? [
                Permission.read(Role.team(_teamId!)),
                Permission.update(Role.team(_teamId!)),
                Permission.delete(Role.team(_teamId!)),
              ]
            : null,
      );

      // 🚀 الخطوة الأخيرة والأهم: التصفير لا يحدث إلا بعد نجاح الحفظ تماماً
      if (allVisitedIdsToReset.isNotEmpty) {
        if (!mounted) {
          return;
        }
        onProgress('resetting_visitation_status'.tr(context));
        const int batchSize = 5;
        for (var i = 0; i < allVisitedIdsToReset.length; i += batchSize) {
          final end = (i + batchSize < allVisitedIdsToReset.length)
              ? i + batchSize
              : allVisitedIdsToReset.length;
          final batch = allVisitedIdsToReset.sublist(i, end);

          if (allVisitedIdsToReset.length > 20) {
            if (!mounted) {
              return;
            }
            onProgress(
              "${'resetting_data'.tr(context)} (${i + batch.length}/${allVisitedIdsToReset.length})...",
            );
          }

          try {
            await Future.wait(
              batch.map(
                (docId) => _databases.updateDocument(
                  databaseId: databaseId,
                  collectionId: studentsCollectionId,
                  documentId: docId,
                  data: {
                    'isVisited': false,
                    'visitedBy': '',
                    'timestamp': DateTime.now().toIso8601String(),
                  },
                ),
              ),
            );
          } catch (e) {
            debugPrint("Error resetting visit status for batch: $e");
            // لن نمنع إكمال باقي العملية إن فشل تحديث وثيقة واحدة
          }

          // Throttle
          if (end < allVisitedIdsToReset.length) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'save_report_success'.tr(context).replaceFirst('%s', weekName),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error in _saveAllGradesStatsAndReset: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${'general_save_failed'.tr(context)}: $e"),
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

  @override
  void initState() {
    super.initState();
    _gradeService = GradeService(groupId: '');
    _realtime = Realtime(_client);
    _fetchUserData();
    // Grades will be fetched after we have a groupId
  }

  @override
  void dispose() {
    _userSubscription?.close();
    _gradesSubscription?.cancel(); // 🚀 Cancel grades subscription
    _weekNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    // 🚀 1. Cache First (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        if (mounted) {
          setState(() {
            _myGroupId = cachedCtx['groupId']!;
            _isAdmin =
                cachedCtx['role'] == 'admin' ||
                cachedCtx['role'] == 'super_admin';
            _isLoadingRole = false;
            _gradeService = GradeService(groupId: _myGroupId);
          });
          _canWrite = await PermissionService.canWrite(_myGroupId);
          if (mounted) setState(() {});
          if (_myGroupId.isNotEmpty) _setupGradesStream();
        }
      }
    } else {
      // Global fallback
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        if (mounted) {
          setState(() {
            _myGroupId = lastData['groupId'];
            _isAdmin =
                lastData['role'] == 'admin' ||
                lastData['role'] == 'super_admin';
            _isLoadingRole = false;
            _gradeService = GradeService(groupId: _myGroupId);
          });
          _canWrite = await PermissionService.canWrite(_myGroupId);
          if (mounted) setState(() {});
          if (_myGroupId.isNotEmpty) _setupGradesStream();
        }
      }
    }

    // 🚀 2. Background Refresh
    try {
      final user = await _account.get();
      await UserService().getCurrentUser(); // Cache ID

      final cachedCtx = await DataCacheService().getCachedUserGroupId(user.$id);
      if (cachedCtx != null) {
        // Redundant but safe check if network fetch succeeds
        // Logic similar to initial check
        if (mounted) {
          _teamId = cachedCtx['teamId'];
        }
      }

      try {
        final uDoc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: usersCollectionId,
          documentId: user.$id,
        );

        // Update Cache with fresh data to correct any invalid stored session
        await DataCacheService().cacheUserGroupId(
          user.$id,
          uDoc.data['groupId'],
          uDoc.data['teamId'],
          uDoc.data['role'],
        );

        _updateState(uDoc.data);
      } catch (e) {
        debugPrint("Error fetching live user doc: $e");
      }

      _userSubscription?.close();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);

      _userSubscription!.stream.listen((event) {
        if (mounted) {
          final data = event.payload;
          _updateState(data);
        }
      });
    } catch (e) {
      debugPrint("Network fetch failed (offline): $e");
      if (mounted && _myGroupId.isEmpty) {
        // Only stop loading if we truly have nothing
        setState(() => _isLoadingRole = false);
      }
    }
  }

  void _updateState(Map<String, dynamic> data) {
    if (mounted) {
      setState(() {
        final newGroupId = data['groupId'] ?? '';
        final role = data['role'] ?? 'user';
        _isAdmin = role == 'admin' || role == 'super_admin';
        _isLoadingRole = false;

        if (newGroupId != _myGroupId) {
          _myGroupId = newGroupId;
          _gradeService = GradeService(groupId: _myGroupId);
          if (_myGroupId.isNotEmpty) _setupGradesStream();
        }
        _teamId = data['teamId'];
      });
    }
  }

  // 🚀 New Method to Handle Grades with Cache + Stream
  Future<void> _setupGradesStream() async {
    // 1. Initial Cache Load
    final cachedGrades = await DataCacheService().getCachedGrades(_myGroupId);
    if (cachedGrades.isNotEmpty) {
      if (mounted) {
        setState(() {
          _grades = cachedGrades;
          _isLoadingGrades = false;
        });
      }
    }

    // 2. Subscribe to Stream (which typically fetches fresh data too)
    _gradesSubscription?.cancel();
    _gradesSubscription = _gradeService.getGradesStream().listen(
      (grades) {
        if (mounted) {
          setState(() {
            _grades = grades;
            _isLoadingGrades = false;
          });
          // Update Cache
          DataCacheService().cacheGrades(_myGroupId, grades);
        }
      },
      onError: (e) {
        debugPrint("Error in grades stream: $e");
        if (mounted && _grades.isEmpty) {
          setState(() => _isLoadingGrades = false);
        }
      },
    );
  }

  Future<void> _showAddGradeDialog() async {
    if (!_canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('subscription_expired'.tr(context))),
      );
      return;
    }
    final TextEditingController gradeController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('add_new_grade_title'.tr(context)),
        content: TextField(
          controller: gradeController,
          decoration: InputDecoration(hintText: 'grade_name_hint'.tr(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newGrade = gradeController.text.trim();
              if (newGrade.isNotEmpty) {
                if (!_canWrite) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('subscription_expired'.tr(context))),
                  );
                  return;
                }

                // Optimistic Update
                if (mounted) {
                  setState(() {
                    _grades.add(newGrade);
                    _isLoadingGrades = false;
                  });
                  DataCacheService().cacheGrades(_myGroupId, _grades);
                }

                try {
                  await _gradeService.addGrade(newGrade);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  debugPrint("Add grade error: $e. Saving pending.");
                  DataCacheService().addPendingOperation({
                    'type': 'add_grade',
                    'data': {'groupId': _myGroupId, 'name': newGrade},
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              }
            },
            child: Text('add'.tr(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDeleteDialog(String currentName) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${'edit_delete'.tr(context)}: $currentName"),
        content: Text('edit_delete_warning'.tr(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr(context)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _showRenameDialog(currentName);
            },
            child: Text(
              'edit_name'.tr(context),
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('warning_final_delete_title'.tr(context)),
                  content: Text('delete_grade_confirm'.tr(context)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('cancel'.tr(context)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('yes_delete_all'.tr(context)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                if (!_canWrite) {
                  return;
                }

                // Optimistic Update
                if (mounted) {
                  setState(() {
                    _grades.remove(currentName);
                  });
                  DataCacheService().cacheGrades(_myGroupId, _grades);
                }

                try {
                  // 1. Delete all students & their data first
                  // For a clean offline experience, we might want to skip the graduateStudents if offline
                  // or queue it. But graduateStudents involves listing all students.
                  // Let's assume delete grade also cleans up or we queue the delete action.

                  // Use a dummy callback for now since we are in a dialog without progress bar
                  await _graduateStudents(currentName, (_) {});
                  await _gradeService.deleteGrade(currentName);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                } catch (e) {
                  debugPrint("Delete grade error: $e. Saving pending.");
                  DataCacheService().addPendingOperation({
                    'type': 'delete_grade',
                    'data': {'groupId': _myGroupId, 'name': currentName},
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('deleted_locally'.tr(context))),
                    );
                    Navigator.pop(context);
                  }
                }
              }
            },
            child: Text('delete'.tr(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(String oldName) async {
    if (!_canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('subscription_expired'.tr(context))),
      );
      return;
    }
    final TextEditingController renameController = TextEditingController(
      text: oldName,
    );
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('change_grade_name'.tr(context)),
        content: TextField(
          controller: renameController,
          decoration: InputDecoration(labelText: 'new_name'.tr(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = renameController.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                if (!_canWrite) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('subscription_expired'.tr(context))),
                  );
                  return;
                }

                // Optimistic Update
                if (mounted) {
                  setState(() {
                    final index = _grades.indexOf(oldName);
                    if (index != -1) _grades[index] = newName;
                  });
                  DataCacheService().cacheGrades(_myGroupId, _grades);
                }

                try {
                  await _gradeService.updateGradeName(oldName, newName);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  debugPrint("Rename grade error: $e. Saving pending.");
                  DataCacheService().addPendingOperation({
                    'type': 'rename_grade',
                    'data': {
                      'groupId': _myGroupId,
                      'oldName': oldName,
                      'newName': newName,
                    },
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('edited_locally'.tr(context))),
                    );
                    Navigator.pop(context);
                  }
                }
              }
            },
            child: Text('save'.tr(context)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // ## دوال ترحيل المراحل
  // -------------------------------------------------------------------------

  Future<void> _showPromotionDialog() async {
    final passwordController = TextEditingController();
    bool isProcessing = false;
    String statusMessage = 'preparing'.tr(context);
    double progressValue = 0.0;

    await showDialog(
      context: context,
      barrierDismissible: !isProcessing,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('promotion_graduation_title'.tr(context)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_canWrite)
                    Text(
                      'subscription_read_only_warning'.tr(context),
                      style: const TextStyle(color: Colors.red),
                    ),
                  const SizedBox(height: 8),
                  Text('promotion_description'.tr(context)),
                  const SizedBox(height: 8),
                  Text(
                    'promotion_warning'.tr(context),
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!isProcessing)
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'confirmation_pin'.tr(context),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  if (isProcessing) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progressValue),
                    const SizedBox(height: 8),
                    Text(
                      statusMessage,
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!isProcessing)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('cancel'.tr(context)),
                ),
              if (!isProcessing)
                ElevatedButton(
                  onPressed: (isProcessing || !_canWrite)
                      ? null
                      : () async {
                          if (!_canWrite || await _checkInternet() == false) {
                            return;
                          }

                          if (!context.mounted) return;

                          if (passwordController.text != _promotionPassword) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('incorrect_pin'.tr(context)),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isProcessing = true;
                            statusMessage = 'starting_process'.tr(context);
                            progressValue = 0.0;
                          });

                          await _performStudentPromotion((msg, val) {
                            if (context.mounted) {
                              setDialogState(() {
                                statusMessage = msg;
                                progressValue = val;
                              });
                            }
                          });

                          if (context.mounted) {
                            setDialogState(() => isProcessing = false);
                            Navigator.of(context).pop();
                          }
                        },
                  child: Text('promote_and_confirm'.tr(context)),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _performStudentPromotion(
    Function(String, double) onProgress,
  ) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('subscription_expired'.tr(context))),
        );
      }
      return;
    }

    try {
      final grades = await _gradeService.getGrades();
      if (!mounted) return;
      if (grades.isEmpty) {
        if (!mounted) {
          throw Exception("Component unmounted during promotion check");
        }
        throw Exception('no_grades_to_promote'.tr(context));
      }

      final totalSteps =
          grades.length; // 1 step for graduation + N-1 promotions
      double currentStep = 0;

      // 1. تخرج الدفعة الأخيرة
      final lastGrade = grades.last;
      if (!mounted) {
        return;
      }
      onProgress("${'graduating_batch'.tr(context)} $lastGrade...", 0.1);

      await _graduateStudents(lastGrade, (msg) {
        onProgress(msg, (currentStep / totalSteps) + 0.05);
      });

      currentStep++;
      if (!mounted) {
        return;
      }
      onProgress(
        'batch_graduated_success'.tr(context),
        currentStep / totalSteps,
      );

      // 2. ترحيل الفصول المتبقية
      for (int i = grades.length - 2; i >= 0; i--) {
        final fromGrade = grades[i];
        final toGrade = grades[i + 1];

        if (!mounted) {
          return;
        }
        onProgress(
          "${'promoting_from_to'.tr(context).replaceFirst('%s1', fromGrade).replaceFirst('%s2', toGrade)}...",
          currentStep / totalSteps,
        );

        await _updateStudentGrade(fromGrade, toGrade, (msg) {
          onProgress(msg, (currentStep / totalSteps) + 0.05);
        });

        currentStep++;
      }

      if (!mounted) {
        return;
      }
      onProgress('process_completed_success'.tr(context), 1.0);
      await Future.delayed(const Duration(seconds: 1)); // Show 100% briefly

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('promotion_graduation_success'.tr(context)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${'promotion_failed'.tr(context)}: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _graduateStudents(
    String grade,
    Function(String) onStatus,
  ) async {
    String? lastId;
    bool hasMore = true;
    int totalDeleted = 0;

    // First ensure we can fetch something to check count roughly or just iterate
    while (hasMore) {
      List<String> queries = [
        Query.equal('groupId', _myGroupId),
        Query.equal('grade', grade),
        Query.limit(100), // Fetch 100 at a time
      ];

      if (lastId != null) {
        queries.add(Query.cursorAfter(lastId));
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: queries,
      );

      if (result.documents.isEmpty) {
        hasMore = false;
        break;
      }

      lastId = result.documents.last.$id;
      final docs = result.documents;

      // Process this chunk of 100 docs
      // Use concurrency control: Process 5 at a time
      const int concurrentDeletes = 5;
      for (var i = 0; i < docs.length; i += concurrentDeletes) {
        final end = (i + concurrentDeletes < docs.length)
            ? i + concurrentDeletes
            : docs.length;
        final batch = docs.sublist(i, end);

        final futures = batch.map((doc) async {
          final String kidId = doc.$id;
          final String kidName = doc.data['name'] ?? '';
          final String? photoUrl = doc.data['photoUrl'];
          final imageService = ImageService();

          // 1. Delete student profile photo
          if (photoUrl != null && photoUrl.isNotEmpty) {
            try {
              await imageService.deleteImageByUrl(photoUrl);
            } catch (_) {}
          }

          // 2. Delete individual visit records
          // (This part might still be query heavy, so we should be careful.
          //  If a student has MANY visits, this could slow down.
          //  Optimization: Fire and forget or simple limit)
          if (kidName.isNotEmpty) {
            try {
              final visitsResult = await _databases.listDocuments(
                databaseId: databaseId,
                collectionId: 'individual_visits',
                queries: [
                  Query.equal('groupId', _myGroupId),
                  Query.equal('kidName', kidName),
                  Query.limit(100), // Limit deletion overhead
                ],
              );

              for (var visitDoc in visitsResult.documents) {
                // Delete images first
                final List<dynamic> publicIds =
                    visitDoc.data['publicIds'] ?? [];
                for (var id in publicIds) {
                  if (id is String) {
                    try {
                      await imageService.deleteImage(id);
                    } catch (_) {}
                  }
                }
                await _databases.deleteDocument(
                  databaseId: databaseId,
                  collectionId: 'individual_visits',
                  documentId: visitDoc.$id,
                );
              }
            } catch (_) {}
          }

          // 3. Delete student doc
          await _databases.deleteDocument(
            databaseId: databaseId,
            collectionId: studentsCollectionId,
            documentId: kidId,
          );
        });

        await Future.wait(futures);
        if (!mounted) return;
        totalDeleted += batch.length;

        if (totalDeleted % 10 == 0) {
          onStatus(
            "${'graduated_grade'.tr(context).replaceFirst('%s', grade)}: ${'deleted_students_count'.tr(context).replaceFirst('%s', totalDeleted.toString())}...",
          );
        }

        // Throttling to protect server
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Safety brake if needed, but pagination handles it
    }

    debugPrint("Graduated $totalDeleted students from $grade.");
  }

  Future<void> _updateStudentGrade(
    String fromGrade,
    String toGrade,
    Function(String) onStatus,
  ) async {
    String? lastId;
    bool hasMore = true;
    int totalPromoted = 0;

    while (hasMore) {
      List<String> queries = [
        Query.equal('groupId', _myGroupId),
        Query.equal('grade', fromGrade),
        Query.limit(100),
      ];

      if (lastId != null) {
        queries.add(Query.cursorAfter(lastId));
      }

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: queries,
      );

      if (result.documents.isEmpty) {
        hasMore = false;
        break;
      }

      lastId = result.documents.last.$id;
      final docs = result.documents;

      // Update in batches of 10
      const int batchSize = 10;
      for (var i = 0; i < docs.length; i += batchSize) {
        final end = (i + batchSize < docs.length) ? i + batchSize : docs.length;
        final batch = docs.sublist(i, end);

        final futures = batch.map(
          (doc) => _databases.updateDocument(
            databaseId: databaseId,
            collectionId: studentsCollectionId,
            documentId: doc.$id,
            data: {'grade': toGrade},
          ),
        );

        await Future.wait(futures);
        if (!mounted) return;
        totalPromoted += batch.length;

        onStatus(
          "${'promoted_students_count_from_to'.tr(context).replaceFirst('%s0', totalPromoted.toString()).replaceFirst('%s1', fromGrade).replaceFirst('%s2', toGrade)}...",
        );

        // Throttle
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    debugPrint("Promoted $totalPromoted students from $fromGrade to $toGrade.");
  }

  // تم نقل دوال حفظ التقرير إلى صفحة AttendanceTypeSelectorPage (تمت الإعادة)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('visit'.tr(context)),
        actions: [
          if (_isAdmin) ...[
            IconButton(
              icon: Icon(
                Icons.save,
                color: _canWrite ? Colors.green : Colors.grey,
              ),
              tooltip: _canWrite
                  ? 'save_visit_stats_all'.tr(context)
                  : 'subscription_expired'.tr(context),
              onPressed: _showManualSaveDialogForAllGrades,
            ),
            IconButton(
              icon: Icon(
                Icons.school,
                color: _canWrite ? Colors.blue : Colors.grey,
              ),
              tooltip: _canWrite
                  ? 'promote_students'.tr(context)
                  : 'subscription_expired'.tr(context),
              onPressed: _showPromotionDialog,
            ),
          ],
        ],
      ),
      floatingActionButton: (_isAdmin && _canWrite)
          ? FloatingActionButton(
              onPressed: _showAddGradeDialog,
              tooltip: 'add_new_grade'.tr(context),
              child: const Icon(Icons.add),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Center(
            child: _isLoadingRole || (_isLoadingGrades && _grades.isEmpty)
                ? const CircularProgressIndicator()
                : _grades.isEmpty
                ? Text(
                    'no_grades_added_yet'.tr(context),
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    itemCount: _grades.length,
                    itemBuilder: (context, index) {
                      final grade = _grades[index];
                      return Container(
                        width: MediaQuery.of(context).size.width * 0.8,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        child: Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            title: Center(
                              child: Text(
                                grade,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            onLongPress: (_isAdmin && _canWrite)
                                ? () => _showEditDeleteDialog(grade)
                                : null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => KidsListPage(grade: grade),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
