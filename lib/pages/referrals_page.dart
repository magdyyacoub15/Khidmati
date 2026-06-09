import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:math';

import '../services/appwrite_service.dart';
import '../services/referral_service.dart';
import '../l10n/app_translations.dart';

class ReferralsPage extends StatefulWidget {
  final String groupId;

  const ReferralsPage({super.key, required this.groupId});

  @override
  State<ReferralsPage> createState() => _ReferralsPageState();
}

class _ReferralsPageState extends State<ReferralsPage> {
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';

  bool _isLoading = true;
  String _referralCode = ''; // Will initialize in build
  List<models.Document> _referrals = [];
  final Map<String, String> _groupNames = {};
  final Map<String, int> _activeDaysMap = {};

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Check Rewards First (to update UI if needed)
      await ReferralService.checkAndApplyRewards(widget.groupId);

      // 2. Fetch Group Data
      final groupDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: widget.groupId,
      );

      String currentCode = groupDoc.data['referralCode'] ?? '';

      // Ensure Group has a Referral Code
      if (currentCode.isEmpty) {
        currentCode = await _generateUniqueReferralCode();
        try {
          await _databases.updateDocument(
            databaseId: databaseId,
            collectionId: groupsCollectionId,
            documentId: widget.groupId,
            data: {'referralCode': currentCode, 'referralUses': 0},
          );
        } on AppwriteException catch (e) {
          debugPrint("Appwrite Update Error: ${e.message}");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${'check_appwrite_settings'.tr(context)}: ${e.message}',
                ),
              ),
            );
          }
          // Even if saving fails, let's display it so it's not 'غير محدد'
        }
      }

      // 3. Fetch Referrals List
      List<models.Document> refs = [];
      try {
        refs = await ReferralService.getReferralsForGroup(widget.groupId);

        // Fetch group names and active days for each referral
        for (var r in refs) {
          final id = r.data['referredGroupId'];
          if (id != null) {
            // Group Name
            try {
              final gDoc = await _databases.getDocument(
                databaseId: databaseId,
                collectionId: groupsCollectionId,
                documentId: id,
              );
              if (!mounted) return;
              _groupNames[id] =
                  "${gDoc.data['churchName']} - ${gDoc.data['serviceName']}";
            } catch (_) {
              if (!mounted) return;
              _groupNames[id] = 'invited_group'.tr(context);
            }

            // Active Days
            try {
              final records = await _databases.listDocuments(
                databaseId: databaseId,
                collectionId: 'attendance_records',
                queries: [Query.equal('groupId', id), Query.limit(100)],
              );
              final Set<String> uniqueDates = {};
              for (var rec in records.documents) {
                final String? ts = rec.data['timestamp'];
                if (ts != null) {
                  try {
                    final dt = DateTime.parse(ts);
                    uniqueDates.add("${dt.year}-${dt.month}-${dt.day}");
                  } catch (_) {}
                }
              }
              _activeDaysMap[id] = uniqueDates.length;
            } catch (_) {
              _activeDaysMap[id] = 0;
            }
          }
        }
      } catch (e) {
        debugPrint("Error fetching referrals: $e");
      }

      if (mounted) {
        setState(() {
          _referralCode = currentCode;
          _referrals = refs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading referrals page data: $e");
      if (mounted) {
        setState(() {
          _referralCode = 'check_appwrite_settings'.tr(context);
          _isLoading = false;
        });
      }
    }
  }

  Future<String> _generateUniqueReferralCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    String code = '';
    bool isUnique = false;

    while (!isUnique) {
      code =
          'MGR-${List.generate(4, (index) => chars[random.nextInt(chars.length)]).join()}';
      try {
        final query = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: groupsCollectionId,
          queries: [Query.equal('referralCode', code)],
        );
        if (query.documents.isEmpty) isUnique = true;
      } catch (e) {
        return code;
      }
    }
    return code;
  }

  Future<void> _copyCode() async {
    if (_referralCode == 'undefine'.tr(context) || _referralCode.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _referralCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'code_copied_success'.tr(context),
          textAlign: TextAlign.right,
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openTelegram() async {
    final Uri url = Uri.parse("https://t.me/+Eql6H_Ebm_4wMWFk");
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint("Error opening telegram: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_referralCode.isEmpty) _referralCode = 'undefine'.tr(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'referral_and_rewards'.tr(context),
          style: const TextStyle(
            color: Color(0xFF1A237E),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A237E)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1A237E)),
            onPressed: _loadReferralData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReferralData,
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 20),
                  _buildTelegramCard(),
                  const SizedBox(height: 30),
                  Text(
                    'invited_groups_data'.tr(context),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildReferralsList(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.card_giftcard, size: 50, color: Colors.white),
          const SizedBox(height: 10),
          Text(
            'share_code'.tr(context),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          Text(
            'get_free_month'.tr(context),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          GestureDetector(
            onTap: _copyCode,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _referralCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 15),
                  const Icon(Icons.copy, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelegramCard() {
    return InkWell(
      onTap: _openTelegram,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            const Icon(Icons.telegram, color: Colors.blue, size: 40),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'join_telegram'.tr(context),
                    style: const TextStyle(
                      color: Color(0xFF1976D2),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'telegram_desc'.tr(context),
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.blue, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralsList() {
    if (_referrals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.group_off_outlined, size: 50, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              'no_one_used_code'.tr(context),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _referrals.length,
      itemBuilder: (context, index) {
        final doc = _referrals[index];
        final data = doc.data;
        final status = data['status'] ?? 'pending';
        final referredGroupId = data['referredGroupId'] ?? '';
        final groupName =
            _groupNames[referredGroupId] ?? 'new_invited_group'.tr(context);
        final activeDays = _activeDaysMap[referredGroupId] ?? 0;
        final progress = (activeDays / 10.0).clamp(0.0, 1.0);

        bool isRewarded = status == 'rewarded';

        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.church_outlined,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            groupName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isRewarded
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isRewarded
                          ? 'rewarded'.tr(context)
                          : 'under_test'.tr(context),
                      style: TextStyle(
                        color: isRewarded ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'active_days_10'.tr(context),
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    isRewarded
                        ? 'completed_100'.tr(context)
                        : "${(progress * 100).toInt()}% ($activeDays ${'days'.tr(context)})",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isRewarded ? Colors.green : Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: isRewarded ? 1.0 : progress,
                backgroundColor: Colors.grey.shade200,
                color: isRewarded ? Colors.green : Colors.blue,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      },
    );
  }
}
