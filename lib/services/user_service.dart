import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_service.dart';
import 'package:flutter/foundation.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  String? _cachedName;
  final Account _account = AppwriteService().account;
  final Databases _databases = AppwriteService().databases;

  // ⚠️ يجب إنشاء Collection في Appwrite وتسميته 'users_info' أو تغييره هنا
  static const String databaseId =
      AppwriteService.databaseId; // معرف قاعدة البيانات
  static const String collectionId = 'users_info'; // معرف الجدول

  /// Fetches the current user's username.
  Future<String> getCurrentUserName() async {
    if (_cachedName != null && _cachedName!.isNotEmpty) {
      return _cachedName!;
    }

    // Try SharedPreferences first
    final prefs = await SharedPreferences.getInstance();
    String? localName = prefs.getString('username');
    if (localName != null && localName.isNotEmpty && !localName.contains('@')) {
      _cachedName = localName;
      return localName;
    }

    try {
      // Try Appwrite Account
      final user = await _account.get();
      if (user.name.isNotEmpty) {
        _cachedName = user.name;
        await prefs.setString('username', user.name);
        return user.name;
      }

      // Try Appwrite Databases (as fallback for detailed info)
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: user.$id,
      );

      if (doc.data.containsKey('username') && doc.data['username'] != null) {
        String appwriteName = doc.data['username'];
        if (appwriteName.isNotEmpty) {
          _cachedName = appwriteName;
          await prefs.setString('username', appwriteName);
          return appwriteName;
        }
      }
    } catch (e) {
      debugPrint("Error fetching username from Appwrite: $e");
    }

    // Fallback
    try {
      final user = await _account.get();
      String fallbackName = user.email.split('@').first;
      _cachedName = fallbackName;
      return fallbackName;
    } catch (_) {
      return "Guest";
    }
  }

  /// Forces a refresh of the username
  Future<String> refreshUserName() async {
    _cachedName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    return getCurrentUserName();
  }

  /// Persist User ID
  Future<void> _cacheUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
  }

  /// Get Cached User ID
  Future<String?> getCachedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  /// Get the full User object
  Future<models.User?> getCurrentUser() async {
    try {
      final user = await _account.get();
      await _cacheUserId(user.$id); // Cache ID on success
      return user;
    } catch (e) {
      return null;
    }
  }

  /// Get the user role (admin or user)
  Future<String> getUserRole() async {
    try {
      final user = await _account.get();
      await _cacheUserId(user.$id); // Cache ID
      if (user.labels.contains('admin')) return 'admin';

      if (user.prefs.data.containsKey('role')) {
        return user.prefs.data['role'];
      }

      // Fallback to database
      try {
        final doc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: collectionId,
          documentId: user.$id,
        );
        return doc.data['role'] ?? 'user';
      } catch (_) {
        return 'user';
      }
    } catch (e) {
      // Offline? Return mocked or cached role if possible?
      // AttendancePage handles cache lookup manually, so we just return 'user' here or null?
      // Keeping it 'user' to avoid crash, but Page should handle "no network".
      return 'user';
    }
  }

  /// Get the user's Group ID with fallback
  Future<String?> fetchUserGroupId() async {
    try {
      final user = await _account.get();
      await _cacheUserId(user.$id); // Cache ID

      // 1. Try Prefs
      if (user.prefs.data.containsKey('groupId') &&
          user.prefs.data['groupId'] != null) {
        return user.prefs.data['groupId'];
      }

      // 2. Try Database
      try {
        final doc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: collectionId,
          documentId: user.$id,
        );
        return doc.data['groupId'];
      } catch (_) {
        return null; // Not found in DB either
      }
    } catch (e) {
      debugPrint("Error fetching groupId: $e");
      return null;
    }
  }

  /// Clears all cached user data (Call this on Logout)
  Future<void> clearSession() async {
    _cachedName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('user_id');
    debugPrint("✅ UserService: Session cleared.");
  }
}
