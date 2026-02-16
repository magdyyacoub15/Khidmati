import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/appwrite_service.dart';
import '../services/data_cache_service.dart';

class JoinGroupPage extends StatefulWidget {
  const JoinGroupPage({super.key});

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController groupCodeController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  // Cloud Function removed in favor of Admin Approval Flow

  // Removed unused database constants

  Future<void> _handleJoin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirm = confirmPasswordController.text.trim();
    final username = usernameController.text.trim();
    final groupCode = groupCodeController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty ||
        username.isEmpty ||
        groupCode.isEmpty) {
      _showError("يرجى إكمال جميع الحقول");
      return;
    }

    if (password != confirm) {
      _showError("كلمات المرور غير متطابقة");
      return;
    }

    setState(() => _isLoading = true);

    String userId = ''; // 🚀 Declare here

    try {
      // 1. Authenticate User (Robust Handling)
      try {
        final currentAccount = await _account.get();
        userId = currentAccount.$id;
      } catch (_) {
        // No session, create account and session
        try {
          userId = ID.unique();
          await _account.create(
            userId: userId,
            email: email,
            password: password,
            name: username,
          );
        } on AppwriteException catch (e) {
          if (e.code == 409) {
            // Already exists, just login
          } else {
            rethrow;
          }
        }

        await _account.createEmailPasswordSession(
          email: email,
          password: password,
        );
        final currentAccount = await _account.get();
        userId = currentAccount.$id;
      }

      // 2. Client-Side Group Validation
      // Search for the group by join code
      final groupResult = await _databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.groupsCollectionId,
        queries: [Query.equal('joinCode', groupCode)],
      );

      if (groupResult.total == 0) {
        _showError("كود المجموعة غير صحيح");
        return;
      }

      final groupDoc = groupResult.documents.first;
      final groupId = groupDoc.data['groupId'];

      // 3. Create/Update User Info
      try {
        await _databases.updateDocument(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.usersCollectionId,
          documentId: userId,
          data: {'username': username, 'groupId': groupId, 'role': 'user'},
        );
      } catch (e) {
        // Create if not exists
        await _databases.createDocument(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.usersCollectionId,
          documentId: userId,
          data: {
            'userId': userId,
            'email': email,
            'username': username,
            'groupId': groupId,
            'role': 'user',
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
      }

      // 4. Create Pending Membership Document (Replacement for Cloud Function)
      final existingMemberships = await _databases.listDocuments(
        databaseId: AppwriteService.databaseId,
        collectionId: AppwriteService.membershipsCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('groupId', groupId),
        ],
      );

      if (existingMemberships.total == 0) {
        await _databases.createDocument(
          databaseId: AppwriteService.databaseId,
          collectionId: AppwriteService.membershipsCollectionId,
          documentId: ID.unique(),
          data: {
            'userId': userId,
            'groupId': groupId,
            'role': 'user',
            'status': 'pending', // 🚀 User is now in 'pending' status
            'joinedAt': DateTime.now().toIso8601String(),
          },
        );
        // 🚀 UPDATE CACHE IMMEDIATELY TO PREVENT DATA LEAK
        await DataCacheService().cacheUserData({
          'groupId': groupId,
          'role': 'user',
          'status': 'pending',
        });
      }

      // 5. Success Flow
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);

      if (!mounted) return;

      _showTelegramJoinDialog();
    } on AppwriteException catch (e) {
      _showError(e.message ?? "حدث خطأ أثناء الاتصال");
    } catch (e) {
      _showError("حدث خطأ غير متوقع: $e");
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
        title: const Text(
          "تم إرسال الطلب بنجاح! 🎉",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send, size: 50, color: Colors.blue),
            SizedBox(height: 15),
            Text(
              "لقد تم تسجيل بياناتك وبانتظار موافقة الأدمن. يرجى الاشتراك في قناة التليجرام لمتابعة آخر التحديثات وحل المشاكل التقنية.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/dashboard',
                (route) => false,
              );
            },
            child: const Text("لاحقاً"),
          ),
          ElevatedButton(
            onPressed: () async {
              final Uri url = Uri.parse("https://t.me/+Eql6H_Ebm_4wMWFk");
              try {
                if (!await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                )) {
                  await launchUrl(url, mode: LaunchMode.platformDefault);
                }
              } catch (e) {
                debugPrint("Error launching Telegram: $e");
              }
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/dashboard',
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("الاشتراك الآن"),
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
        title: const Text(
          "الالتحاق بمجموعة",
          style: TextStyle(
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
          // Background Blob
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
              ),
            ),
          ),

          SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "بيانات الالتحاق",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "أدخل الكود الخاص بمجموعتك لتنضم إليها",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 30),

                // Form Container
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
                      _buildField(
                        controller: usernameController,
                        hint: "اسم المستخدم",
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        controller: emailController,
                        hint: "البريد الإلكتروني",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        controller: passwordController,
                        hint: "كلمة المرور",
                        icon: Icons.lock_outline,
                        isPassword: true,
                        isPasswordVisible: _isPasswordVisible,
                        onToggle: () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible,
                        ),
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        controller: confirmPasswordController,
                        hint: "تأكيد كلمة المرور",
                        icon: Icons.lock_reset_outlined,
                        isPassword: true,
                        isPasswordVisible: _isPasswordVisible,
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        controller: groupCodeController,
                        hint: "كود الالتحاق",
                        icon: Icons.vpn_key_outlined,
                      ),
                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _handleJoin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A73E8),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text(
                                  "التحاق الآن",
                                  style: TextStyle(
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
        ],
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
          prefixIcon: isPassword && onToggle != null
              ? IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: onToggle,
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
}
