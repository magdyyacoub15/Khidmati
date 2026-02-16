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
  final Realtime _realtime = Realtime(AppwriteService().client);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();

      // Initial Fetch
      try {
        final doc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: usersCollectionId,
          documentId: user.$id,
        );
        _updateState(doc.data);
      } catch (e) {
        debugPrint("Error fetching user data: $e");
      }

      // Realtime Listener
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);

      _userSubscription!.stream.listen((event) {
        if (mounted) {
          _updateState(event.payload);
        }
      });
    } catch (e) {
      debugPrint("Error in _loadUserData: $e");
      if (mounted) setState(() => _isLoading = false);
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
        appBar: AppBar(title: const Text("تحميل...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text("الفصول الدراسية"),
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
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final grades = snapshot.data!;

        if (grades.isEmpty) {
          return const Center(
            child: Text(
              "لا توجد فصول مضافة حالياً",
              style: TextStyle(fontSize: 18, color: Colors.white),
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
                    "اضغط لمتابعة طلاب الفصل",
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
  final Realtime _realtime = Realtime(AppwriteService().client);

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ تم حذف جميع مواد ودرجات الطالب $studentName"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ خطأ في حذف بيانات الطالب: $e")),
        );
      }
    }
  }

  void _showClearStudentDataDialog(String studentId, String studentName) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ انتهت صلاحية الاشتراك")),
        );
      }
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("مسح بيانات الطالب"),
        content: Text(
          "هل أنت متأكد من مسح جميع بيانات الطالب '$studentName' (المواد والدرجات)؟\n\nملاحظة: الطالب نفسه لن يتم حذفه.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearStudentData(studentId, studentName);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text("مسح البيانات"),
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
            ? const Center(
                child: Text(
                  "لا يوجد طلاب في هذا الفصل",
                  style: TextStyle(fontSize: 18, color: Colors.white),
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
                          'إجمالي الطلاب',
                          _students.length.toString(),
                        ),
                        _buildStatItem(Icons.grade, 'الصف', widget.gradeTitle),
                      ],
                    ),
                  ),
                  Expanded(
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
            : const Text("لا يوجد هاتف", textAlign: TextAlign.center),
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
  final Realtime _realtime = Realtime(AppwriteService().client);

  List<models.Document> _subjects = [];
  bool _isLoading = true;
  bool _canWrite = true;
  String? _teamId;
  RealtimeSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadCachedSubjects();
    _fetchSubjects();
    _subscribe();
    _fetchTeamId();
    _checkPermissions();
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
        // 🚀 Cache subjects
        // Wait, Appwrite Document is more than just data. But for caching simple stuff doc.data is usually enough if we include $id.
        final cacheMaps = result.documents.map((doc) {
          final m = Map<String, dynamic>.from(doc.data);
          m['\$id'] = doc.$id;
          m['\$createdAt'] = doc.$createdAt;
          return m;
        }).toList();
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
    try {
      final user = await AppwriteService().account.get();
      final userName = await UserService().getCurrentUserName();

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        documentId: ID.unique(),
        data: {
          'name': name,
          'studentId': widget.studentId,
          'studentName': widget.studentName,
          'type': 'school',
          'createdAt': DateTime.now().toIso8601String(),
          'createdBy': user.$id,
          'createdByName': userName,
          'groupId': widget.groupId,
        },
        permissions: _teamId != null
            ? [
                Permission.read(Role.team(_teamId!)),
                Permission.update(Role.team(_teamId!)),
                Permission.delete(Role.team(_teamId!)),
              ]
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ تم إضافة المادة بنجاح")),
        );
      }
    } catch (e) {
      debugPrint("Error adding subject: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ في إضافة المادة: $e")));
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
          const SnackBar(content: Text("❌ ليس لديك صلاحية لحذف هذه المادة")),
        );
      }
      return;
    }

    if (!mounted) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("حذف المادة"),
            content: const Text(
              "هل أنت متأكد من حذف هذه المادة وجميع درجاتها؟",
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
        ) ??
        false;

    if (!confirmed) return;

    try {
      // Delete grades first
      final subjectDoc = _subjects.firstWhere((doc) => doc.$id == subjectId);
      final subjectName = subjectDoc.data['name'];

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

      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: subjectsCollectionId,
        documentId: subjectId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ تم حذف المادة وجميع بياناتها بنجاح")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ في حذف المادة: $e")));
      }
    }
  }

  void _showAddSubjectDialog(BuildContext context) async {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("إضافة مادة"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "اسم المادة"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                if (!_canWrite) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("⚠️ ليس لديك صلاحية للإضافة"),
                      ),
                    );
                  }
                  return;
                }
                _addSubject(nameController.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text("إضافة"),
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
                "مواد: ${widget.studentName}",
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
                "إجمالي المواد",
                _subjects.length.toString(),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _subjects.isEmpty
                  ? const Center(
                      child: Text(
                        "لا توجد مواد مضافة",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    )
                  : ListView.builder(
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
            if (_canWrite)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_box),
                    label: const Text("إضافة مادة"),
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
        subtitle: Text("أضيفت بواسطة: ${data['createdByName'] ?? 'مستخدم'}"),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text("حذف"),
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
  final Realtime _realtime = Realtime(AppwriteService().client);
  List<ChartData> _chartData = [];
  bool _canWrite = true;

  RealtimeSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadCachedGrades();
    _fetchGrades();
    _subscribe();
    _checkPermissions();
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

        // 🚀 Cache grades
        final cacheMaps = result.documents.map((doc) {
          final m = Map<String, dynamic>.from(doc.data);
          m['\$id'] = doc.$id;
          m['\$createdAt'] = doc.$createdAt;
          return m;
        }).toList();
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
    try {
      final user = await AppwriteService().account.get();
      final userName = await UserService().getCurrentUserName();

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: studyGradesCollectionId,
        documentId: ID.unique(),
        data: {
          'exam': exam,
          'grade': grade,
          'maxGrade': maxGrade,
          'studentId': widget.studentId,
          'subject': widget.subject,
          'createdBy': user.$id,
          'createdByName': userName,
          'date': DateTime.now().toIso8601String(),
          'groupId': widget.groupId,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ تم إضافة الدرجة بنجاح")),
        );
      }
    } catch (e) {
      debugPrint("Error adding grade: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ في إضافة الدرجة: $e")));
      }
    }
  }

  Future<void> _deleteGrade(String id) async {
    if (!_canWrite) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ ليس لديك صلاحية للحذف")),
        );
      }
      return;
    }

    try {
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: studyGradesCollectionId,
        documentId: id,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ تم حذف الدرجة بنجاح")));
      }
    } catch (e) {
      debugPrint("Error deleting grade: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ في حذف الدرجة: $e")));
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
        title: const Text("إضافة درجة"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: examController,
              decoration: const InputDecoration(labelText: "اسم الامتحان"),
            ),
            TextField(
              controller: gradeController,
              decoration: const InputDecoration(labelText: "الدرجة"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: maxController,
              decoration: const InputDecoration(labelText: "من كام؟"),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
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
                      const SnackBar(
                        content: Text("⚠️ ليس لديك صلاحية للإضافة"),
                      ),
                    );
                  }
                  return;
                }
                _addGrade(examController.text, grade, max);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text("إضافة"),
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
                  ? const Center(
                      child: Text(
                        "لا توجد بيانات للرسم البياني",
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : SfCartesianChart(
                      primaryXAxis: CategoryAxis(),
                      title: ChartTitle(
                        text: 'مستوى الطالب الدراسي',
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
                        "الدرجة: ${data.grade} / ${data.maxGrade}",
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
            if (_canWrite)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("إضافة درجة"),
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
