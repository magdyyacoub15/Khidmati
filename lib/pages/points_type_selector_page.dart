import 'package:flutter/material.dart';
// removed appwrite
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import '../services/custom_page_service.dart';
// removed user_service
import '../l10n/app_translations.dart';
import '../widgets/premium_background.dart';
import 'points_grade_selector_page.dart';

class PointsTypeSelectorPage extends StatefulWidget {
  const PointsTypeSelectorPage({super.key});

  @override
  State<PointsTypeSelectorPage> createState() => _PointsTypeSelectorPageState();
}

class _PointsTypeSelectorPageState extends State<PointsTypeSelectorPage> {
  late CustomPageService _customPageService;
  List<models.Document> _customPages = [];
  bool _isLoadingCustomPages = true;
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
            _customPageService = CustomPageService(groupId: _myGroupId);
            _fetchCustomPages();
          } else {
            _isLoadingCustomPages = false;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
      if (mounted) setState(() => _isLoadingCustomPages = false);
    }
  }

  Future<void> _fetchCustomPages() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام النقاط - اختيار الفئة'),
        backgroundColor: const Color(0xFF0D47A1), // Match premium theme
        foregroundColor: Colors.white,
      ),
      body: PremiumBackground(
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
                            PointsGradeSelectorPage(type: 'servants'),
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
                            PointsGradeSelectorPage(type: 'attendees'),
                      ),
                    );
                  },
                ),

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
                        icon: const Icon(Icons.class_),
                        label: Text(page.data['name']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.purple,
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
                              builder: (_) => PointsGradeSelectorPage(
                                type: page.data['name'],
                              ),
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
    );
  }
}
