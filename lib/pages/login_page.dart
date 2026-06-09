import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/appwrite_service.dart';
import '../services/language_service.dart';
import '../l10n/app_translations.dart';
import 'tutorial_video_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  Future<void> _handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('enter_email_password'.tr(context));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🚀 تسجيل الدخول عبر Appwrite
      try {
        await AppwriteService().account.deleteSession(sessionId: 'current');
      } catch (_) {} // Ignore if no session exists

      await AppwriteService().account.createEmailPasswordSession(
        email: email,
        password: password,
      );

      final account = await AppwriteService().account.get();
      final userId = account.$id;

      // Fetch user info to get groupId
      final userDoc = await AppwriteService().databases.getDocument(
        databaseId: AppwriteService.databaseId,
        collectionId:
            'users_info', // Assuming this is the ID, verify if it's a constant
        documentId: userId,
      );
      final groupId = userDoc.data['groupId'] ?? '';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userId', userId);
      await prefs.setString('groupId', groupId);

      if (!mounted) return;

      // إظهار تنبيه الاشتراك في القناة قبل الانتقال للداشبورد
      await _showTelegramJoinDialog();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
    } on AppwriteException catch (e) {
      String message = 'login_error_title'.tr(context);
      if (e.code == 401) {
        message = 'invalid_credentials'.tr(context);
      } else if (e.code == 404) {
        message = 'user_not_found'.tr(context);
      }
      _showError("$message: ${e.message}");
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
          'update_follow_up'.tr(context),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.send, size: 40, color: Colors.blue),
                SizedBox(width: 15),
                Icon(Icons.chat_bubble_outline, size: 40, color: Colors.green),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              'join_social_groups_msg'.tr(context),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('later_btn'.tr(context)),
          ),
          Column(
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final Uri url = Uri.parse(
                    "https://chat.whatsapp.com/LcWrv2ocEtPB74oLbIaAUW?mode=hq1tcla",
                  );
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.chat, color: Colors.white),
                label: Text('whatsapp_group_btn'.tr(context)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final Uri url = Uri.parse("https://t.me/+Eql6H_Ebm_4wMWFk");
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.send, color: Colors.white),
                label: Text('telegram_channel_btn'.tr(context)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService().currentLocale,
      builder: (context, locale, child) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              // 🔵 Background Blobs
              Positioned(
                top: -100,
                left: -100,
                child: _buildBlob(
                  300,
                  const Color(0xFF0D47A1).withValues(alpha: 0.8),
                ),
              ),
              Positioned(
                top: 200,
                right: -150,
                child: _buildBlob(
                  400,
                  const Color(0xFF1976D2).withValues(alpha: 0.6),
                ),
              ),

              SafeArea(
                child: Center(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                      await Future.delayed(const Duration(milliseconds: 500));
                    },
                    child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 🏢 App Logo/Title + Language Button (Responsive)
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'app_title_khidmati'.tr(context),
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E),
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showLanguageDialog(context),
                              icon: const Icon(
                                Icons.language,
                                color: Color(0xFF1A237E),
                                size: 30,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'welcome_msg'.tr(context),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'login_to_continue'.tr(context),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // 📝 Login Form Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildModernTextField(
                                controller: emailController,
                                hint: 'email_label'.tr(context),
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 20),
                              _buildModernTextField(
                                controller: passwordController,
                                hint: 'password_label'.tr(context),
                                icon: Icons.lock_outline,
                                isPassword: true,
                                isPasswordVisible: _isPasswordVisible,
                                onTogglePassword: () => setState(
                                  () =>
                                      _isPasswordVisible = !_isPasswordVisible,
                                ),
                              ),
                              const SizedBox(height: 30),

                              // Login Button
                              SizedBox(
                                width: double.infinity,
                                height: 55,
                                child: _isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : ElevatedButton(
                                        onPressed: _handleLogin,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF1A73E8,
                                          ),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          'login_btn'.tr(context),
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

                        const SizedBox(height: 25),

                        // 🔗 Action Buttons Wrap (Responsive)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 25,
                          runSpacing: 20,
                          children: [
                            _buildActionChip(
                              label: 'join_group_btn'.tr(context),
                              icon: Icons.group_add_outlined,
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/join_group'),
                            ),
                            _buildActionChip(
                              label: 'create_group_btn'.tr(context),
                              icon: Icons.add_business_outlined,
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/create_group'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 25),

                        // 🎥 Tutorial Video Action Chip (In its place)
                        _buildActionChip(
                          label: 'tutorial_video_btn'.tr(context),
                          icon: Icons.play_circle_fill,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TutorialVideoPage(),
                              ),
                            );
                          },
                        ),
                      ],
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

  Widget _buildBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isPasswordVisible = false,
    VoidCallback? onTogglePassword,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isPasswordVisible,
        keyboardType: keyboardType,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: onTogglePassword,
                )
              : null,
          suffixIcon: Icon(icon, color: const Color(0xFF95A1AC)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF1A73E8), size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E),
            ),
          ),
        ],
      ),
    );
  }
}
