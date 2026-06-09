import 'package:flutter/material.dart';
// removed appwrite
import '../services/appwrite_service.dart';
import '../services/grade_service.dart';
import '../widgets/premium_background.dart';
import 'points_list_page.dart';

class PointsGradeSelectorPage extends StatefulWidget {
  final String type; // 'servants', 'attendees', or Custom Page Name

  const PointsGradeSelectorPage({super.key, required this.type});

  @override
  State<PointsGradeSelectorPage> createState() =>
      _PointsGradeSelectorPageState();
}

class _PointsGradeSelectorPageState extends State<PointsGradeSelectorPage> {
  late GradeService _gradeService;
  List<String> _grades = [];
  bool _isLoading = true;
  String _myGroupId = '';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = await AppwriteService().account.get();
      final doc = await AppwriteService().databases.getDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: 'users_info',
        documentId: user.$id,
      );

      if (mounted) {
        setState(() {
          _myGroupId = doc.data['groupId'] ?? '';
          if (_myGroupId.isNotEmpty) {
            _gradeService = GradeService(groupId: _myGroupId);
            _fetchGrades();
          } else {
            _isLoading = false;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchGrades() async {
    try {
      final grades = await _gradeService.getGrades();
      if (mounted) {
        setState(() {
          _grades = grades;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching grades: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = 'الفصول - نقاط ';
    if (widget.type == 'servants') {
      title += 'الخدام';
    } else if (widget.type == 'attendees') {
      title += 'المخدومين';
    } else {
      title += widget.type;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0D47A1), // Match premium theme
        foregroundColor: Colors.white,
      ),
      body: PremiumBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _grades.isEmpty
                ? const Center(child: Text("لا توجد فصول متاحة.", style: TextStyle(color: Colors.white70)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _grades.length,
                    itemBuilder: (context, index) {
                      final grade = _grades[index];
                      return Card(
                        elevation: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        color: Colors.white.withValues(alpha: 0.95),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.class_, color: Colors.orange),
                          ),
                          title: Text(
                            grade,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B)
                            ),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.black54),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PointsListPage(
                                  type: widget.type,
                                  grade: grade,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
