import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:ui';
import '../services/appwrite_service.dart';
import '../services/subscription_service.dart';
import '../l10n/app_translations.dart';

class SuperAdminPage extends StatefulWidget {
  const SuperAdminPage({super.key});

  @override
  State<SuperAdminPage> createState() => _SuperAdminPageState();
}

class _SuperAdminPageState extends State<SuperAdminPage>
    with SingleTickerProviderStateMixin {
  final Databases _databases = AppwriteService().databases;
  final SubscriptionService _subscriptionService = SubscriptionService();
  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';

  List<models.Document> _groups = [];
  List<models.Document> _filteredGroups = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  AnimationController? _animationController;
  int _totalUsersCount = 0;
  int _totalAdminsCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchGroups();
      _fetchTotalUsersCount();
      _fetchTotalAdminsCount();
    });
  }

  Future<void> _fetchTotalUsersCount() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'users_info', // Count users, not students
        queries: [
          Query.limit(1), // We only need the total count
        ],
      );
      if (mounted) {
        setState(() {
          _totalUsersCount = result.total;
        });
      }
    } catch (e) {
      debugPrint("Error fetching total users count: $e");
    }
  }

  Future<void> _fetchTotalAdminsCount() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        queries: [
          Query.limit(1), // We only need the total count
        ],
      );
      if (mounted) {
        setState(() {
          _totalAdminsCount = result.total;
        });
      }
    } catch (e) {
      debugPrint("Error fetching total admins count: $e");
    }
  }

  Future<void> _fetchGroups({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        queries: [
          Query.orderDesc('\$createdAt'),
          Query.limit(5000), // Fetch up to 5000 groups (effectively all)
        ],
      );
      if (mounted) {
        setState(() {
          _groups = result.documents;
          _filteredGroups = result.documents;
          _isLoading = false;
        });
        _onSearchChanged(_searchController.text);
      }
    } catch (e) {
      debugPrint("Error fetching groups: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          SnackBar(content: Text("Error fetching groups: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    _animationController?.stop();
    _animationController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filteredGroups = _groups.where((group) {
        final adminEmail = (group.data['adminEmail'] ?? '')
            .toString()
            .toLowerCase();
        final name = (group.data['serviceName'] ?? '').toString().toLowerCase();
        final church = (group.data['churchName'] ?? '')
            .toString()
            .toLowerCase();
        final searchLower = query.toLowerCase();
        return adminEmail.contains(searchLower) ||
            name.contains(searchLower) ||
            church.contains(searchLower);
      }).toList();
    });
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'super_admin_panel_title'.tr(context),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          _buildPremiumBackground(),
          SafeArea(
            child: Column(
              children: [
                // Stats Cards (Admins & Kids)
                Padding(
                  padding: const EdgeInsets.only(
                    top: 16,
                    left: 16,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'total_users_count'.tr(context),
                          _totalUsersCount.toString(),
                          Icons.people_alt,
                          Colors.blue.shade300,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'total_admins_count'.tr(context),
                          _totalAdminsCount.toString(),
                          Icons.admin_panel_settings,
                          Colors.orange.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'search_by_email_or_church'.tr(context),
                            hintStyle: const TextStyle(color: Colors.white70),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white70,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 15,
                            ),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : _filteredGroups.isEmpty
                      ? Center(
                          child: Text(
                            'no_results_found'.tr(context),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async => await _fetchGroups(showLoading: false),
                          child: ListView.builder(
                          itemCount: _filteredGroups.length,
                          padding: const EdgeInsets.all(15),
                          itemBuilder: (context, index) {
                            final group = _filteredGroups[index];
                            final data = group.data;
                            final String name =
                                data['serviceName'] ?? 'No Name';
                            final String adminEmail =
                                data['adminEmail'] ?? 'No Email';
                            final String? endDateStr =
                                data['subscriptionEndDate'];
                            final bool isTrial = data['isTrial'] ?? false;
                            final DateTime updateTime = DateTime.parse(
                              group.$updatedAt,
                            );
                            final bool isIdle =
                                DateTime.now().difference(updateTime).inDays >
                                30;

                            String statusText = 'unspecified_status'.tr(
                              context,
                            );
                            Color statusColor = Colors.grey;
                            DateTime? endDate;

                            if (endDateStr != null) {
                              endDate = DateTime.tryParse(endDateStr);
                              if (endDate != null &&
                                  endDate.isAfter(DateTime.now())) {
                                statusText = isTrial
                                    ? 'trial_status'.tr(context)
                                    : 'active_status'.tr(context);
                                statusColor = isTrial
                                    ? Colors.orange
                                    : Colors.green;
                              } else {
                                statusText = 'expired_status'.tr(context);
                                statusColor = Colors.red;
                              }
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: ExpansionTile(
                                  backgroundColor: Colors.white,
                                  collapsedBackgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    side: BorderSide.none,
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Color(0xFF0D47A1),
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        adminEmail,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 14,
                                            color: Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'status_prefix'
                                                .tr(context)
                                                .replaceFirst('%s', statusText),
                                            style: const TextStyle(
                                              color: Colors.blueGrey,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.event,
                                            size: 14,
                                            color: Colors.blue.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'expires_at_prefix'
                                                .tr(context)
                                                .replaceFirst(
                                                  '%s',
                                                  endDate != null
                                                      ? DateFormat(
                                                          'yyyy-MM-dd',
                                                        ).format(endDate)
                                                      : 'unspecified_status'.tr(
                                                          context,
                                                        ),
                                                ),
                                            style: TextStyle(
                                              color: Colors.blue.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (isIdle) ...[
                                            const SizedBox(width: 10),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.orange.shade200,
                                                ),
                                              ),
                                              child: Text(
                                                'idle_status'.tr(context),
                                                style: TextStyle(
                                                  color: Colors.orange.shade800,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: statusColor,
                                    radius: 8,
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(20.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildInfoRow(
                                            'identifier_label'.tr(context),
                                            group.$id,
                                            Icons.vpn_key_outlined,
                                          ),
                                          _buildInfoRow(
                                            'last_activity_label'.tr(context),
                                            DateFormat(
                                              'yyyy-MM-dd HH:mm',
                                            ).format(updateTime),
                                            Icons.history,
                                          ),
                                          const Divider(height: 30),
                                          Text(
                                            'extend_subscription_easy'.tr(
                                              context,
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1565C0),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _buildExtendButton(
                                                group.$id,
                                                'one_month_duration'.tr(
                                                  context,
                                                ),
                                                30,
                                              ),
                                              _buildExtendButton(
                                                group.$id,
                                                'three_months_duration'.tr(
                                                  context,
                                                ),
                                                90,
                                              ),
                                              _buildExtendButton(
                                                group.$id,
                                                'six_months_duration'.tr(
                                                  context,
                                                ),
                                                180,
                                              ),
                                              _buildExtendButton(
                                                group.$id,
                                                'one_year_duration'.tr(context),
                                                365,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 25),
                                          Text(
                                            'additional_actions_label'.tr(
                                              context,
                                            ),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade900,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              _buildEditDateButton(
                                                group.$id,
                                                endDate,
                                              ),
                                              _buildCustomDaysButton(group.$id),
                                              _buildCancelButton(group.$id),
                                              const Spacer(),
                                              _buildDeleteSystemButton(
                                                group.$id,
                                                name,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteSystemButton(String groupId, String groupName) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
        tooltip: 'delete_entire_system_tooltip'.tr(context),
        onPressed: () => _showDeleteConfirmation(groupId, groupName),
      ),
    );
  }

  Widget _buildPremiumBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (_animationController != null)
            AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildAnimatedBlob(
                      top: -50,
                      left: -50,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 60,
                        cos(_animationController!.value * 2 * pi) * 40,
                      ),
                      color: Colors.white.withValues(alpha: 0.1),
                      size: 300,
                    ),
                    _buildAnimatedBlob(
                      top: 300,
                      left: 150,
                      offset: Offset(
                        cos(_animationController!.value * 2 * pi) * 70,
                        sin(_animationController!.value * 2 * pi) * 50,
                      ),
                      color: Colors.white.withValues(alpha: 0.07),
                      size: 250,
                    ),
                    _buildAnimatedBlob(
                      top: 600,
                      left: -30,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 40,
                        -cos(_animationController!.value * 2 * pi) * 60,
                      ),
                      color: Colors.white.withValues(alpha: 0.05),
                      size: 200,
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
      top: top,
      left: left,
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

  void _showDeleteConfirmation(String groupId, String groupName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteConfirmationDialog(
        groupId: groupId,
        groupName: groupName,
        onDelete: _deleteEntireSystemData,
      ),
    );
  }

  Future<void> _deleteEntireSystemData(
    String groupId, {
    required Function(String) onProgress,
  }) async {
    final deletingProgressStr = 'deleting_collection_progress'.tr(context);
    final deletedItemsCountStr = 'deleted_items_count_progress'.tr(context);
    final resettingMemberStr = 'resetting_member_permissions'.tr(context);

    // ... keep the logic as is ...
    try {
      final subcollections = [
        'grades',
        'subjects', // Legacy
        'attendance_status',
        'attendance_records',
        'attendance_kids_records',
        'attendance_servants_records',
        'attendance_kids_details',
        'attendance_servants_details',
        'meetings',
        'servants',
        'visited_reports',
        'visited_reports_details',
        'absence_actions',
        'preparations',
        'statuses',
        'status_tracking', // Legacy
        'birthday_congratulations',
        'students',
        'ai_insights',
        'individual_visits',
      ];

      int currentStep = 0;
      final totalSteps = subcollections.length + 1; // +1 for memberships

      // 1. Delete all documents in related collections
      for (var col in subcollections) {
        currentStep++;
        onProgress(
          deletingProgressStr
              .replaceFirst('%s', col)
              .replaceFirst('%s', '$currentStep')
              .replaceFirst('%s', '$totalSteps'),
        );

        try {
          var docs = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: col,
            queries: [Query.equal('groupId', groupId), Query.limit(100)],
          );

          int deletedInCol = 0;
          while (docs.documents.isNotEmpty) {
            // Process in chunks of 10 to avoid rate limits
            final chunkDocs = docs.documents;
            for (int i = 0; i < chunkDocs.length; i += 10) {
              final end = (i + 10 < chunkDocs.length)
                  ? i + 10
                  : chunkDocs.length;
              final batch = chunkDocs.sublist(i, end);

              await Future.wait(
                batch.map(
                  (d) => _databases.deleteDocument(
                    databaseId: databaseId,
                    collectionId: col,
                    documentId: d.$id,
                  ),
                ),
              );
              deletedInCol += batch.length;
              onProgress(
                "${deletingProgressStr.replaceFirst('%s', col).replaceFirst('%s', '$currentStep').replaceFirst('%s', '$totalSteps')}\n${deletedItemsCountStr.replaceFirst('%s', '$deletedInCol')}",
              );
              // Small delay to let the event loop breathe
              await Future.delayed(const Duration(milliseconds: 50));
            }

            // Re-fetch to see if more remain
            docs = await _databases.listDocuments(
              databaseId: databaseId,
              collectionId: col,
              queries: [Query.equal('groupId', groupId), Query.limit(100)],
            );
          }
        } catch (e) {
          debugPrint("Skipping collection $col: $e");
        }
      }

      // 2. Clear memberships and user roles
      onProgress(
        resettingMemberStr
            .replaceFirst('%s', '$totalSteps')
            .replaceFirst('%s', '$totalSteps'),
      );

      var membershipDocs = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [Query.equal('groupId', groupId), Query.limit(100)],
      );

      while (membershipDocs.documents.isNotEmpty) {
        for (var m in membershipDocs.documents) {
          final userId = m.data['userId'];
          if (userId != null && userId.toString().isNotEmpty) {
            try {
              await _databases.updateDocument(
                databaseId: databaseId,
                collectionId: AppwriteService.usersCollectionId,
                documentId: userId,
                data: {'groupId': '', 'role': 'user'},
              );
            } catch (e) {
              debugPrint("Error resetting user $userId: $e");
            }
          }
          await _databases.deleteDocument(
            databaseId: databaseId,
            collectionId: AppwriteService.membershipsCollectionId,
            documentId: m.$id,
          );
        }

        // Fetch next batch
        membershipDocs = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: AppwriteService.membershipsCollectionId,
          queries: [Query.equal('groupId', groupId), Query.limit(100)],
        );
      }

      // 3. Delete the group itself
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
      );

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('system_deleted_successfully'.tr(context)),
            backgroundColor: Colors.green,
          ),
        );
        _fetchGroups(showLoading: false);
      }
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'delete_system_failed'
                  .tr(context)
                  .replaceFirst('%s', e.toString()),
            ),
          ),
        );
      }
    }
  }

  Widget _buildExtendButton(String groupId, String label, int days) {
    return ElevatedButton(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await _subscriptionService.extendSubscription(groupId, days);
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'subscription_extended_success'
                      .tr(context)
                      .replaceFirst('%s', label),
                ),
              ),
            );
            _fetchGroups(showLoading: false); // Silent Refresh
          }
        } catch (e) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'error_check_internet'
                      .tr(context)
                      .replaceFirst('%s', e.toString()),
                ),
              ),
            );
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade100,
        foregroundColor: Colors.blue.shade900,
      ),
      child: Text(label),
    );
  }

  Widget _buildEditDateButton(String groupId, DateTime? currentDate) {
    return IconButton(
      icon: const Icon(Icons.calendar_today, color: Colors.blue),
      tooltip: 'edit_date_manually'.tr(context),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: currentDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          try {
            await _subscriptionService.updateSubscriptionDate(groupId, picked);
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('subscription_date_updated'.tr(context)),
                ),
              );
              _fetchGroups(showLoading: false);
            }
          } catch (e) {
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('update_failed_check_internet'.tr(context)),
                ),
              );
            }
          }
        }
      },
    );
  }

  Widget _buildCustomDaysButton(String groupId) {
    return IconButton(
      icon: const Icon(Icons.exposure, color: Colors.orange),
      tooltip: 'add_deduct_days'.tr(context),
      onPressed: () {
        final TextEditingController controller = TextEditingController();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('add_deduct_days'.tr(context)),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'number_of_days_hint'.tr(context),
                hintText: 'days_example_hint'.tr(context),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('cancel_btn'.tr(context)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final int? days = int.tryParse(controller.text);
                  final daysAddedDeductedMsg = 'days_added_deducted'.tr(
                    context,
                  );
                  final addedWord = 'added_word'.tr(context);
                  final deductedWord = 'deducted_word'.tr(context);
                  final updateFailedMsg = 'update_failed_check_internet'.tr(
                    context,
                  );

                  if (days != null) {
                    Navigator.pop(context);
                    try {
                      await _subscriptionService.extendSubscription(
                        groupId,
                        days,
                      );
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              daysAddedDeductedMsg
                                  .replaceFirst(
                                    '%s',
                                    days > 0 ? addedWord : deductedWord,
                                  )
                                  .replaceFirst('%s', '${days.abs()}'),
                            ),
                          ),
                        );
                        _fetchGroups(showLoading: false);
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(updateFailedMsg)),
                        );
                      }
                    }
                  }
                },
                child: Text('save_btn'.tr(context)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCancelButton(String groupId) {
    return IconButton(
      icon: const Icon(Icons.delete_forever, color: Colors.red),
      tooltip: 'cancel_subscription_btn'.tr(context),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('confirm_cancel_subscription'.tr(context)),
            content: Text('cancel_subscription_warning'.tr(context)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('back_btn'.tr(context)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  try {
                    await _subscriptionService.cancelSubscription(groupId);
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('cancel_subscription_btn'.tr(context)),
                      ),
                    );
                    _fetchGroups(showLoading: false);
                  } catch (e) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'update_failed_check_internet'.tr(context),
                        ),
                      ),
                    );
                  }
                },
                child: Text('cancel_subscription_btn'.tr(context)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeleteConfirmationDialog extends StatefulWidget {
  final String groupId;
  final String groupName;
  final Future<void> Function(String, {required Function(String) onProgress})
  onDelete;

  const _DeleteConfirmationDialog({
    required this.groupId,
    required this.groupName,
    required this.onDelete,
  });

  @override
  State<_DeleteConfirmationDialog> createState() =>
      _DeleteConfirmationDialogState();
}

class _DeleteConfirmationDialogState extends State<_DeleteConfirmationDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isDeleting = false;
  String _progress = "";

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'delete_system_title'
                  .tr(context)
                  .replaceFirst('%s', widget.groupName),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'delete_system_warning_msg'.tr(context),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Text(
              'type_final_delete_to_confirm'.tr(context),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'type_final_delete_hint'.tr(context),
                fillColor: Colors.red.shade50,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_isDeleting)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 15),
                    Text(
                      _progress,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: Text('cancel_btn'.tr(context)),
        ),
        ElevatedButton(
          onPressed: _isDeleting
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (_passwordController.text !=
                      'final_delete_confirmation_text'.tr(context)) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('text_does_not_match'.tr(context)),
                      ),
                    );
                    return;
                  }

                  setState(() => _isDeleting = true);
                  final navigator = Navigator.of(context);

                  await widget.onDelete(
                    widget.groupId,
                    onProgress: (msg) {
                      if (mounted) setState(() => _progress = msg);
                    },
                  );
                  if (mounted) navigator.pop();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text('confirm_final_delete_btn'.tr(context)),
        ),
      ],
    );
  }
}
