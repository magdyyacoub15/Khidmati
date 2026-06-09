import 'package:flutter/material.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import '../services/appwrite_service.dart';
import 'subscription_page.dart';
import 'super_admin_page.dart';
import '../services/settings_service.dart';
import '../services/notification_service.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service
import '../services/user_service.dart';
import '../services/language_service.dart';
import '../services/sync_service.dart'; // 🚀 Added Sync Service
import '../l10n/app_translations.dart';
import 'tutorial_video_page.dart';
import 'points_type_selector_page.dart';
import 'curriculums_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // Placeholder removed
  final Account _account = AppwriteService().account;
  final Databases _databases = AppwriteService().databases;

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  AnimationController? _animationController;

  // 🚀 Local State for Caching
  Map<String, dynamic>? _cachedUserData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _loadUserData(); // 🚀 Load Data on Init
  }

  // 🚀 Fetch Data with Caching Strategy
  Future<void> _loadUserData() async {
    // 1. Try Loading from Cache
    final cached = await DataCacheService().getCachedUserData();
    if (cached != null) {
      if (mounted) {
        setState(() {
          _cachedUserData = cached;
          _isLoading = false;
        });
      }
    }

    // 2. Fetch Fresh Data (Background)
    try {
      final user = await _account.get();
      final userDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      // 2b. Fetch Status from Membership
      String? groupStatus;
      final activeGroupId = userDoc.data['groupId'] ?? '';
      if (activeGroupId.isNotEmpty) {
        try {
          final membershipRes = await _databases.listDocuments(
            databaseId: databaseId,
            collectionId: AppwriteService.membershipsCollectionId,
            queries: [
              Query.equal('userId', user.$id),
              Query.equal('groupId', activeGroupId),
            ],
          );
          if (membershipRes.total > 0) {
            groupStatus = membershipRes.documents.first.data['status'];
          }
        } catch (e) {
          debugPrint("Error fetching membership status in Profile: $e");
        }
      }

      final Map<String, dynamic> freshData = {
        'id': user.$id,
        'email': user.email,
        'username': userDoc.data['username'] ?? user.email,
        'role': userDoc.data['role'] ?? 'user',
        'groupId': activeGroupId,
        if (groupStatus != null) 'status': groupStatus,
      };

      // 3. Update Cache & UI
      await DataCacheService().cacheUserData(freshData);
      if (mounted) {
        setState(() {
          _cachedUserData = freshData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile data: $e");
      if (mounted && _cachedUserData == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  // Removed checkNotificationStatus as requested

  Future<void> _signOut() async {
    try {
      await UserService().clearSession(); // 🗑️ Clear local cache
      await _account.deleteSession(sessionId: 'current');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint("Error signing out: $e");
      // Force logout anyway for UX
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  void _showGlobalBroadcastDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController(
      text: 'global_broadcast_title'.tr(context),
    );
    final TextEditingController bodyController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'global_broadcast_desc'.tr(context),
            textAlign: TextAlign.right,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'msg_title_label'.tr(context),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyController,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'msg_body_label'.tr(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel_btn'.tr(context)),
            ),
            if (isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: () async {
                  if (bodyController.text.isEmpty) return;

                  setState(() => isLoading = true);
                  try {
                    await NotificationService().sendBroadcast(
                      titleController.text,
                      bodyController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'send_success'.tr(context),
                            textAlign: TextAlign.right,
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'send_failed'
                                .tr(context)
                                .replaceFirst('%s', e.toString()),
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.send),
                label: Text('send_now_btn'.tr(context)),
              ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF0277BD)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'about_security_title'.tr(context),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
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
                'about_app_desc'.tr(context),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(height: 30),
              _buildSecurityPoint(
                'ssl_tls'.tr(context),
                'ssl_tls_desc'.tr(context),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                'app_protection'.tr(context),
                'app_protection_desc'.tr(context),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                'password_encryption'.tr(context),
                'password_encryption_desc'.tr(context),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                'media_security'.tr(context),
                'media_security_desc'.tr(context),
              ),
              const SizedBox(height: 12),
              _buildSecurityPoint(
                'group_data_protection'.tr(context),
                'group_data_protection_desc'.tr(context),
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
      ),
    );
  }

  Widget _buildSecurityPoint(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF0277BD),
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  void _showGroupsDialog(BuildContext context, String currentUserId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _GroupsManagerDialog(userId: currentUserId, databases: _databases),
    );
  }

  void _showFontSizeDialog(BuildContext context, double currentMultiplier) {
    final Map<String, double> sizes = {
      'font_size_small'.tr(context): 0.8,
      'font_size_normal'.tr(context): 1.0,
      'font_size_medium'.tr(context): 1.2,
      'font_size_large'.tr(context): 1.4,
      'font_size_xl'.tr(context): 1.6,
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'select_font_size_title'.tr(context),
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sizes.entries.map((entry) {
            final isSelected = (currentMultiplier - entry.value).abs() < 0.01;
            return ListTile(
              title: Text(
                entry.key,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF0277BD) : Colors.black87,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Color(0xFF0277BD))
                  : null,
              onTap: () {
                SettingsService().setFontSize(entry.value);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'select_language'.tr(context),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLanguageTile('ar', 'arabic'.tr(context), context),
                const Divider(),
                _buildLanguageTile('en', 'english'.tr(context), context),
                const Divider(),
                _buildLanguageTile('fr', 'Français (French)', context),
                const Divider(),
                _buildLanguageTile('es', 'Español (Spanish)', context),
                const Divider(),
                _buildLanguageTile('de', 'Deutsch (German)', context),
                const Divider(),
                _buildLanguageTile('it', 'Italiano (Italian)', context),
                const Divider(),
                _buildLanguageTile('pt', 'Português (Portuguese)', context),
                const Divider(),
                _buildLanguageTile('nl', 'Nederlands (Dutch)', context),
                const Divider(),
                _buildLanguageTile('ru', 'Русский (Russian)', context),
                const Divider(),
                _buildLanguageTile('pl', 'Polski (Polish)', context),
                const Divider(),
                _buildLanguageTile('sv', 'Svenska (Swedish)', context),
                const Divider(),
                _buildLanguageTile('el', 'Ελληνικά (Greek)', context),
                const Divider(),
                _buildLanguageTile('uk', 'Українська (Ukrainian)', context),
                const Divider(),
                _buildLanguageTile('ro', 'Română (Romanian)', context),
                const Divider(),
                _buildLanguageTile('cs', 'Čeština (Czech)', context),
                const Divider(),
                _buildLanguageTile('hu', 'Magyar (Hungarian)', context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(
    String langCode,
    String label,
    BuildContext context,
  ) {
    return ListTile(
      title: Text(label, textAlign: TextAlign.center),
      onTap: () {
        LanguageService().changeLanguage(langCode);
        Navigator.pop(context);
      },
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

  @override
  Widget build(BuildContext context) {
    // 🚀 Use Local State instead of FutureBuilder
    if (_isLoading && _cachedUserData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Default values if data load failed
    final String displayName =
        _cachedUserData?['username'] ?? 'user_label'.tr(context);
    final String email = _cachedUserData?['email'] ?? "";
    final String role = _cachedUserData?['role'] ?? "user";
    final String? groupId = _cachedUserData?['groupId'];
    final String? userId = _cachedUserData?['id'];

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService().currentLocale,
      builder: (context, locale, child) {
        return Scaffold(
          body: Stack(
            children: [
              _buildPremiumBackground(),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: RefreshIndicator(
                      onRefresh: _loadUserData,
                      child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              // 🚀 User Info Section (Centered)
                              SizedBox(
                                width: double.infinity,
                                child: Column(
                                  children: [
                                    const SizedBox(height: 40),
                                    const CircleAvatar(
                                      radius: 50,
                                      backgroundColor: Colors.white24,
                                      child: Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12.0),
                                      child: Text(
                                        email,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Action Icons (Positioned at far right)
                              Positioned(
                                right: 16,
                                top: 10,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    ValueListenableBuilder<double>(
                                      valueListenable:
                                          SettingsService().fontSizeMultiplier,
                                      builder: (context, currentMultiplier, _) {
                                        return IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(
                                            Icons.format_size,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          onPressed: () => _showFontSizeDialog(
                                            context,
                                            currentMultiplier,
                                          ),
                                          tooltip: 'font_size'.tr(context),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.language,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showLanguageDialog(context),
                                      tooltip: 'change_language'.tr(context),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.groups,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        if (userId != null) {
                                          _showGroupsDialog(context, userId);
                                        }
                                      },
                                      tooltip: 'my_groups'.tr(context),
                                    ),
                                    if (email == 'magdyyacoub41@gmail.com')
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.campaign_rounded,
                                          color: Colors.orangeAccent,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _showGlobalBroadcastDialog(context),
                                        tooltip: 'global_notification'.tr(
                                          context,
                                        ),
                                      ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.info_outline,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () => _showInfoDialog(context),
                                      tooltip: 'about_app'.tr(context),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),

                          // Contact Us Section
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'contact_us'.tr(context),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildSocialButton(
                                        icon: Icons.chat_bubble_outline,
                                        label: 'whatsapp'.tr(context),
                                        color: Colors.green.shade400,
                                        onTap: () => _launchURL(
                                          "https://wa.me/qr/PVCRF6JDXXLVD1",
                                        ),
                                      ),
                                      _buildSocialButton(
                                        icon: Icons.camera_alt_outlined,
                                        label: 'instagram'.tr(context),
                                        color: Colors.pink.shade400,
                                        onTap: () => _launchURL(
                                          "https://www.instagram.com/magdyyacoub0?igsh=MXFyb2ZwcjJtbGNwYg==",
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          // جروب التطبيق Section
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'app_group'.tr(context),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildSocialButton(
                                        icon: Icons.chat_bubble_outline,
                                        label: 'official_whatsapp'.tr(context),
                                        color: Colors.green.shade400,
                                        onTap: () => _launchURL(
                                          "https://chat.whatsapp.com/LcWrv2ocEtPB74oLbIaAUW?mode=hq1tcla",
                                        ),
                                      ),
                                      _buildSocialButton(
                                        icon: Icons.send,
                                        label: 'official_telegram'.tr(context),
                                        color: Colors.blue.shade400,
                                        onTap: () => _launchURL(
                                          "https://t.me/+Eql6H_Ebm_4wMWFk",
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Subscription Button
                          if (role != 'user' && groupId != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SubscriptionPage(groupId: groupId),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.star,
                                  color: Colors.blue,
                                ),
                                label: Text(
                                  'subscriptions'.tr(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          // Tutorial Video Button (Matched Styling)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 15,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const TutorialVideoPage(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.play_circle_fill,
                                color: Colors.redAccent,
                                size: 28,
                              ),
                              label: Text(
                                'tutorial_video_btn'.tr(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(double.infinity, 50),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),

                          // Points System Button
                          if (groupId != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const PointsTypeSelectorPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.stars,
                                  color: Colors.orange,
                                  size: 28,
                                ),
                                label: const Text(
                                  'نظام النقاط',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          // المناهج والكرازة Button
                          if (groupId != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CurriculumsPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.menu_book_rounded,
                                  color: Colors.purpleAccent,
                                  size: 28,
                                ),
                                label: const Text(
                                  'المناهج والكرازة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          // Super Admin Button
                          if (email == 'magdyyacoub41@gmail.com')
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 15,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SuperAdminPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.red,
                                ),
                                label: Text('super_admin_panel'.tr(context)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 50),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                            ),

                          const SizedBox(height: 32),

                          ElevatedButton.icon(
                            onPressed: () => _signOut(),
                            icon: const Icon(Icons.logout),
                            label: Text('logout'.tr(context)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 🛠️ Debugging Section
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _GroupsManagerDialog extends StatefulWidget {
  final String userId;
  final Databases databases;

  const _GroupsManagerDialog({required this.userId, required this.databases});

  @override
  State<_GroupsManagerDialog> createState() => _GroupsManagerDialogState();
}

class _GroupsManagerDialogState extends State<_GroupsManagerDialog> {
  bool _isLoading = true;
  bool _isSwitchingGroup = false; // Add state for group switching loading
  List<models.Document> _memberships = [];
  String? _activeGroupId; // 🚀 Added to track active group
  final TextEditingController _joinCodeController = TextEditingController();
  // Cloud Function removed in favor of Admin Approval flow

  @override
  void initState() {
    super.initState();
    _loadMemberships();
  }

  Future<void> _loadMemberships({bool isRetry = false}) async {
    final String unnamedGroupMsg = 'unnamed_group'.tr(context);
    try {
      final membershipResult = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [Query.equal('userId', widget.userId)],
      );

      final groupIds = membershipResult.documents
          .map((m) => m.data['groupId'] as String)
          .toList();

      Map<String, String> groupNames = {};
      if (groupIds.isNotEmpty) {
        final groupsResult = await widget.databases.listDocuments(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.groupsCollectionId,
          queries: [Query.equal('groupId', groupIds)],
        );
        for (var g in groupsResult.documents) {
          final serviceName = g.data['serviceName'] ?? unnamedGroupMsg;
          final stageName = g.data['churchName'] ?? '';
          groupNames[g.data['groupId']] = stageName.isNotEmpty
              ? "$serviceName - $stageName"
              : serviceName;
        }
      }

      // 1.5. Self-healing: Check if primary group is missing from memberships
      final userDoc = await widget.databases.getDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.usersCollectionId,
        documentId: widget.userId,
      );
      final primaryGroupId = userDoc.data['groupId'] ?? '';

      if (mounted) {
        setState(() {
          _activeGroupId = primaryGroupId;
        });
      }

      if (primaryGroupId.isNotEmpty && !groupIds.contains(primaryGroupId)) {
        debugPrint(
          "Self-healing: Primary group $primaryGroupId missing from memberships. Creating...",
        );
        await widget.databases.createDocument(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.membershipsCollectionId,
          documentId: ID.unique(),
          data: {
            'userId': widget.userId,
            'groupId': primaryGroupId,
            'role': userDoc.data['role'] ?? 'user',
            'joinedAt': DateTime.now().toIso8601String(),
          },
        );
        // Reload once to include the new membership, but prevent infinite loops
        if (!isRetry) {
          return _loadMemberships(isRetry: true);
        } else {
          debugPrint(
            "Self-healing failed to reflect immediately. Proceeding anyway.",
          );
        }
      }

      if (mounted) {
        setState(() {
          _memberships = membershipResult.documents;
          _groupNamesMap = groupNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading memberships: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, String> _groupNamesMap = {};

  Future<void> _switchGroup(String groupId) async {
    setState(() => _isSwitchingGroup = true); // Use new state
    final String noMembershipFoundMsg = 'no_membership_found'.tr(context);
    final String groupPendingApprovalMsg = 'group_pending_admin_approval'.tr(
      context,
    );
    final String switchErrorMsg = 'switch_error'.tr(context);
    try {
      // 1. Fetch role for this group from memberships (using Query instead of direct ID)
      final membershipRes = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupId', groupId),
        ],
      );

      if (membershipRes.total == 0) {
        throw Exception(noMembershipFoundMsg);
      }

      final membership = membershipRes.documents.first;
      final role = membership.data['role'] ?? 'user';
      final status = membership.data['status'] ?? 'approved';

      if (status == 'pending') {
        throw Exception(groupPendingApprovalMsg);
      }

      // 2. Fetch teamId from Group document
      final groupDoc = await widget.databases.getDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.groupsCollectionId,
        documentId: groupId,
      );
      final teamId = groupDoc.data['teamId'] ?? '';

      // 3. Update user doc with groupId AND role
      await widget.databases.updateDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.usersCollectionId,
        documentId: widget.userId,
        data: {'groupId': groupId, 'role': role},
      );

      // 4. Update Cache IMMEDIATELY
      await DataCacheService().cacheUserGroupId(
        widget.userId,
        groupId,
        teamId,
        role,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error switching group: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switchErrorMsg.replaceFirst('%s', e.toString())),
          ),
        );
        setState(
          () => _isSwitchingGroup = false,
        ); // Stop loading indicator on error
      }
    }
  }

  void _confirmSwitchWithPendingOps(String groupId) async {
    final hasOps = await DataCacheService().hasPendingOperations(
      _activeGroupId,
    );
    if (!hasOps) {
      _switchGroup(groupId);
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text('pending_sync_warning'.tr(context)),
          ],
        ),
        content: Text('pending_sync_message'.tr(context)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              SyncService().syncAll(_activeGroupId ?? '');
            },
            child: Text('sync_now'.tr(context)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _switchGroup(groupId);
            },
            child: Text('switch_anyway'.tr(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMembership(String membershipId, String gid) async {
    setState(() => _isLoading = true);
    try {
      await widget.databases.deleteDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: membershipId,
      );
      // Refresh list
      await _loadMemberships(isRetry: true);
    } catch (e) {
      debugPrint("Error deleting membership: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'leave_group_error'.tr(context).replaceFirst('%s', e.toString()),
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showLeaveConfirmation(String membershipId, String gid, String gname) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('confirm_leave_group_title'.tr(context)),
        content: Text('confirm_leave_group_message'.tr(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel_btn'.tr(context)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteMembership(membershipId, gid);
            },
            child: Text('leave_group_btn'.tr(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _joinNewGroup() async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    final String invalidGroupCodeMsg = 'invalid_group_code'.tr(context);
    final String alreadyMemberMsg = 'already_member_or_pending'.tr(context);
    final String joinRequestSentMsg = 'join_request_sent'.tr(context);

    try {
      // 1. Validate Code
      final groups = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.groupsCollectionId,
        queries: [Query.equal('joinCode', code)],
      );

      if (groups.total == 0) {
        throw Exception(invalidGroupCodeMsg);
      }

      final group = groups.documents.first;
      final groupId = group.data['groupId'];

      // 2. Check if already joined
      final existing = await widget.databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [
          Query.equal('userId', widget.userId),
          Query.equal('groupId', groupId),
        ],
      );

      if (existing.total > 0) {
        throw Exception(alreadyMemberMsg);
      }

      // 3. Create Pending Membership
      await widget.databases.createDocument(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: ID.unique(),
        data: {
          'userId': widget.userId,
          'groupId': groupId,
          'role': 'user',
          'status': 'pending', // 🚀 Pending approval
          'joinedAt': DateTime.now().toIso8601String(),
        },
      );

      // 🚀 UPDATE CACHE IMMEDIATELY TO PREVENT DATA LEAK
      await DataCacheService().cacheUserData({
        'groupId': groupId,
        'role': 'user',
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(joinRequestSentMsg),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context); // Close groups manager dialog
      }
    } catch (e) {
      debugPrint("Error joining group: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'my_groups'.tr(context),
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Stack(
              children: [
                SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ..._memberships.map((m) {
                            final gid = m.data['groupId'];
                            final mid = m.$id;
                            final name =
                                _groupNamesMap[gid] ??
                                'loading_data'.tr(context);
                            final status = m.data['status'] ?? 'approved';
                            final isPending = status == 'pending';

                            // Check if this is the active group
                            final bool isActive = _activeGroupId == gid;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: Icon(
                                isPending ? Icons.hourglass_top : Icons.church,
                                color: isPending
                                    ? Colors.orange
                                    : (isActive ? Colors.green : Colors.blue),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: isActive
                                    ? () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'cannot_leave_active_group'.tr(
                                                context,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    : () => _showLeaveConfirmation(
                                        mid,
                                        gid,
                                        name,
                                      ),
                              ),
                              title: Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                textDirection: TextDirection.rtl,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    name,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (isPending)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'pending_status'.tr(context),
                                        style: TextStyle(
                                          color: Colors.orange.shade900,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                "ID: $gid",
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              onTap: isActive || isPending
                                  ? null
                                  : () => _confirmSwitchWithPendingOps(gid),
                            );
                          }),
                          const Divider(),
                          TextField(
                            controller: _joinCodeController,
                            decoration: InputDecoration(
                              hintText: 'new_join_code_hint'.tr(context),
                              prefixIcon: const Icon(Icons.add),
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Add Loading Indicator Overlay
                if (_isSwitchingGroup)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withAlpha(150),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 10),
                            Text(
                              'switching_group_msg'.tr(context),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _isSwitchingGroup ? null : () => Navigator.pop(context),
          child: Text('cancel_btn'.tr(context)),
        ),
        ElevatedButton(
          onPressed: _isSwitchingGroup ? null : _joinNewGroup,
          child: Text('join_btn'.tr(context)),
        ),
      ],
    );
  }
}
