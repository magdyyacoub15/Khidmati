import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import '../services/appwrite_service.dart';
import '../services/team_service.dart';
import '../services/referral_service.dart';
import '../l10n/app_translations.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController countryController = TextEditingController();
  final TextEditingController serviceNameController = TextEditingController();
  final TextEditingController churchNameController = TextEditingController();
  final TextEditingController referralCodeController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;

  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';
  static const String usersCollectionId = 'users_info';

  Future<String> _generateUniqueGroupCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();

    while (true) {
      String code = List.generate(
        6,
        (index) => chars[random.nextInt(chars.length)],
      ).join();

      // Check if this code exists in Appwrite
      try {
        final result = await _databases.listDocuments(
          databaseId: databaseId,
          collectionId: groupsCollectionId,
          queries: [Query.equal('joinCode', code)],
        );

        if (result.total == 0) {
          return code;
        }
      } catch (e) {
        // If query fails (collection doesn't exist yet?), we might just return it or handle error
        return code;
      }
    }
  }

  Future<void> _handleCreateGroup() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirm = confirmPasswordController.text.trim();
    final username = usernameController.text.trim();
    final service = serviceNameController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty ||
        username.isEmpty ||
        service.isEmpty) {
      _showError('fill_required_fields'.tr(context));
      return;
    }

    if (password != confirm) {
      _showError('passwords_not_match'.tr(context));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Generate Unique Join Code
      final joinCode = await _generateUniqueGroupCode();

      // 2. Create Admin Account
      final userId = ID.unique();
      await _account.create(
        userId: userId,
        email: email,
        password: password,
        name: username,
      );

      // Login immediately to perform database operations
      try {
        await _account.deleteSession(sessionId: 'current');
      } catch (_) {} // Ignore if no session exists

      await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );

      // 3. Create Appwrite Team
      String? teamId;
      try {
        // Use the group name or service name for the team
        teamId = await TeamService().createTeam(service);
      } catch (e) {
        debugPrint("Error creating team: $e");
        // We continue even if team creation fails?
        // Ideally we should stop, but for now let's allow fallback or retry later.
      }

      // 4. Create Group Record
      final groupId = ID.unique();
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: groupsCollectionId,
        documentId: groupId,
        data: {
          'groupId': groupId,
          'teamId': teamId, // 🆕 Store Team ID
          'joinCode': joinCode,
          'serviceName': service,
          'churchName': churchNameController.text.trim(),
          'country': countryController.text.trim(),
          'phone': phoneController.text.trim(),
          'adminEmail': email,
          'createdAt': DateTime.now().toIso8601String(),
          'subscriptionEndDate': DateTime.now()
              .add(const Duration(days: 60))
              .toIso8601String(),
          'isTrial': true,
        },
      );

      // 4. Create Admin User Info Record
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: userId,
        data: {
          'userId': userId,
          'email': email,
          'username': username,
          'groupId': groupId,
          'role': 'admin',
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      // 4.5 Create Membership for Admin (Ensures visibility in "My Groups")
      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        documentId: ID.unique(),
        data: {
          'userId': userId,
          'groupId': groupId,
          'role': 'admin',
          'status': 'approved', // 🚀 Admins are approved by default
          'joinedAt': DateTime.now().toIso8601String(),
        },
      );

      // 5. Success Flow
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);

      if (!mounted) return;

      // Submit Referral if a code was provided (Silently, without blocking)
      final referralCode = referralCodeController.text.trim();
      if (referralCode.isNotEmpty) {
        ReferralService.submitReferral(referralCode, groupId).then((success) {
          if (success) {
            debugPrint("Referral submitted successfully.");
          } else {
            debugPrint("Referral submission failed or invalid.");
          }
        });
      }

      await _showTelegramJoinDialog();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
    } on AppwriteException catch (e) {
      _showError(e.message ?? 'error_creating_group'.tr(context));
    } catch (e) {
      _showError(
        'unexpected_error'.tr(context).replaceFirst('%s', e.toString()),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showTelegramJoinDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'updates_channel'.tr(context),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send, size: 50, color: Colors.blue),
            const SizedBox(height: 15),
            Text(
              'telegram_subscribe_msg'.tr(context),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('later'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              final Uri url = Uri.parse("https://t.me/+Eql6H_Ebm_4wMWFk");
              try {
                if (!await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                )) {
                  // Fallback
                  await launchUrl(url, mode: LaunchMode.platformDefault);
                }
              } catch (e) {
                debugPrint("Error launching Telegram: $e");
              }
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text('subscribe_now'.tr(context)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.right),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'create_new_group'.tr(context),
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
      ),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A73E8).withValues(alpha: 0.05),
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: () async {
              setState(() {});
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildSectionTitle('admin_account_data'.tr(context)),
                      _buildField(
                        controller: usernameController,
                        hint: 'personal_name'.tr(context),
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: emailController,
                        hint: 'email'.tr(context),
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: passwordController,
                        hint: 'password'.tr(context),
                        icon: Icons.lock_outline,
                        isPassword: true,
                        isPasswordVisible: _isPasswordVisible,
                        onToggle: () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: confirmPasswordController,
                        hint: 'confirm_password'.tr(context),
                        icon: Icons.lock_reset_outlined,
                        isPassword: true,
                        isPasswordVisible: _isPasswordVisible,
                      ),

                      const Divider(height: 40),
                      _buildSectionTitle('church_data'.tr(context)),
                      _buildField(
                        controller: serviceNameController,
                        hint: 'service_name'.tr(context),
                        icon: Icons.church,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: churchNameController,
                        hint: 'church_stage'.tr(context),
                        icon: Icons.map_outlined,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: phoneController,
                        hint: 'phone_number'.tr(context),
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: countryController,
                        hint: 'country'.tr(context),
                        icon: Icons.public_outlined,
                      ),
                      const Divider(height: 40),
                      _buildSectionTitle('optional_referral_code'.tr(context)),
                      _buildField(
                        controller: referralCodeController,
                        hint: 'subscription_referral_code'.tr(context),
                        icon: Icons.card_giftcard,
                      ),

                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _handleCreateGroup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A73E8),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: Text(
                                  'save_and_create'.tr(context),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A237E),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isPasswordVisible = false,
    VoidCallback? onToggle,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isPasswordVisible,
        keyboardType: keyboardType,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
          prefixIcon: isPassword && onToggle != null
              ? IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: onToggle,
                )
              : null,
          suffixIcon: Icon(icon, color: const Color(0xFF95A1AC), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}
