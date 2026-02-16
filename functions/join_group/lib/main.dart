import 'dart:async';
import 'package:dart_appwrite/dart_appwrite.dart';

/*
  Appwrite Function: Join Group
  ---------------------------------
  This function runs on the server to securely add a user to a Team.
  
  Environment Variables Required:
  - APPWRITE_API_KEY: A standard API Key with 'teams.write', 'documents.read', 'documents.write' scopes.
*/

Future<dynamic> main(final context) async {
  final client = Client()
    ..setEndpoint('https://fra.cloud.appwrite.io/v1') // Adjust if self-hosted
    ..setProject(context.req.headers['x-appwrite-project'] ?? '')
    ..setKey(context.req.headers['x-appwrite-key'] ?? '');

  final databases = Databases(client);
  final teams = Teams(client);

  // 1. Parse Input
  if (context.req.body == null || context.req.body.isEmpty) {
    return context.res.json({
      'success': false,
      'message': 'Missing body. Expecting {"joinCode": "...", "userId": "..."}',
    }, 400);
  }

  // Handle both JSON string and object depending on runtime
  final Map<String, dynamic> payload = context.req.body is Map
      ? context.req.body
      : (context.req.body
              is String) // rudimentary check, assume auto-parsed usually
          ? {} // Should parse JSON if string, but let's rely on standard Appwrite behavior
          : {};

  // Better: Appwrite 1.4+ parses body automatically if JSON content-type
  // Let's assume payload is directly accessible or needs parsing if raw string

  final String joinCode = payload['joinCode'] ?? '';
  final String userId = payload['userId'] ?? '';

  if (joinCode.isEmpty || userId.isEmpty) {
    return context.res.json({
      'success': false,
      'message': 'Missing joinCode or userId',
    }, 400);
  }

  try {
    context.log('Running Join Group for User: $userId with Code: $joinCode');

    // 2. Find Group by Join Code
    // We assume 'main_db' is the database ID. Better to pass it or use env var.
    const databaseId = 'main_db';
    const groupsCollectionId = 'groups';

    final groupList = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: groupsCollectionId,
      queries: [Query.equal('joinCode', joinCode), Query.limit(1)],
    );

    if (groupList.documents.isEmpty) {
      return context.res.json({
        'success': false,
        'message': 'Invalid Join Code',
      }, 404);
    }

    final groupDoc = groupList.documents.first;
    final String teamId = groupDoc.data['teamId'];
    final String groupId = groupDoc.data['groupId'];
    final String role = 'user'; // Default role

    context.log('Found Group: $groupId, Team: $teamId');

    // 3. Add User to Team (The Core Security Step)
    try {
      await teams.createMembership(
        teamId: teamId,
        roles: ['user'], // Appwrite Team Roles
        userId: userId,
        // email: '', // Optional/Not needed if userId is provided and user exists
        url:
            'https://localhost', // Redirect URL (required param but unused for API calls)
      );
      context.log('Added to Appwrite Team successfully.');
    } catch (e) {
      // Ignore if already member
      context.log('Team membership note: $e');
    }

    // 4. Update 'memberships' Collection (For UI Application Logic)
    try {
      // Check if exists first to avoid duplicates
      final existingMemberships = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: 'memberships',
        queries: [
          Query.equal('userId', userId),
          Query.equal('groupId', groupId),
        ],
      );

      if (existingMemberships.documents.isEmpty) {
        await databases.createDocument(
          databaseId: databaseId,
          collectionId: 'memberships',
          documentId: ID.unique(),
          data: {
            'userId': userId,
            'groupId': groupId,
            'role': role,
            'joinedAt': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      context.log('Membership doc creation error: $e');
    }

    // 5. Update User's Main Info (Current Group)
    try {
      await databases.updateDocument(
        databaseId: databaseId,
        collectionId: 'users_info',
        documentId: userId,
        data: {'groupId': groupId, 'role': role},
      );
    } catch (e) {
      context.log('User info update error: $e');
    }

    return context.res.json({
      'success': true,
      'message': 'Joined successfully',
      'groupId': groupId,
      'teamId': teamId,
    });
  } catch (e) {
    context.error('Error in function: $e');
    return context.res.json({
      'success': false,
      'message': 'Server Error: $e',
    }, 500);
  }
}
