import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';
import 'subscription_service.dart';

/*
  ===========================================================================
  🚨 SERVER-SIDE SECURITY NOTICE (APPWRITE CLOUD FUNCTION REQUIRED) 🚨
  ===========================================================================
  While the app prevents expired users from seeing Edit/Add buttons, the 
  Appwrite server itself STILL trusts the "team:TEAM_ID" permission natively.
  This means an expired user can use Postman/Python to edit the database.

  To fix this SERVER-SIDE loophole, you must create a CRON Cloud Function
  in your Appwrite Console (e.g. Node.js 18.0) that runs every day and
  removes 'update' and 'delete' permissions from groups whose 
  `subscriptionEndDate` has passed.

  **Copy & Paste this Node.js Appwrite Function:**
  
  ```javascript
  const sdk = require('node-appwrite');

  module.exports = async function (req, res) {
    const client = new sdk.Client();
    const databases = new sdk.Databases(client);

    client
      .setEndpoint('YOUR_ENDPOINT')
      .setProject('YOUR_PROJECT_ID')
      .setKey('YOUR_API_KEY'); // Requires Database Read/Write scopes

    try {
      const dbId = 'main_db'; 
      const now = new Date();
      
      // Get all groups
      const response = await databases.listDocuments(dbId, 'groups', [
        sdk.Query.limit(100)
      ]);

      for (const group of response.documents) {
        if (group.subscriptionEndDate) {
          const endDate = new Date(group.subscriptionEndDate);
          
          if (endDate < now) {
            // Subscription Expired! Downgrade permissions to Read-Only
            const teamId = group.teamId;
            const readOnlyPerms = [
              sdk.Permission.read(sdk.Role.team(teamId))
              // Intentionally stripping update() and delete()
            ];
            
            // Note: You must loop through your collections (students, visits, etc.)
            // and apply `readOnlyPerms` to documents where teamId matches, 
            // OR handle it at the collection level if using Dynamic Roles.
            console.log(`Group ${group.name} expired. (Team: ${teamId})`);
          }
        }
      }
      res.json({ success: true, message: "Checked subscriptions." });
    } catch (error) {
      res.json({ success: false, error: error.message });
    }
  };
  ```
  ===========================================================================
*/

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
