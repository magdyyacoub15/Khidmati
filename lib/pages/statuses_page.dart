import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import 'package:intl/intl.dart';
import '../services/status_service.dart';
import '../services/permission_service.dart';

class StatusesPage extends StatefulWidget {
  const StatusesPage({super.key});

  @override
  State<StatusesPage> createState() => _StatusesPageState();
}

class _StatusesPageState extends State<StatusesPage> {
  String _myGroupId = '';
  String _currentUserId = '';
  StatusService?
  _statusService; // Made nullable to prevent LateInitializationError
  bool _isLoading = true;
  bool _canWrite = true;
  String? _errorMessage;

  final Account _account = AppwriteService().account;
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      if (mounted) {
        setState(() {
          _currentUserId = user.$id;
          _myGroupId = doc.data['groupId'] ?? '';
          _statusService = StatusService(groupId: _myGroupId);
          _isLoading = false;
        });
        final canWrite = await PermissionService.canWrite(_myGroupId);
        if (mounted) setState(() => _canWrite = canWrite);
      }
    } catch (e) {
      debugPrint("Error loading user data in StatusesPage: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "حدث خطأ أثناء تحميل البيانات";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF81D4FA), Color(0xFF0277BD)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(), // Only one header
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : (_errorMessage != null || _statusService == null)
                    ? Center(
                        child: Text(
                          _errorMessage ?? "تعذر تحميل البيانات",
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : _buildStatusContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Text(
            "الحالات",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (!_canWrite)
            Container(
              margin: const EdgeInsets.only(top: 10, left: 20, right: 20),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    "وضع القراءة فقط (انتهى الاشتراك)",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusContent() {
    return StreamBuilder<List<models.Document>>(
      stream: _statusService!.getRecentStatuses(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState();
        }

        // Group statuses by uploaderId
        final Map<String, List<models.Document>> groupedStatuses = {};
        for (var doc in snapshot.data!) {
          final data = doc.data;
          final uploaderId = data['uploaderId'];
          if (!groupedStatuses.containsKey(uploaderId)) {
            groupedStatuses[uploaderId] = [];
          }
          groupedStatuses[uploaderId]!.add(doc);
        }

        // Sort users: current user first, then others by latest status timestamp
        final List<String> userIds = groupedStatuses.keys.toList();

        userIds.sort((a, b) {
          if (a == _currentUserId) return -1;
          if (b == _currentUserId) return 1;

          final timeAStr =
              groupedStatuses[a]!.last.data['timestamp'] as String?;
          final timeBStr =
              groupedStatuses[b]!.last.data['timestamp'] as String?;

          final timeA = timeAStr != null
              ? DateTime.parse(timeAStr).millisecondsSinceEpoch
              : 0;
          final timeB = timeBStr != null
              ? DateTime.parse(timeBStr).millisecondsSinceEpoch
              : 0;
          return timeB.compareTo(timeA);
        });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: userIds.length,
          itemBuilder: (context, index) {
            final userId = userIds[index];
            final userStatuses = groupedStatuses[userId]!;
            return _buildUserStatusTile(userId, userStatuses);
          },
        );
      },
    );
  }

  Widget _buildUserStatusTile(String userId, List<models.Document> statuses) {
    final bool isCurrentUser = userId == _currentUserId;
    final latestStatus = statuses.last;
    final data = latestStatus.data;
    final timeStr = data['timestamp'] as String?;
    final time = timeStr != null
        ? DateFormat('hh:mm a').format(DateTime.parse(timeStr))
        : "...";

    return ListTile(
      onTap: () => _openStoryPlayer(statuses),
      leading: CircleAvatar(
        radius: 25,
        backgroundColor: Colors.white24,
        backgroundImage: CachedNetworkImageProvider(data['imageUrl'] ?? ''),
      ),
      title: Text(
        data['uploaderName'] ?? 'Unknown',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        "${data['source'] ?? ''} • $time",
        style: const TextStyle(color: Colors.white70),
      ),
      trailing: isCurrentUser
          ? const Icon(Icons.more_horiz, color: Colors.white)
          : null,
    );
  }

  void _openStoryPlayer(List<models.Document> statuses) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryPlayerPage(
          statuses: statuses,
          statusService: _statusService!,
          currentUserId: _currentUserId,
          canWrite: _canWrite,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined, size: 80, color: Colors.blue.shade100),
          const SizedBox(height: 16),
          const Text(
            "لا توجد حالات حالياً",
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          const Text(
            "تظهر هنا الصور المرفوعة خلال آخر 24 ساعة",
            style: TextStyle(fontSize: 14, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class StoryPlayerPage extends StatefulWidget {
  final List<models.Document> statuses;
  final StatusService statusService;
  final String currentUserId;
  final bool canWrite;

  const StoryPlayerPage({
    super.key,
    required this.statuses,
    required this.statusService,
    required this.currentUserId,
    required this.canWrite,
  });

  @override
  State<StoryPlayerPage> createState() => _StoryPlayerPageState();
}

class _StoryPlayerPageState extends State<StoryPlayerPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animController = AnimationController(vsync: this);

    // 🚀 [FIX] لا نمرر true لـ animateToPage في initState لأن الـ controller لم يتم ربطه بعد
    _loadStory(index: 0, animateToPage: false);

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animController.stop();
        _animController.reset();
        setState(() {
          if (_currentIndex + 1 < widget.statuses.length) {
            _currentIndex++;
            _loadStory(index: _currentIndex);
          } else {
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _loadStory({required int index, bool animateToPage = true}) {
    _animController.stop();
    _animController.reset();
    _animController.duration = const Duration(seconds: 5);
    _animController.forward();

    if (animateToPage && _pageController.hasClients) {
      _pageController.jumpToPage(index);
    }

    // Mark as viewed if not the uploader and has permission
    final status = widget.statuses[index];
    if (status.data['uploaderId'] != widget.currentUserId && widget.canWrite) {
      widget.statusService.markAsViewed(status.$id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.statuses[_currentIndex];
    final data = status.data;
    final bool isUploader = data['uploaderId'] == widget.currentUserId;
    final List allViewers = data['viewers'] as List? ?? [];
    // استثناء صاحب الحالة من قائمة المشاهدين
    final List viewers = allViewers
        .where((uid) => uid != data['uploaderId'])
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) => _onTapDown(details),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.statuses.length,
              itemBuilder: (context, index) {
                return CachedNetworkImage(
                  imageUrl: widget.statuses[index].data['imageUrl'] ?? '',
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                );
              },
            ),
            // Progress Bars
            Positioned(
              top: 40.0,
              left: 10.0,
              right: 10.0,
              child: Row(
                children: widget.statuses
                    .asMap()
                    .map((i, e) {
                      return MapEntry(
                        i,
                        AnimatedBar(
                          animController: _animController,
                          position: i,
                          currentIndex: _currentIndex,
                        ),
                      );
                    })
                    .values
                    .toList(),
              ),
            ),
            // User Info
            Positioned(
              top: 55.0,
              left: 10.0,
              right: 10.0,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white24,
                    backgroundImage: CachedNetworkImageProvider(
                      data['imageUrl'] ?? '',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['uploaderName'] ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${data['source'] ?? ''} • ${data['caption'] ?? ''}",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Viewer Tracking
            if (isUploader)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _showViewersList(context, viewers),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.visibility,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${viewers.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onTapDown(TapDownDetails details) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double dx = details.globalPosition.dx;

    if (dx < screenWidth / 3) {
      setState(() {
        if (_currentIndex - 1 >= 0) {
          _currentIndex--;
          _loadStory(index: _currentIndex);
        }
      });
    } else if (dx > 2 * screenWidth / 3) {
      setState(() {
        if (_currentIndex + 1 < widget.statuses.length) {
          _currentIndex++;
          _loadStory(index: _currentIndex);
        } else {
          Navigator.of(context).pop();
        }
      });
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
      } else {
        _animController.forward();
      }
    }
  }

  void _showViewersList(BuildContext context, List viewers) {
    _animController.stop();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              "المشاهدات",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            if (viewers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text("لا توجد مشاهدات بعد"),
              )
            else
              SizedBox(
                height: 300,
                child: FutureBuilder<models.DocumentList>(
                  future: AppwriteService().databases.listDocuments(
                    databaseId: 'main_db',
                    collectionId: 'users_info',
                    queries: [Query.limit(100)],
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    // Filter locally because Query.equal('$id', list) might not work well
                    // Fetching all users might be heavy but for now simpler than looping requests
                    // Better approach: Since we have viewers list, check if we can query by IDs.
                    // For now, let's filter the fetched list.
                    // A better approach for scalability is needed, but assuming small group size.

                    final allUsers = snapshot.data?.documents ?? [];
                    final filteredUsers = allUsers.where((u) {
                      return viewers.contains(u.$id) &&
                          u.$id !=
                              widget.statuses[_currentIndex].data['uploaderId'];
                    }).toList();

                    if (filteredUsers.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text("لا توجد مشاهدات من مستخدمين آخرين"),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final userData = filteredUsers[index].data;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              (userData['name'] as String?)?[0].toUpperCase() ??
                                  "?",
                            ),
                          ),
                          title: Text(userData['name'] ?? "مستخدم مجهول"),
                          subtitle: Text(userData['role'] ?? ""),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ).whenComplete(() {
      _animController.forward();
    });
  }
}

class AnimatedBar extends StatelessWidget {
  final AnimationController animController;
  final int position;
  final int currentIndex;

  const AnimatedBar({
    super.key,
    required this.animController,
    required this.position,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 3.0,
        margin: const EdgeInsets.symmetric(horizontal: 2.0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(1.5),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                _buildBar(
                  constraints.maxWidth * (position < currentIndex ? 1.0 : 0.0),
                  Colors.white,
                ),
                if (position == currentIndex)
                  AnimatedBuilder(
                    animation: animController,
                    builder: (context, child) {
                      return _buildBar(
                        constraints.maxWidth * animController.value,
                        Colors.white,
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBar(double width, Color color) {
    return Container(
      height: 3.0,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
