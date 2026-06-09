import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:math';
import 'dart:ui';
import 'dart:async';

import '../services/appwrite_service.dart';
import '../services/permission_service.dart';
import '../services/team_service.dart';
import 'referrals_page.dart';
import '../l10n/app_translations.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage>
    with SingleTickerProviderStateMixin {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Realtime _realtime = AppwriteService().realtime;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String groupsCollectionId = 'groups';

  final TextEditingController _searchController = TextEditingController();

  final List<String> _baseRoles = ["admin"];
  List<String> _dynamicRoles = [];
  List<String> get _allRoles => [..._baseRoles, ..._dynamicRoles, "user"];

  String _searchQuery = '';
  String _currentJoinCode = '...';
  String _myGroupId = '';
  String _groupAdminEmail = '';
  String _currentUserEmail = '';
  String _teamId = ''; // 🚀 Store Team ID
  bool _isResetting = false;
  AnimationController? _animationController;

  StreamSubscription<models.Document>? _groupSubscription;
  StreamSubscription<RealtimeMessage>? _usersSubscription;
  Map<String, models.Document> _usersMap = {}; // Approved users
  Map<String, models.Document> _pendingUsersMap = {};
  bool _isLoadingUsers = true;
  bool _canWrite = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _initializeAdmin();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _searchController.dispose();
    _groupSubscription?.cancel();
    _usersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeAdmin() async {
    try {
      final user = await _account.get();
      if (mounted) setState(() => _currentUserEmail = user.email);

      final userDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      if (mounted) {
        setState(() => _myGroupId = userDoc.data['groupId'] ?? '');
        if (_myGroupId.isNotEmpty) {
          _loadGroupData();
          _loadDynamicRoles();
          _loadUsers();
          _subscribeToUsers();
          _checkPermissions();
        }
      }
    } catch (e) {
      debugPrint("Error initializing admin: $e");
    }
  }

  Future<void> _checkPermissions() async {
    final canWrite = await PermissionService.canWrite(_myGroupId);
    if (mounted) setState(() => _canWrite = canWrite);
  }

  Future<void> _loadGroupData() async {
    try {
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: _myGroupId,
      );
      if (mounted) {
        setState(() {
          _currentJoinCode = doc.data['joinCode'] ?? '...';
          _groupAdminEmail = doc.data['adminEmail'] ?? '';
          _teamId = doc.data['teamId'] ?? ''; // 🚀 Fetch Team ID
        });
        // 🚀 Sync Team Members if Team ID exists
        if (_teamId.isNotEmpty && _usersMap.isNotEmpty) {
          _syncTeamMembers(_usersMap.keys.toList());
        }
      }
    } catch (e) {
      debugPrint("Error loading group: $e");
    }
  }

  Future<void> _loadDynamicRoles() async {
    try {
      final grades = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'grades',
        queries: [Query.equal('groupId', _myGroupId)],
      );
      if (mounted) {
        setState(() {
          _dynamicRoles = grades.documents
              .map((doc) => "class_supervisor_grade_${doc.data['name']}")
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Error loading dynamic roles: $e");
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      // 1. Fetch memberships for this group
      final membershipResult = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
      );

      final approvedMemberships = membershipResult.documents
          .where((m) => m.data['status'] == 'approved')
          .toList();
      final pendingMemberships = membershipResult.documents
          .where((m) => m.data['status'] == 'pending')
          .toList();

      final approvedUserIds = approvedMemberships
          .map((m) => m.data['userId'] as String)
          .toList();

      // 🚀 Sync Team Members for approved users
      if (_teamId.isNotEmpty && approvedUserIds.isNotEmpty) {
        _syncTeamMembers(approvedUserIds);
      }

      // 2. Fetch user details from users_info for ALL members (approved + pending)
      final allUserIds = membershipResult.documents
          .map((m) => m.data['userId'] as String)
          .toSet()
          .toList();

      Map<String, models.Document> userInfoMap = {};
      if (allUserIds.isNotEmpty) {
        final userInfosResult = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: AppwriteService.usersCollectionId,
          queries: [Query.equal('userId', allUserIds), Query.limit(100)],
        );
        userInfoMap = {
          for (var doc in userInfosResult.documents) doc.data['userId']: doc,
        };
      }

      // 3. Helper to merge and map
      Map<String, models.Document> processMemberships(
        List<models.Document> docs,
      ) {
        final map = <String, models.Document>{};
        for (var m in docs) {
          final uid = m.data['userId'];
          final uInfo = userInfoMap[uid];
          final mergedData = Map<String, dynamic>.from(m.data);
          if (uInfo != null) {
            mergedData['username'] = uInfo.data['username'];
            mergedData['email'] = uInfo.data['email'];
          }
          map[m.$id] = models.Document(
            $id: m.$id,
            $collectionId: m.$collectionId,
            $databaseId: m.$databaseId,
            $createdAt: m.$createdAt,
            $updatedAt: m.$updatedAt,
            $permissions: m.$permissions,
            data: mergedData,
          );
        }
        return map;
      }

      if (mounted) {
        setState(() {
          _usersMap = processMemberships(approvedMemberships);
          _pendingUsersMap = processMemberships(pendingMemberships);
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading users: $e");
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  void _subscribeToUsers() {
    final channel =
        'databases.$databaseId.collections.${AppwriteService.membershipsCollectionId}.documents';
    _usersSubscription = _realtime.subscribe([channel]).stream.listen((
      event,
    ) async {
      final payload = event.payload;
      final docId = payload['\$id'];

      if (payload['groupId'] == _myGroupId) {
        if (event.events.any(
          (e) => e.endsWith('.create') || e.endsWith('.update'),
        )) {
          try {
            // Fetch user info to avoid empty name/email in UI
            final userInfo = await _databases.listDocuments(
              databaseId: databaseId,
              collectionId: AppwriteService.usersCollectionId,
              queries: [Query.equal('userId', payload['userId'])],
            );

            final Map<String, dynamic> mergedData = Map.from(payload);
            if (userInfo.total > 0) {
              mergedData['username'] =
                  userInfo.documents.first.data['username'];
              mergedData['email'] = userInfo.documents.first.data['email'];
            }

            final newDoc = models.Document(
              $id: docId,
              $collectionId: payload['\$collectionId'],
              $databaseId: payload['\$databaseId'],
              $createdAt: payload['\$createdAt'],
              $updatedAt: payload['\$updatedAt'],
              $permissions: List<String>.from(payload['\$permissions']),
              data: mergedData,
            );

            if (mounted) {
              setState(() {
                if (payload['status'] == 'approved') {
                  _usersMap[docId] = newDoc;
                  _pendingUsersMap.remove(docId);
                  // 🚀 Sync team member immediately if approved
                  _syncTeamMembers([payload['userId']]);
                } else {
                  _pendingUsersMap[docId] = newDoc;
                  _usersMap.remove(docId);
                }
              });
            }
          } catch (e) {
            debugPrint("Error fetching user info for realtime update: $e");
          }
        } else if (event.events.any((e) => e.endsWith('.delete'))) {
          if (mounted) {
            setState(() {
              _usersMap.remove(docId);
              _pendingUsersMap.remove(docId);
            });
          }
        }
      } else {
        // Membership for another group
        if (mounted) {
          setState(() {
            _usersMap.remove(docId);
            _pendingUsersMap.remove(docId);
          });
        }
      }
    });
  }

  Future<void> _copyCode() async {
    if (_currentJoinCode == '...') {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _currentJoinCode));
    if (!mounted) {
      return;
    }
    _showSnackBar('copied_to_clipboard'.tr(context), Colors.blueAccent);
  }

  Future<void> _resetJoinCode() async {
    if (_myGroupId.isEmpty) {
      return;
    }

    if (!_canWrite) {
      _showSnackBar('service_unavailable'.tr(context), Colors.red);
      return;
    }

    setState(() => _isResetting = true);

    try {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random();
      String newCode = '';

      bool isUnique = false;
      while (!isUnique) {
        newCode = List.generate(
          6,
          (index) => chars[random.nextInt(chars.length)],
        ).join();
        final query = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: groupsCollectionId,
          queries: [Query.equal('joinCode', newCode)],
        );
        if (query.documents.isEmpty) {
          isUnique = true;
        }
      }

      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: _myGroupId,
        data: {'joinCode': newCode},
      );

      if (!mounted) {
        return;
      }
      setState(() => _currentJoinCode = newCode);
      _showSnackBar('code_changed_success'.tr(context), Colors.green);
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showSnackBar('code_change_failed'.tr(context), Colors.red);
    } finally {
      setState(() => _isResetting = false);
    }
  }

  String _formatRoleForDisplay(String role) {
    if (role == 'admin') return 'admin_role'.tr(context);
    if (role == 'general_supervisor') {
      return 'general_supervisor_role'.tr(context);
    }
    if (role == 'user') {
      return 'user_role'.tr(context);
    }
    if (role.startsWith('class_supervisor_grade_')) {
      final grade = role.replaceFirst('class_supervisor_grade_', '');
      return 'class_supervisor_format'.tr(context).replaceFirst('%s', grade);
    }
    return role;
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Future<void> _updateRole(
    String membershipId,
    String userId,
    String newRole,
  ) async {
    if (!_canWrite) {
      _showSnackBar('service_unavailable'.tr(context), Colors.red);
      return;
    }
    try {
      // 1. Update Membership doc
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: membershipId,
        data: {'role': newRole},
      );

      // 2. Sync to users_info IF this is their active group (for realtime UI update)
      try {
        final userDoc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: AppwriteService.usersCollectionId,
          documentId: userId,
        );
        if (userDoc.data['groupId'] == _myGroupId) {
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: AppwriteService.usersCollectionId,
            documentId: userId,
            data: {'role': newRole},
          );
        }
      } catch (e) {
        debugPrint("Silent error syncing role to users_info: $e");
      }

      if (!mounted) return;
      _showSnackBar('role_updated'.tr(context), Colors.blue);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        'error_occurred'.tr(context).replaceFirst('%s', '$e'),
        Colors.red,
      );
    }
  }

  // 🚀 Approval Methods
  Future<void> _approveUser(String membershipId, String userId) async {
    if (!_canWrite) {
      _showSnackBar('service_unavailable'.tr(context), Colors.red);
      return;
    }
    try {
      // 1. Update status to approved
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: membershipId,
        data: {'status': 'approved'},
      );

      // 2. Add to team (Appwrite Teams Protection)
      if (_teamId.isNotEmpty) {
        await TeamService().addMember(_teamId, userId);
      }

      if (!mounted) return;
      _showSnackBar('member_accepted'.tr(context), Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        'error_occurred'.tr(context).replaceFirst('%s', '$e'),
        Colors.red,
      );
    }
  }

  Future<void> _rejectUser(String membershipId) async {
    if (!_canWrite) {
      _showSnackBar('service_unavailable'.tr(context), Colors.red);
      return;
    }
    try {
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: membershipId,
      );
      if (!mounted) return;
      _showSnackBar('member_rejected'.tr(context), Colors.orange);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        'error_occurred'.tr(context).replaceFirst('%s', e.toString()),
        Colors.red,
      );
    }
  }

  Future<void> _deleteUser(
    String membershipId,
    String userId,
    String username,
  ) async {
    if (!_canWrite) {
      _showSnackBar('service_unavailable'.tr(context), Colors.red);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('confirm_deletion'.tr(context), textAlign: TextAlign.right),
        content: Text(
          'delete_user_confirm'.tr(context).replaceFirst('%s', username),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('delete'.tr(context)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 1. Delete membership
        await _databases.deleteDocument(
          databaseId: databaseId,
          collectionId: AppwriteService.membershipsCollectionId,
          documentId: membershipId,
        );

        // 2. Clear groupId in user doc to trigger Logout on their device via Realtime
        try {
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: AppwriteService.usersCollectionId,
            documentId: userId,
            data: {
              'groupId': '',
            }, // Setting to empty triggers logout in DashboardPage
          );
        } catch (e) {
          debugPrint("Silent error clearing groupId for $userId: $e");
        }

        if (!mounted) return;
        _showSnackBar('user_deleted_success'.tr(context), Colors.orange);
      } catch (e) {
        if (!mounted) return;
        _showSnackBar(
          'error_occurred'.tr(context).replaceFirst('%s', e.toString()),
          Colors.red,
        );
      }
    }
  }

  Future<void> _deleteAllSystemData(String password) async {
    if (!_canWrite) {
      _showSnackBar('service_unavailable'.tr(context), Colors.red);
      return;
    }
    try {
      // التحقق الفعلي من كلمة المرور عبر إعادة تسجيل الدخول
      try {
        await _account.deleteSession(sessionId: 'current');
        await _account.createEmailPasswordSession(
          email: _currentUserEmail,
          password: password,
        );
      } on AppwriteException catch (_) {
        if (mounted) {
          _showSnackBar('password_incorrect'.tr(context), Colors.red);
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
        return;
      } catch (e) {
        if (mounted) {
          _showSnackBar('password_check_error'.tr(context), Colors.red);
        }
        return;
      }

      final subcollections = [
        'grades',
        'subjects',
        'attendance_records',
        'meetings',
        'servants',
        'reports',
        'notifications',
        'visits',
        'absence_actions',
        'preparations',
        'status_tracking',
        'birthdays',
      ]; // 'students' and 'kids' usually same concept? check names.

      // 'students' collection?
      // Let's add all likely collections.
      final allCols = ['students', ...subcollections];

      // Delete Docs
      for (var col in allCols) {
        try {
          var docs = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: col,
            queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
          );
          while (docs.documents.isNotEmpty) {
            await Future.wait(
              docs.documents.map(
                (d) => _databases.deleteDocument(
                  databaseId: databaseId,
                  collectionId: col,
                  documentId: d.$id,
                ),
              ),
            );
            docs = await _databases.listDocuments(
              databaseId: databaseId,
              collectionId: col,
              queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
            );
          }
        } catch (e) {
          debugPrint("Skipping col $col: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${'error_fixing_collections'.tr(context)}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }

      // Clear Memberships and Active Group pointers
      final membershipDocs = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
      );

      var currentMemberships = membershipDocs;
      while (currentMemberships.documents.isNotEmpty) {
        for (var d in currentMemberships.documents) {
          final userId = d.data['userId'];
          // 1. Delete membership
          await _databases.deleteDocument(
            databaseId: databaseId,
            collectionId: AppwriteService.membershipsCollectionId,
            documentId: d.$id,
          );
          // 2. Clear groupId in user doc if it was this group
          try {
            final userDoc = await _databases.getDocument(
              databaseId: databaseId,
              collectionId: AppwriteService.usersCollectionId,
              documentId: userId,
            );
            if (userDoc.data['groupId'] == _myGroupId) {
              await _databases.updateDocument(
                databaseId: databaseId,
                collectionId: AppwriteService.usersCollectionId,
                documentId: userId,
                data: {'groupId': null},
              );
            }
          } catch (e) {
            debugPrint("Error clearing groupId for user $userId: $e");
          }
        }
        currentMemberships = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: AppwriteService.membershipsCollectionId,
          queries: [Query.equal('groupId', _myGroupId), Query.limit(100)],
        );
      }

      // Delete Group
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: _myGroupId,
      );

      // Logout
      await _account.deleteSession(sessionId: 'current');
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _showDeleteSystemDialog() {
    final TextEditingController passwordController = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'serious_warning'.tr(context),
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'delete_system_warning'.tr(context),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('enter_password_confirm'.tr(context)),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'password_required'.tr(context),
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('cancel'.tr(context)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () async {
                      if (passwordController.text.isEmpty) {
                        setState(
                          () => errorText = 'password_required'.tr(context),
                        );
                        return;
                      }
                      setState(() {
                        isLoading = true;
                        errorText = null;
                      });
                      // We skip actual auth check for now to avoid session complexity,
                      // effectively trusting the active admin session.
                      await _deleteAllSystemData(passwordController.text);
                    },
                    child: Text('delete_system_confirm'.tr(context)),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'control_panel'.tr(context),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            if (!_canWrite)
              Text(
                'read_only_mode'.tr(context),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_currentUserEmail.isNotEmpty &&
              _currentUserEmail == _groupAdminEmail)
            IconButton(
              icon: const Icon(
                Icons.delete_forever,
                color: Colors.redAccent,
                size: 30,
              ),
              onPressed: _showDeleteSystemDialog,
              tooltip: 'delete_entire_system'.tr(context),
            ),

          // 🆕 Security Migration Button (Only for Admin)
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(
              Icons.help_outline_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => _showRoleDefinitionsDialog(context),
            tooltip: 'role_definitions'.tr(context),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          _buildPremiumBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildJoinCodeSection(),
                _buildReferralSection(), // Added Referral Button Section
                if (_pendingUsersMap.isNotEmpty) _buildPendingRequestsSection(),
                _buildSearchAndUsersSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_animationController != null)
            AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildAnimatedBlob(
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 100,
                        cos(_animationController!.value * 2 * pi) * 50,
                      ),
                      color: Colors.white.withValues(alpha: 0.1),
                      size: 400,
                    ),
                    _buildAnimatedBlob(
                      top: 400,
                      left: 200,
                      offset: Offset(
                        cos(_animationController!.value * 2 * pi) * 80,
                        sin(_animationController!.value * 2 * pi) * 120,
                      ),
                      color: Colors.white.withValues(alpha: 0.05),
                      size: 300,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    double? top,
    double? left,
    required Offset offset,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top ?? -100,
      left: left ?? -100,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  Widget _buildJoinCodeSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'join_code_title'.tr(context),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      GestureDetector(
                        onTap: _copyCode,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _currentJoinCode,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.copy,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _isResetting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: _resetJoinCode,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferralSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: GestureDetector(
        onTap: () {
          if (_myGroupId.isEmpty) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReferralsPage(groupId: _myGroupId),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.card_giftcard,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'invite_other_service'.tr(context),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'get_free_subscription'.tr(context),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequestsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_alt_1, color: Colors.orange),
              const SizedBox(width: 10),
              Text(
                'new_join_requests'
                    .tr(context)
                    .replaceFirst('%s', '${_pendingUsersMap.length}'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._pendingUsersMap.values.map((doc) {
            final data = doc.data;
            return Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text(
                  data['username'] ?? 'new_user'.tr(context),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(data['email'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => _approveUser(doc.$id, data['userId']),
                      tooltip: 'accept'.tr(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => _rejectUser(doc.$id),
                      tooltip: 'reject'.tr(context),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSearchAndUsersSection() {
    return Expanded(
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 20, 25, 10),
              child: TextField(
                controller: _searchController,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'search_servant_hint'.tr(context),
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF1976D2),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF1F4F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildUserList()),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList() {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_usersMap.isEmpty) {
      return Center(
        child: Text(
          'no_members_in_group'.tr(context),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final users = _usersMap.values.where((doc) {
      final name = (doc.data['username'] ?? '').toString().toLowerCase();
      final email = (doc.data['email'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || email.contains(_searchQuery);
    }).toList();

    if (users.isEmpty) {
      return Center(
        child: Text(
          'no_results'.tr(context),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final doc = users[index];
        final uid = doc.$id;
        final data = doc.data;
        final role = data['role'] ?? 'user';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFF1F4F8)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 5,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getRoleColor(role).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getRoleIcon(role),
                color: _getRoleColor(role),
                size: 24,
              ),
            ),
            title: Text(
              data['username'] ?? 'unknown_user'.tr(context),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['email'] ?? 'ID: ${data['userId']}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getRoleColor(role).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _allRoles.contains(role) ? role : 'user',
                    isDense: true,
                    isExpanded: true, // Fix collision/overflow
                    underline: const SizedBox(),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _getRoleColor(role),
                    ),
                    onChanged: (val) => _updateRole(uid, data['userId'], val!),
                    items: _allRoles
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(
                              _getRoleLabel(r),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: _getRoleColor(role),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_sweep_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () => _deleteUser(
                uid,
                data['userId'] ?? '',
                data['username'] ?? '',
              ),
            ),
          ),
        );
      },
    ),
    );
  }

  Color _getRoleColor(String role) {
    if (role == 'admin') return const Color(0xFFD32F2F);
    if (role.contains('supervisor')) return const Color(0xFF1976D2);
    return Colors.blueGrey;
  }

  IconData _getRoleIcon(String role) {
    if (role == 'admin') return Icons.shield_rounded;
    if (role.contains('supervisor')) return Icons.admin_panel_settings_rounded;
    return Icons.person_rounded;
  }

  // 🚀 Sync Team Members Logic
  Future<void> _syncTeamMembers(List<String> userIds) async {
    if (_teamId.isEmpty) return;
    try {
      // 1. Get current Team members
      final teamMembers = await TeamService().getTeamMembers(_teamId);
      final teamMemberIds = teamMembers.map((m) => m.userId).toSet();

      // 2. Find missing members
      final missingUserIds = userIds
          .where((uid) => !teamMemberIds.contains(uid))
          .toList();

      if (missingUserIds.isEmpty) return;

      debugPrint(
        "🚀 Found ${missingUserIds.length} users needing Team Sync...",
      );

      // 3. Add them (Invite)
      for (var uid in missingUserIds) {
        await TeamService().addMember(_teamId, uid);
      }

      // ✅ Silent sync - no notification shown to user
      debugPrint("✅ Synced ${missingUserIds.length} members to team");
    } catch (e) {
      debugPrint("Error syncing team members: $e");
    }
  }

  String _getRoleLabel(String role) {
    return _formatRoleForDisplay(role);
  }

  void _showRoleDefinitionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'role_definitions_title'.tr(context),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoleDefinitionItem(
                  icon: Icons.shield_rounded,
                  color: const Color(0xFFD32F2F),
                  title: 'admin_role'.tr(context),
                  description: 'admin_role_desc'.tr(context),
                ),
                const Divider(height: 24),
                _buildRoleDefinitionItem(
                  icon: Icons.admin_panel_settings_rounded,
                  color: const Color(0xFF1976D2),
                  title: 'class_supervisor_format'
                      .tr(context)
                      .replaceFirst('%s', ''),
                  description: 'supervisor_role_desc'.tr(context),
                ),
                const Divider(height: 24),
                _buildRoleDefinitionItem(
                  icon: Icons.person_rounded,
                  color: Colors.blueGrey,
                  title: 'user_role'.tr(context),
                  description: 'user_role_desc'.tr(context),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'close'.tr(context),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoleDefinitionItem({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.trim().isEmpty
                    ? 'supervisor_role_generic'.tr(context)
                    : title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
