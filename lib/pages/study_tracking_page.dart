import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';

import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import '../services/grade_service.dart';
import '../services/user_service.dart';
import '../services/permission_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/full_screen_image.dart';
import '../services/data_cache_service.dart';
import '../services/sync_service.dart';
import '../l10n/app_translations.dart';
import '../models/kid.dart';

// -----------------------------------------------------------------------------
// *********** APPWRITE CONFIGURATION & HELPERS **********
// -----------------------------------------------------------------------------

const String databaseId = 'main_db';
const String usersCollectionId = 'users_info';
const String studentsCollectionId = 'students';
const String subjectsCollectionId = 'subjects';
const String studyGradesCollectionId = 'study_grades';
const String gradesCollectionId = 'grades'; // For fetching year names

Color getRandomColor() {
  final random = Random();
  return Color.fromARGB(
    255,
    random.nextInt(256),
    random.nextInt(256),
    random.nextInt(256),
  );
}

Future<void> _makePhoneCall(String phoneNumber) async {
  final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
  if (await canLaunchUrl(launchUri)) {
    await launchUrl(launchUri);
  } else {
    throw 'Could not launch $launchUri';
  }
}

// -----------------------------------------------------------------------------
// ****************************** DATA MODELS **********************************
// -----------------------------------------------------------------------------

class ChartData {
  final String id;
  final String exam;
  final double grade;
  final double maxGrade;
  final Color color;
  final String? createdBy;
  final DateTime? date;

  ChartData(
    this.id,
    this.exam,
    this.grade,
    this.maxGrade,
    this.color, {
    this.createdBy,
    this.date,
  });

  factory ChartData.fromAppwrite(models.Document doc) {
    final Map<String, dynamic> data = doc.data;
    DateTime? date;
    if (data['date'] != null) {
      date = DateTime.tryParse(data['date']);
    } else if (doc.$createdAt.isNotEmpty) {
      date = DateTime.parse(doc.$createdAt);
    }

    return ChartData(
      doc.$id,
      data['exam'] as String? ?? 'N/A',
      (data['grade'] as num?)?.toDouble() ?? 0.0,
      (data['maxGrade'] as num?)?.toDouble() ?? 100.0,
      getRandomColor(),
      createdBy: data['createdBy'] as String?,
      date: date,
    );
  }

  double get percentage => maxGrade > 0 ? (grade / maxGrade) * 100 : 0;
}

// -----------------------------------------------------------------------------
// ****************************** MAIN PAGES ***********************************
// -----------------------------------------------------------------------------

class StudyTrackingPage extends StatefulWidget {
  const StudyTrackingPage({super.key});

  @override
  State<StudyTrackingPage> createState() => _StudyTrackingPageState();
}

class _StudyTrackingPageState extends State<StudyTrackingPage> {
  String _myGroupId = '';
  RealtimeSubscription? _userSubscription;
  bool _isLoading = true;

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Realtime _realtime = AppwriteService().realtime;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // 🚀 1. Try to load from cache IMMEDIATELY (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        if (mounted) {
          _updateState(cachedCtx);
        }
      } else {
        final fallbackData = await DataCacheService().getCachedUserData();
        if (fallbackData != null) {
          _updateState(fallbackData);
        }
      }
    } else {
      final fallbackData = await DataCacheService().getCachedUserData();
      if (fallbackData != null) {
        _updateState(fallbackData);
      }
    }

    // 🚀 2. Background Network Refresh (Silent)
    try {
      final user = await _account.get();
      final userId = user.$id;

      try {
        final doc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: usersCollectionId,
          documentId: userId,
        );

        await DataCacheService().cacheUserGroupId(
          userId,
          doc.data['groupId'] ?? '',
          doc.data['teamId'],
          doc.data['role'] ?? '',
        );
        await DataCacheService().cacheUserData(doc.data);

        if (mounted) _updateState(doc.data);
      } catch (e) {
        debugPrint("Error fetching user data: $e");
      }

      // Realtime Listener
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
      debugPrint("Offline mode active or error in _loadUserData: $e");
      if (mounted && _myGroupId.isEmpty) setState(() => _isLoading = false);
    }
  }

  void _updateState(Map<String, dynamic> data) {
    if (mounted) {
      setState(() {
        _myGroupId = data['groupId'] ?? '';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _userSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('loading'.tr(context))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('study_classes'.tr(context)),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: GradesPage(groupId: _myGroupId),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ************************** SCHOOL TRACKING PAGES ****************************
// -----------------------------------------------------------------------------

class GradesPage extends StatefulWidget {
  final String groupId;
  const GradesPage({required this.groupId, super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  late GradeService _gradeService;

  @override
  void initState() {
    super.initState();
    _gradeService = GradeService(groupId: widget.groupId);
  }

  @override
  Widget build(BuildContext context) {
    return _GradesList(gradeService: _gradeService, groupId: widget.groupId);
  }
}

class _GradesList extends StatelessWidget {
  final GradeService gradeService;
  final String groupId;
  const _GradesList({required this.gradeService, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: gradeService.getGradesStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'error_loading_data'
                  .tr(context)
                  .replaceFirst('%s', snapshot.error.toString()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final grades = snapshot.data!;

        if (grades.isEmpty) {
          return Center(
            child: Text(
              'no_classes_added'.tr(context),
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
          );
        }

        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: grades.map((grade) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: _GradeCard(grade: grade, groupId: groupId),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _GradeCard extends StatelessWidget {
  final String grade;
  final String groupId;
  const _GradeCard({required this.grade, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (BuildContext context) => StudentsPage(
                  gradeId: grade,
                  gradeTitle: grade,
                  groupId: groupId,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    grade,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'tap_to_follow_students'.tr(context),
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudentsPage extends StatefulWidget {
  final String gradeId;
  final String gradeTitle;
  final String groupId;
  const StudentsPage({
    super.key,
    required this.gradeId,
    required this.gradeTitle,
    required this.groupId,
  });

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = AppwriteService().realtime;

  List<Kid> _students = [];
  bool _isLoading = true;
  bool _canWrite = true;
  RealtimeSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadCachedStudents(); // Load from cache first
    _fetchStudents();
    _subscribe();
    _checkPermissions();
  }

  Future<void> _loadCachedStudents() async {
    final cached = await DataCacheService().getCachedKidsList(
      widget.groupId,
      widget.gradeId,
    );
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _students = cached;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkPermissions() async {
    final canWrite = await PermissionService.canWrite(widget.groupId);
    if (mounted) setState(() => _canWrite = canWrite);
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  Future<void> _fetchStudents() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('grade', widget.gradeId),
          Query.limit(100),
        ],
      );
      final kids = result.documents
          .map((doc) => Kid.fromAppwrite(doc))
          .toList();

      if (mounted) {
        setState(() {
          _students = kids;
          _isLoading = false;
        });
        // 🚀 Cache for offline access
        DataCacheService().cacheKidsList(widget.groupId, widget.gradeId, kids);
      }
    } catch (e) {
      debugPrint("Error fetching students: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribe() {
    _subscription = _realtime.subscribe([
      'databases.$databaseId.collections.$studentsCollectionId.documents',
    ]);

    _subscription!.stream.listen((event) {
      if (event.payload['groupId'] == widget.groupId &&
          event.payload['grade'] == widget.gradeId) {
        _fetchStudents();
      }
    });
  }

  Future<void> _clearStudentData(String studentId, String studentName) async {
    try {
      final syncData = {'studentId': studentId};

      // 🚀 Offline Logic
      final bool online = await SyncService().isOnline();
      if (!online) {
        await DataCacheService().addPendingOperation({
          'type': 'study_student_data_clear',
          'data': syncData,
        });

        // Optimistic UI Update in Cache
        await DataCacheService().cacheStudySubjects(studentId, []);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('offline_saved'.tr(context))));
        }
        return;
      }

      // 1. Get Subjects
      final subjects = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        queries: [Query.equal('studentId', studentId), Query.limit(1000)],
      );

      // 2. Delete Subjects and Grades
      for (final subjectDoc in subjects.documents) {
        final subjectName = subjectDoc.data['name'];

        // Get Grades
        final grades = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: studyGradesCollectionId,
          queries: [
            Query.equal('studentId', studentId),
            Query.equal('subject', subjectName),
            Query.limit(1000),
          ],
        );

        // Delete Grades
        for (final gradeDoc in grades.documents) {
          await _databases.deleteDocument(
            databaseId: databaseId,
            collectionId: studyGradesCollectionId,
            documentId: gradeDoc.$id,
          );
        }

        // Delete Subject
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: subjectsCollectionId,
          documentId: subjectDoc.$id,
        );
      }

      // 3. Clear Cache
      await DataCacheService().cacheStudySubjects(studentId, []);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'student_data_deleted_success'
                  .tr(context)
                  .replaceFirst('%s', studentName),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'student_data_deleted_error'
                  .tr(context)
                  .replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  void _showClearStudentDataDialog(String studentId, String studentName) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('subscription_expired_warning'.tr(context))),
        );
      }
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('clear_student_data_title'.tr(context)),
        content: Text(
          'clear_student_data_desc'.tr(context).replaceFirst('%s', studentName),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel_btn'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearStudentData(studentId, studentName);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('clear_data'.tr(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.gradeTitle),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _students.isEmpty
            ? Center(
                child: Text(
                  'no_students_in_class'.tr(context),
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem(
                          Icons.people,
                          'total_students_count'.tr(context),
                          _students.length.toString(),
                        ),
                        _buildStatItem(
                          Icons.grade,
                          'grade_word'.tr(context),
                          widget.gradeTitle,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _fetchStudents,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final kid = _students[index];
                          return _StudentCard(
                            studentId: kid.id,
                            studentName: kid.name,
                            studentPhone: kid.phoneRequired ?? '',
                            studentData: kid.toMap(),
                            groupId: widget.groupId,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentDetailsPage(
                                  studentId: kid.id,
                                  studentName: kid.name,
                                  studentPhotoUrl: kid.photoUrl,
                                  groupId: widget.groupId,
                                ),
                              ),
                            ),
                            onClearData: () =>
                                _showClearStudentDataDialog(kid.id, kid.name),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String title, String value) {
    return Column(
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: MediaQuery.of(context).size.width * 0.05,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _StudentCard extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentPhone;
  final Map<String, dynamic> studentData;
  final VoidCallback onTap;
  final VoidCallback? onClearData;
  final String groupId;

  const _StudentCard({
    required this.studentId,
    required this.studentName,
    required this.studentPhone,
    required this.studentData,
    required this.onTap,
    required this.groupId,
    this.onClearData,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  final Databases _databases = AppwriteService().databases;
  int _subjectsCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSubjectsCount();
  }

  Future<void> _fetchSubjectsCount() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        queries: [Query.equal('studentId', widget.studentId)],
      );
      if (mounted) {
        setState(() {
          _subjectsCount = result.total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color countColor = _subjectsCount == 0
        ? Colors.red.shade700
        : _subjectsCount <= 2
        ? Colors.orange.shade700
        : Colors.green.shade700;
    final Color countBgColor = _subjectsCount == 0
        ? Colors.red.shade100
        : _subjectsCount <= 2
        ? Colors.orange.shade100
        : Colors.green.shade100;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _isLoading
            ? const CircularProgressIndicator()
            : SizedBox(
                width: 55,
                height: 55,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (widget.studentData['photoUrl'] != null &&
                            widget.studentData['photoUrl']
                                .toString()
                                .isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullScreenImage(
                                imageUrl: widget.studentData['photoUrl'],
                                tag:
                                    'study_tracking_student_${widget.studentId}',
                              ),
                            ),
                          );
                        }
                      },
                      child: Hero(
                        tag: 'study_tracking_student_${widget.studentId}',
                        child: CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage:
                              (widget.studentData['photoUrl'] != null &&
                                  widget.studentData['photoUrl']
                                      .toString()
                                      .isNotEmpty)
                              ? CachedNetworkImageProvider(
                                  widget.studentData['photoUrl'],
                                )
                              : null,
                          child:
                              (widget.studentData['photoUrl'] == null ||
                                  widget.studentData['photoUrl']
                                      .toString()
                                      .isEmpty)
                              ? Icon(Icons.person, color: Colors.grey.shade400)
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: countBgColor,
                        child: Text(
                          _subjectsCount.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: countColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        title: Text(
          widget.studentName,
          style: const TextStyle(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        subtitle: widget.studentPhone.isNotEmpty
            ? GestureDetector(
                onTap: () => _makePhoneCall(widget.studentPhone),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone, size: 16, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      widget.studentPhone,
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              )
            : Text('no_phone_found'.tr(context), textAlign: TextAlign.center),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onClearData != null && _subjectsCount > 0)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.orange),
                onPressed: widget.onClearData,
              ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: widget.onTap,
      ),
    );
  }
}

class StudentDetailsPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentPhotoUrl;
  final String groupId;
  const StudentDetailsPage({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentPhotoUrl,
    required this.groupId,
  });

  @override
  State<StudentDetailsPage> createState() => _StudentDetailsPageState();
}

class _StudentDetailsPageState extends State<StudentDetailsPage> {
  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = AppwriteService().realtime;

  List<models.Document> _subjects = [];
  bool _isLoading = true;
  bool _canWrite = true;
  String? _teamId;
  RealtimeSubscription? _subscription;
  String? _currentUserId;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadCachedSubjects();
    _fetchSubjects();
    _subscribe();
    _fetchTeamId();
    _checkPermissions();
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = await UserService().getCurrentUser();
      final name = await UserService().getCurrentUserName();
      if (mounted) {
        setState(() {
          _currentUserId = user?.$id;
          _currentUserName = name;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkPermissions() async {
    final canWrite = await PermissionService.canWrite(widget.groupId);
    if (mounted) setState(() => _canWrite = canWrite);
  }

  Future<void> _loadCachedSubjects() async {
    final cached = await DataCacheService().getCachedStudySubjects(
      widget.studentId,
    );
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _subjects = cached.map((m) => models.Document.fromMap(m)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTeamId() async {
    try {
      final groupDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'groups',
        documentId: widget.groupId,
      );
      if (mounted) {
        setState(() => _teamId = groupDoc.data['teamId']);
      }
    } catch (e) {
      debugPrint("Error fetching teamId: $e");
    }
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  Future<void> _fetchSubjects() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        queries: [
          Query.equal('studentId', widget.studentId),
          Query.orderDesc('\$createdAt'),
        ],
      );
      if (mounted) {
        setState(() {
          _subjects = result.documents;
          _isLoading = false;
        });
        // 🚀 Cache subjects securely using toMap()
        final cacheMaps = result.documents.map((doc) => doc.toMap()).toList();
        DataCacheService().cacheStudySubjects(widget.studentId, cacheMaps);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribe() {
    _subscription = _realtime.subscribe([
      'databases.$databaseId.collections.$subjectsCollectionId.documents',
    ]);

    _subscription!.stream.listen((event) {
      if (event.payload['studentId'] == widget.studentId) {
        _fetchSubjects();
      }
    });
  }

  Future<void> _addSubject(String name) async {
    final String docId = ID.unique(); // 🚀 Use consistent ID
    final Map<String, dynamic> subjectData = {
      'name': name,
      'studentId': widget.studentId,
      'studentName': widget.studentName,
      'type': 'school',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': _currentUserId ?? 'pending',
      'createdByName': _currentUserName ?? 'pending',
      'groupId': widget.groupId,
    };

    // 🚀 Optimistic UI: Add to local state immediately
    final Map<String, dynamic> tempDocData = Map.from(subjectData);
    tempDocData[r'$id'] = docId;

    final tempDoc = models.Document.fromMap(tempDocData);

    if (mounted) {
      setState(() {
        _subjects.insert(0, tempDoc);
      });
      // 🚀 Cache update
      DataCacheService().upsertStudySubjectInCache(
        widget.studentId,
        tempDocData,
      );
    }

    try {
      // 🚀 Offline Logic
      final bool online = await SyncService().isOnline();
      if (!online) {
        await DataCacheService().addPendingOperation({
          'type': 'add_study_subject',
          'data': {...subjectData, r'$id': docId, 'teamId': _teamId},
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('offline_saved'.tr(context))));
        }
        return;
      }

      final doc = await _databases.createDocument(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        documentId: docId, // 🚀 Use consistent docId
        data: subjectData,
        permissions: _teamId != null
            ? [
                Permission.read(Role.team(_teamId!)),
                Permission.update(Role.team(_teamId!)),
                Permission.delete(Role.team(_teamId!)),
              ]
            : null,
      );
      if (mounted) {
        // Replace temp doc with actual doc
        setState(() {
          final idx = _subjects.indexWhere((d) => d.$id == docId);
          if (idx != -1) _subjects[idx] = doc;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('add_subject_success'.tr(context))),
        );
        // Sync local cache with real ID
        DataCacheService().removeStudySubjectFromCache(widget.studentId, docId);
        final Map<String, dynamic> finalData = doc.toMap();
        DataCacheService().upsertStudySubjectInCache(
          widget.studentId,
          finalData,
        );
      }
    } catch (e) {
      debugPrint("Error adding subject: $e");
      // Rollback optimistic update
      if (mounted) {
        setState(() {
          _subjects.removeWhere((d) => d.$id == docId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'add_subject_error'.tr(context).replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteSubject(String subjectId, String createdBy) async {
    final bool canDelete = await PermissionService.canEditOrDelete(
      createdBy,
      widget.groupId,
    );
    if (!canDelete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('no_delete_permission'.tr(context))),
        );
      }
      return;
    }

    if (!mounted) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('delete_subject'.tr(context)),
            content: Text('delete_subject_warning'.tr(context)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('cancel_btn'.tr(context)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text('delete_btn'.tr(context)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    models.Document? deletedDoc;
    try {
      // 🚀 Optimistic UI: Remove from local state immediately
      if (mounted) {
        setState(() {
          final idx = _subjects.indexWhere((d) => d.$id == subjectId);
          if (idx != -1) {
            deletedDoc = _subjects.removeAt(idx);
          }
        });
        // 🚀 Cache update
        DataCacheService().removeStudySubjectFromCache(
          widget.studentId,
          subjectId,
        );
      }

      // 🚀 Offline Logic
      final bool online = await SyncService().isOnline();
      if (!online) {
        await DataCacheService().addPendingOperation({
          'type': 'delete_study_subject',
          'data': {'subjectId': subjectId, 'studentId': widget.studentId},
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('offline_saved'.tr(context))));
        }
        return;
      }

      // Delete grades first
      final subjectName = deletedDoc?.data['name'];
      if (subjectName != null) {
        final grades = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: studyGradesCollectionId,
          queries: [
            Query.equal('studentId', widget.studentId),
            Query.equal('subject', subjectName),
          ],
        );

        for (var grade in grades.documents) {
          await _databases.deleteDocument(
            databaseId: databaseId,
            collectionId: studyGradesCollectionId,
            documentId: grade.$id,
          );
        }
      }

      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        documentId: subjectId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('delete_subject_success'.tr(context))),
        );
      }
    } catch (e) {
      debugPrint("Error deleting subject: $e");
      // Rollback optimistic update
      if (mounted && deletedDoc != null) {
        setState(() {
          _subjects.add(deletedDoc!);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'delete_subject_error'
                  .tr(context)
                  .replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  void _showAddSubjectDialog(BuildContext context) async {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('add_subject'.tr(context)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(labelText: 'subject_name'.tr(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel_btn'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                if (!_canWrite) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('no_add_permission'.tr(context))),
                    );
                  }
                  return;
                }
                _addSubject(nameController.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text('add_btn_action'.tr(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.studentPhotoUrl != null &&
                widget.studentPhotoUrl!.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenImage(
                        imageUrl: widget.studentPhotoUrl,
                        tag: 'study_details_student_${widget.studentId}',
                      ),
                    ),
                  );
                },
                child: Hero(
                  tag: 'study_details_student_${widget.studentId}',
                  child: CircleAvatar(
                    radius: 16,
                    backgroundImage: CachedNetworkImageProvider(
                      widget.studentPhotoUrl!,
                    ),
                  ),
                ),
              ),
            if (widget.studentPhotoUrl != null &&
                widget.studentPhotoUrl!.isNotEmpty)
              const SizedBox(width: 8),
            Flexible(
              child: Text(
                'subjects_of'
                    .tr(context)
                    .replaceFirst('%s', widget.studentName),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildStatItem(
                Icons.subject,
                'total_subjects'.tr(context),
                _subjects.length.toString(),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _subjects.isEmpty
                  ? Center(
                      child: Text(
                        'no_subjects_added'.tr(context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => await _fetchSubjects(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                      itemCount: _subjects.length,
                      itemBuilder: (context, index) {
                        final doc = _subjects[index];
                        return _SubjectCard(
                          subjectDoc: doc,
                          groupId: widget.groupId,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GradesChartPage(
                                studentId: widget.studentId,
                                studentName: widget.studentName,
                                subject: doc.data['name'],
                                groupId: widget.groupId,
                              ),
                            ),
                          ),
                          onEdit: () {}, // Implement Edit if needed
                          onDelete: () => _deleteSubject(
                            doc.$id,
                            doc.data['createdBy'] ?? '',
                          ),
                        );
                      },
                    ),
                  ),
            ),
            if (_canWrite)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_box),
                    label: Text('add_subject'.tr(context)),
                    onPressed: () => _showAddSubjectDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String title, String value) {
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
              ),
            ],
          ),
          child: Icon(icon, size: 24, color: Colors.blue.shade700),
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final models.Document subjectDoc;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String groupId;

  const _SubjectCard({
    required this.subjectDoc,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    final data = subjectDoc.data;
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.subject, color: Colors.orange),
        title: Text(
          data['name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'added_by_user'
              .tr(context)
              .replaceFirst(
                '%s',
                data['createdByName']?.toString() ?? 'user'.tr(context),
              ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete, color: Colors.red),
                  const SizedBox(width: 8),
                  Text('delete_btn'.tr(context)),
                ],
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class GradesChartPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String subject;
  final String groupId;

  const GradesChartPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.subject,
    required this.groupId,
  });

  @override
  State<GradesChartPage> createState() => _GradesChartPageState();
}

class _GradesChartPageState extends State<GradesChartPage> {
  final Databases _databases = AppwriteService().databases;
  final Realtime _realtime = AppwriteService().realtime;
  List<ChartData> _chartData = [];
  bool _canWrite = true;
  String? _currentUserId;
  String? _currentUserName;
  String? _teamId;

  RealtimeSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadCachedGrades();
    _fetchGrades();
    _subscribe();
    _fetchTeamId();
    _checkPermissions();
  }

  Future<void> _loadUserInfo() async {
    try {
      final user = await UserService().getCurrentUser();
      final name = await UserService().getCurrentUserName();
      if (mounted) {
        setState(() {
          _currentUserId = user?.$id;
          _currentUserName = name;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTeamId() async {
    try {
      final groupDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'groups',
        documentId: widget.groupId,
      );
      if (mounted) {
        setState(() => _teamId = groupDoc.data['teamId']);
      }
    } catch (e) {
      debugPrint("Error fetching teamId: $e");
    }
  }

  Future<void> _loadCachedGrades() async {
    final cached = await DataCacheService().getCachedStudyGrades(
      widget.studentId,
      widget.subject,
    );
    if (cached.isNotEmpty && mounted) {
      final docs = cached
          .map((m) => ChartData.fromAppwrite(models.Document.fromMap(m)))
          .toList();
      docs.sort(
        (a, b) =>
            (a.date ?? DateTime(2000)).compareTo(b.date ?? DateTime(2000)),
      );
      setState(() {
        _chartData = docs;
      });
    }
  }

  Future<void> _checkPermissions() async {
    final canWrite = await PermissionService.canWrite(widget.groupId);
    if (mounted) setState(() => _canWrite = canWrite);
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  Future<void> _fetchGrades() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studyGradesCollectionId,
        queries: [
          Query.equal('studentId', widget.studentId),
          Query.equal('subject', widget.subject),
        ],
      );

      final docs = result.documents
          .map((doc) => ChartData.fromAppwrite(doc))
          .toList();
      docs.sort(
        (a, b) =>
            (a.date ?? DateTime(2000)).compareTo(b.date ?? DateTime(2000)),
      );

      if (mounted) {
        setState(() {
          _chartData = docs;
        });

        // 🚀 Cache grades securely using toMap()
        final cacheMaps = result.documents.map((doc) => doc.toMap()).toList();
        DataCacheService().cacheStudyGrades(
          widget.studentId,
          widget.subject,
          cacheMaps,
        );
      }
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  void _subscribe() {
    _subscription = _realtime.subscribe([
      'databases.$databaseId.collections.$studyGradesCollectionId.documents',
    ]);

    _subscription!.stream.listen((event) {
      if (event.payload['studentId'] == widget.studentId &&
          event.payload['subject'] == widget.subject) {
        _fetchGrades();
      }
    });
  }

  Future<void> _addGrade(String exam, double grade, double maxGrade) async {
    final String docId = ID.unique(); // 🚀 Use consistent ID
    final Map<String, dynamic> gradeData = {
      'exam': exam,
      'grade': grade,
      'maxGrade': maxGrade,
      'studentId': widget.studentId,
      'subject': widget.subject,
      'createdBy': _currentUserId ?? 'pending',
      'createdByName': _currentUserName ?? 'pending',
      'date': DateTime.now().toIso8601String(),
      'groupId': widget.groupId,
    };

    // 🚀 Optimistic UI
    final Map<String, dynamic> tempDocData = Map.from(gradeData);
    tempDocData[r'$id'] = docId;

    final tempChartData = ChartData(
      docId,
      exam,
      grade,
      maxGrade,
      getRandomColor(),
      createdBy: _currentUserName,
      date: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        _chartData.add(tempChartData);
        _chartData.sort(
          (a, b) =>
              (a.date ?? DateTime(2000)).compareTo(b.date ?? DateTime(2000)),
        );
      });
      // 🚀 Cache update
      DataCacheService().upsertStudyGradeInCache(
        widget.studentId,
        widget.subject,
        tempDocData,
      );
    }

    try {
      final bool isConnected = await SyncService().isOnline();

      if (isConnected) {
        final doc = await _databases.createDocument(
          databaseId: databaseId,
          collectionId: studyGradesCollectionId,
          documentId: docId, // 🚀 Use consistent docId
          data: gradeData,
          permissions: _teamId != null
              ? [
                  Permission.read(Role.team(_teamId!)),
                  Permission.update(Role.team(_teamId!)),
                  Permission.delete(Role.team(_teamId!)),
                ]
              : null,
        );
        if (mounted) {
          setState(() {
            _chartData.removeWhere((d) => d.id == docId);
            _chartData.add(ChartData.fromAppwrite(doc));
            _chartData.sort(
              (a, b) => (a.date ?? DateTime(2000)).compareTo(
                b.date ?? DateTime(2000),
              ),
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('add_grade_success'.tr(context))),
          );
          // Sync cache
          DataCacheService().removeStudyGradeFromCache(
            widget.studentId,
            widget.subject,
            docId,
          );
          final Map<String, dynamic> finalData = doc.toMap();
          DataCacheService().upsertStudyGradeInCache(
            widget.studentId,
            widget.subject,
            finalData,
          );
        }
      } else {
        await DataCacheService().addPendingOperation({
          'type': 'add_study_grade',
          'data': {...gradeData, r'$id': docId, 'teamId': _teamId},
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('offline_saved'.tr(context))));
        }
      }
    } catch (e) {
      debugPrint("Error adding grade: $e");
      if (mounted) {
        setState(() {
          _chartData.removeWhere((d) => d.id == docId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'add_grade_error'.tr(context).replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteGrade(String id) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('no_delete_permission'.tr(context))),
        );
      }
      return;
    }

    ChartData? deletedData;
    try {
      // 🚀 Optimistic UI
      if (mounted) {
        setState(() {
          final idx = _chartData.indexWhere((d) => d.id == id);
          if (idx != -1) {
            deletedData = _chartData.removeAt(idx);
          }
        });
        // 🚀 Cache update
        DataCacheService().removeStudyGradeFromCache(
          widget.studentId,
          widget.subject,
          id,
        );
      }

      final bool isConnected = await SyncService().isOnline();

      if (isConnected) {
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: studyGradesCollectionId,
          documentId: id,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('delete_grade_success'.tr(context))),
          );
        }
      } else {
        await DataCacheService().addPendingOperation({
          'type': 'delete_study_grade',
          'data': {
            'gradeId': id,
            'studentId': widget.studentId,
            'subject': widget.subject,
          },
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('offline_saved'.tr(context))));
        }
      }
    } catch (e) {
      debugPrint("Error deleting grade: $e");
      if (mounted && deletedData != null) {
        setState(() {
          _chartData.add(deletedData!);
          _chartData.sort(
            (a, b) =>
                (a.date ?? DateTime(2000)).compareTo(b.date ?? DateTime(2000)),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'delete_grade_error'.tr(context).replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  void _showAddGradeDialog(BuildContext context) {
    final TextEditingController examController = TextEditingController();
    final TextEditingController gradeController = TextEditingController();
    final TextEditingController maxController = TextEditingController(
      text: "100",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('add_grade'.tr(context)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: examController,
              decoration: InputDecoration(labelText: 'exam_name'.tr(context)),
            ),
            TextField(
              controller: gradeController,
              decoration: InputDecoration(labelText: 'grade_value'.tr(context)),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: maxController,
              decoration: InputDecoration(labelText: 'out_of'.tr(context)),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel_btn'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              final double? grade = double.tryParse(gradeController.text);
              final double? max = double.tryParse(maxController.text);
              if (grade != null &&
                  max != null &&
                  examController.text.isNotEmpty) {
                if (!_canWrite) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('no_add_permission'.tr(context))),
                    );
                  }
                  return;
                }
                _addGrade(examController.text, grade, max);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text('add_btn_action'.tr(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.subject} - ${widget.studentName}"),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
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
            Expanded(
              flex: 2,
              child: _chartData.isEmpty
                  ? Center(
                      child: Text(
                        'no_chart_data'.tr(context),
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : SfCartesianChart(
                      primaryXAxis: CategoryAxis(),
                      title: ChartTitle(
                        text: 'student_academic_level'.tr(context),
                        textStyle: const TextStyle(color: Colors.white),
                      ),
                      series: <CartesianSeries>[
                        ColumnSeries<ChartData, String>(
                          dataSource: _chartData,
                          xValueMapper: (ChartData data, _) => data.exam,
                          yValueMapper: (ChartData data, _) => data.percentage,
                          pointColorMapper: (ChartData data, _) => data.color,
                          dataLabelSettings: const DataLabelSettings(
                            isVisible: true,
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              flex: 3,
              child: RefreshIndicator(
                onRefresh: () async => await _fetchGrades(),
                child: ListView.builder(
                  itemCount: _chartData.length,
                itemBuilder: (context, index) {
                  final data = _chartData[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      title: Text(
                        data.exam,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'grade_label'
                            .tr(context)
                            .replaceFirst('%s', data.grade.toString())
                            .replaceFirst('%s', data.maxGrade.toString()),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteGrade(data.id),
                      ),
                    ),
                  );
                },
              ),
            ),
            ),
            if (_canWrite)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('add_grade'.tr(context)),
                    onPressed: () => _showAddGradeDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
