import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';
import 'subscription_service.dart';

class PermissionService {
  static final Account _account = AppwriteService().account;
  static final Databases _databases = AppwriteService().databases;
  static final SubscriptionService _subscriptionService = SubscriptionService();

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';

  // Get user role
  static Future<String?> getUserRole(String groupId) async {
    try {
      final user = await _account.get();
      final userDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: usersCollectionId,
        documentId: user.$id,
      );

      // Ensure the user belongs to the group we are checking against, or is a super admin style check?
      // Logic: Role is stored in user doc. We trust it if groupId matches.
      if (userDoc.data['groupId'] == groupId) {
        return userDoc.data['role'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> isAdmin(String groupId) async {
    final role = await getUserRole(groupId);
    return role == 'admin';
  }

  static Future<bool> isCreator(String creatorId) async {
    try {
      final user = await _account.get();
      return user.$id == creatorId;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canEditOrDelete(String creatorId, String groupId) async {
    // First check subscription
    if (!await canWrite(groupId)) return false;

    return await isCreator(creatorId) || await isAdmin(groupId);
  }

  // 🆕 Write Permission Check (Enforces Subscription)
  // 🆕 Write Permission Check (Enforces Subscription & Connectivity)
  static Future<bool> canWrite(String groupId) async {
    final status = await _subscriptionService.checkSubscriptionStatus(groupId);

    // Strict Policy: Active, Trial, or Offline (trust cache for now, Sync blocks later if invalid)
    return status == SubscriptionStatus.active ||
        status == SubscriptionStatus.trial ||
        status == SubscriptionStatus.offline;
  }

  /// 🆕 Generate Team Permission String
  static String team(String teamId, {String role = 'member'}) {
    // Appwrite syntax: 'team:TEAM_ID' or 'team:TEAM_ID/owner'
    if (role == 'member') {
      return 'team:$teamId';
    } else {
      return 'team:$teamId/$role';
    }
  }
}
