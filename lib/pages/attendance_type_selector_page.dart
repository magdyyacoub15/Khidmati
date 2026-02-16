import 'package:flutter/material.dart';
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

class AttendanceTypeSelectorPage extends StatefulWidget {
  const AttendanceTypeSelectorPage({super.key});

  @override
  State<AttendanceTypeSelectorPage> createState() =>
      _AttendanceTypeSelectorPageState();
}

class _AttendanceTypeSelectorPageState
    extends State<AttendanceTypeSelectorPage> {
  late GradeService _gradeService;
  bool _isAdmin = false;
  bool _canWrite = true; // 🚀 Subscription Check
  bool _isLoadingRole = true;
  String _myGroupId = '';

  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = Realtime(AppwriteService().client);
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
        _applyUserData(cachedCtx['groupId']!, cachedCtx['role'] == 'admin');
      }
    } else {
      // Try global fallback if specific user cache not found
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        _applyUserData(lastData['groupId'], lastData['role'] == 'admin');
      }
    }

    // 🚀 2. Background Network Refresh (Silent)
    try {
      final user = await _account.get();
      final userId = user.$id;
      // Cache ID for next time
      await UserService().getCurrentUser();

      // Check specific cache again with fresh ID just in case
      // (logic inside _handleUserUpdate updates cache)
      await _handleUserUpdate(userId);

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
        }
        _isLoadingRole = false;
      });
    }
  }

  Future<void> _handleUserUpdate(String userId) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
      );

      // Update Cache
      await DataCacheService().cacheUserGroupId(
        userId,
        doc.data['groupId'],
        doc.data['teamId'],
        doc.data['role'],
      );

      _updateState(doc.data);
    } catch (e) {
      debugPrint("Error fetching user doc: $e");
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  void _updateState(Map<String, dynamic> data) async {
    final canWrite = await PermissionService.canWrite(data['groupId'] ?? '');
    if (mounted) {
      setState(() {
        _myGroupId = data['groupId'] ?? '';
        _isAdmin = (data['role'] == 'admin');
        _canWrite = canWrite;
        if (_myGroupId.isNotEmpty) {
          _gradeService = GradeService(groupId: _myGroupId);
        }
        _isLoadingRole = false;
      });
    }
  }

  Future<void> _saveAndResetBothTypes(
    String reportName,
    DateTime selectedDate,
  ) async {
    if (!_canWrite) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("⚠️ انتهت صلاحية الاشتراك")));
      return;
    }
    try {
      await _saveReportForType(reportName, selectedDate, "خدام");
      await _saveReportForType(reportName, selectedDate, "مخدومين");

      // 💡 تحديث التوصيات الذكية تلقائياً بعد حفظ التقرير الموحد
      if (_myGroupId.isNotEmpty) {
        await AIInsightService(groupId: _myGroupId).generateInsights();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ تم حفظ تقرير '$reportName' للخدام والمخدومين وإعادة التعيين بنجاح",
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ حدث خطأ أثناء الحفظ الموحد: $e"),
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

  Future<void> _saveReportForType(
    String reportName,
    DateTime selectedDate,
    String type,
  ) async {
    // 1. Get all grades
    final allGrades = await _gradeService.getGrades();

    // We will collect data for all grades in this map
    // Structure: GradeName -> List of Kid Maps
    final Map<String, List<Map<String, dynamic>>> fullReportData = {};

    int totalOverall = 0;
    int presentOverall = 0;

    // Determine collections
    final String collectionId = (type == "خدام") ? 'servants' : 'students';

    // 2. Iterate grades to build report
    for (String grade in allGrades) {
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

      // 3. Delete/Reset status for this grade
      // We only delete the documents we fetched in statusResult
      for (var doc in statusResult.documents) {
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: attendanceStatusCollectionId,
          documentId: doc.$id,
        );
      }
    }

    // 4. Save Report
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final user = await _account.get();
    final currentUserName = user.name;

    await _databases.createDocument(
      databaseId: databaseId,
      collectionId: attendanceRecordsCollectionId,
      documentId: ID.unique(),
      data: {
        'reportName': reportName,
        'date':
            formattedDate, // Storing as string for query simplicity or ISO? Original was string
        'timestamp': DateTime.now().toIso8601String(),
        'resetBy': currentUserName,
        'type': type,
        'totalOverall': totalOverall,
        'presentOverall': presentOverall,
        'overallPercentage': totalOverall == 0
            ? 0.0
            : (presentOverall / totalOverall) * 100,
        'groupId': _myGroupId,
        'data': jsonEncode(
          fullReportData,
        ), // Store detailed data as JSON string
      },
    );
  }

  Future<void> _showManualSaveDialog() async {
    _selectedDate = DateTime.now();
    _weekNameController.text =
        "تقرير حضور ${DateFormat('yyyy-MM-dd').format(_selectedDate)}";

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("حفظ التقرير وإعادة التعيين"),
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
                      child: const Text(
                        "⚠️ انتهت صلاحية الاشتراك. لا يمكنك حفظ تقارير جديدة.",
                        style: TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _weekNameController,
                    decoration: const InputDecoration(
                      labelText: "اسم التقرير الموحد",
                      hintText: "مثال: تقرير حضور شهر سبتمبر",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text("تاريخ التقرير:"),
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
                                          "تقرير حضور ${DateFormat('yyyy-MM-dd').format(_selectedDate)}";
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
                    child: const Text(
                      "⚠️ سيتم حفظ وتصفير حالات الحضور للخدام والمخدومين بجميع الصفوف.",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: (_isSaving || !_canWrite)
                    ? null
                    : () async {
                        if (_weekNameController.text.trim().isEmpty) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("⚠️ يرجى إدخال اسم التقرير"),
                              ),
                            );
                          }
                          return;
                        }

                        setDialogState(() => _isSaving = true);
                        await _saveAndResetBothTypes(
                          _weekNameController.text.trim(),
                          _selectedDate,
                        );
                        setDialogState(() => _isSaving = false);
                        if (context.mounted) Navigator.pop(context);
                      },
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text("حفظ"),
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
        title: const Text("اختيار نوع الحضور"),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: Icon(
                Icons.save,
                color: _canWrite ? Colors.green : Colors.grey,
              ),
              tooltip: _canWrite ? "حفظ تقرير الحضور" : "انتهت صلاحية الاشتراك",
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
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person),
                    label: const Text("خدام"),
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
                              AttendanceGradeSelectorPage(type: "خدام"),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.child_care),
                    label: const Text("مخدومين"),
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
                              AttendanceGradeSelectorPage(type: "مخدومين"),
                        ),
                      );
                    },
                  ),
                ],
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
    );
  }
}
