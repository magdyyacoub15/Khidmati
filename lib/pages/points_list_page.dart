import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';
// removed user_service
import '../services/permission_service.dart';
import '../models/kid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/premium_background.dart';

class PointsListPage extends StatefulWidget {
  final String type; // 'servants', 'attendees', or custom
  final String grade;

  const PointsListPage({super.key, required this.type, required this.grade});

  @override
  State<PointsListPage> createState() => _PointsListPageState();
}

class _PointsListPageState extends State<PointsListPage> {
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;

  List<Kid> _kids = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String _myGroupId = '';
  bool _canWrite = false;

  List<Kid> get _filteredKids {
    if (_searchQuery.isEmpty) return _kids;
    return _kids.where((k) => k.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchUserDataAndKids();
  }

  Future<void> _fetchUserDataAndKids() async {
    try {
      final user = await AppwriteService().account.get();
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'users_info',
        documentId: user.$id,
      );

      if (mounted) {
        _myGroupId = doc.data['groupId'] ?? '';
        _canWrite = await PermissionService.canWrite(_myGroupId);
        if (_myGroupId.isNotEmpty) {
          await _fetchKids();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchKids() async {
    setState(() => _isLoading = true);
    try {
      String baseCollection = (widget.type == 'servants' || widget.type == 'خدام')
          ? 'servants'
          : 'students';

      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: baseCollection,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('grade', widget.grade),
          Query.limit(1000),
        ],
      );

      final kids = result.documents.map((e) => Kid.fromAppwrite(e)).toList();
      kids.sort((a, b) => b.points.compareTo(a.points)); // Sort descending

      if (mounted) {
        setState(() {
          _kids = kids;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching kids: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePoints(Kid kid, int change) async {
    if (!_canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية لتعديل النقاط')),
      );
      return;
    }

    final newPoints = kid.points + change;
    if (newPoints < 0) return; // Prevent negative points

    // Optimistic UI update
    setState(() {
      final index = _kids.indexWhere((k) => k.id == kid.id);
      if (index != -1) {
        _kids[index] = kid.copyWithStatus(points: newPoints);
        // Re-sort after optimistic update
        _kids.sort((a, b) => b.points.compareTo(a.points));
      }
    });

    try {
      String baseCollection = (widget.type == 'servants' || widget.type == 'خدام')
          ? 'servants'
          : 'students';

      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: baseCollection,
        documentId: kid.id,
        data: {
          'points': newPoints,
        },
      );
    } catch (e) {
      debugPrint("Error updating points: $e");
      // Revert if error
      setState(() {
        final index = _kids.indexWhere((k) => k.id == kid.id);
        if (index != -1) {
          _kids[index] = kid;
          _kids.sort((a, b) => b.points.compareTo(a.points));
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
    }
  }

  Future<void> _resetAllPoints() async {
    if (!_canWrite) return;
    
    final TextEditingController passController = TextEditingController();
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تصفير النقاط', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('هل أنت متأكد من تصفير جميع نقاط هذا الفصل؟ هذه العملية لا يمكن التراجع عنها.'),
              const SizedBox(height: 16),
              const Text('لتأكيد العملية، اكتب كلمة "تصفير" أدناه:', style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(
                controller: passController,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'تصفير',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passController.text.trim() == 'تصفير') {
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الكلمة غير صحيحة')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('تأكيد التصفير', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        String baseCollection = (widget.type == 'servants' || widget.type == 'خدام')
            ? 'servants'
            : 'students';

        for (var kid in _kids) {
          if (kid.points > 0) {
            await _databases.updateDocument(
              databaseId: databaseId,
              collectionId: baseCollection,
              documentId: kid.id,
              data: {'points': 0},
            );
          }
        }
        
        await _fetchKids();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تصفير جميع النقاط بنجاح')),
          );
        }
      } catch (e) {
        debugPrint("Error resetting points: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حدث خطأ أثناء التصفير: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('النقاط - ${widget.grade}'),
        backgroundColor: const Color(0xFF0D47A1), // Match premium theme
        foregroundColor: Colors.white,
        actions: [
          if (_canWrite && _kids.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: 'تصفير النقاط',
              onPressed: _resetAllPoints,
            ),
        ],
      ),
      body: PremiumBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'ابحث بالاسم...',
                        prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.95),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _filteredKids.isEmpty
                        ? const Center(child: Text('لا توجد نتائج', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredKids.length,
                            itemBuilder: (context, index) {
                              final kid = _filteredKids[index];
                      // Rank colors
                      Color rankColor;
                      IconData? rankIcon;
                      if (index == 0) {
                        rankColor = const Color(0xFFFFD700); // Gold
                        rankIcon = Icons.workspace_premium;
                      } else if (index == 1) {
                        rankColor = const Color(0xFFC0C0C0); // Silver
                        rankIcon = Icons.workspace_premium;
                      } else if (index == 2) {
                        rankColor = const Color(0xFFCD7F32); // Bronze
                        rankIcon = Icons.workspace_premium;
                      } else {
                        rankColor = Colors.white70;
                      }

                      return Card(
                        elevation: index < 3 ? 8 : 2,
                        shadowColor: index < 3 ? rankColor.withValues(alpha: 0.5) : Colors.black26,
                        color: Colors.white.withValues(alpha: 0.95),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: index < 3
                              ? BorderSide(color: rankColor.withValues(alpha: 0.5), width: 2)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          onTap: () {
                            if (kid.photoUrl != null && kid.photoUrl!.isNotEmpty) {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  elevation: 0,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: CachedNetworkImage(
                                          imageUrl: kid.photoUrl!,
                                          placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                                          errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 50),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          kid.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Rank Number / Icon
                              SizedBox(
                                width: 30,
                                child: rankIcon != null
                                    ? Icon(rankIcon, color: rankColor, size: 28)
                                    : Text(
                                        '#${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black54,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              // Avatar
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: (kid.photoUrl != null &&
                                        kid.photoUrl!.isNotEmpty)
                                    ? CachedNetworkImageProvider(kid.photoUrl!)
                                    : null,
                                child: (kid.photoUrl == null ||
                                        kid.photoUrl!.isEmpty)
                                    ? const Icon(Icons.person, color: Colors.grey)
                                    : null,
                              ),
                            ],
                          ),
                          title: Text(
                            kid.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stars, color: Colors.orange, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${kid.points} نقطة',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: _canWrite ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.remove, color: Colors.red),
                                  onPressed: () => _updatePoints(kid, -1),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.add, color: Colors.green),
                                  onPressed: () => _updatePoints(kid, 1),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                ),
                              ),
                            ],
                          ) : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
