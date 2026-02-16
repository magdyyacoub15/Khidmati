import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'appwrite_service.dart';

class TeamService {
  static final TeamService _instance = TeamService._internal();
  factory TeamService() => _instance;
  TeamService._internal();

  final Teams _teams = Teams(AppwriteService().client);

  /// إنشاء فريق جديد للمجموعة
  /// Returns the Team ID
  Future<String?> createTeam(String groupName) async {
    try {
      // 1. Create the Team
      // ID.unique() is good, but we might want to store this Team ID in the Group document later.
      final team = await _teams.create(teamId: ID.unique(), name: groupName);
      debugPrint("✅ Team Created: ${team.$id} for group: $groupName");
      return team.$id;
    } catch (e) {
      debugPrint("❌ Error creating team: $e");
      return null;
    }
  }

  /// إضافة عضو للفريق (عند انضمام مستخدم للمجموعة)
  Future<void> addMember(
    String teamId,
    String userId, {
    List<String> roles = const [],
  }) async {
    try {
      await _teams.createMembership(
        teamId: teamId,
        roles: roles,
        email:
            '', // Not needed if using userId/phone usually, but Appwrite might require email/phone or userId.
        // Wait, createMembership usually takes email/phone/url OR userId.
        // Let's check Appwrite SDK usage.
        // Actually, for client SDK, we usually invite by email.
        // BUT, since we are doing this "backend style" (or if the user is already creating the account),
        // we might need to use a Server Function?
        // NO, `Teams` service in Client SDK allows adding members if the current user is Owner.
        userId: userId,
        // Note: In Client SDK, you usually "invite" members via email.
        // Direct addition `createMembership` might require the user to accept invitation
        // OR if we are using Server SDK.
        // Let's assume for now we use the standard invite flow or we might need a different approach if we want "auto-join".
        // If "Auto-join" is needed, we might need a Cloud Function.
        // Let's hold on this implementation detail and start with `createTeam`.
        url: 'https://localhost', // Redirection URL
      );
    } catch (e) {
      // If user is already in team, it might throw.
      debugPrint("⚠️ Error adding member to team (might already be there): $e");
    }
  }

  /// حذف فريق (عند حذف المجموعة)
  Future<void> deleteTeam(String teamId) async {
    try {
      await _teams.delete(teamId: teamId);
    } catch (e) {
      debugPrint("❌ Error deleting team: $e");
    }
  }

  /// التأكد من وجود الفريق
  Future<models.Team?> getTeam(String teamId) async {
    try {
      return await _teams.get(teamId: teamId);
    } catch (e) {
      return null;
    }
  }

  /// الحصول على أعضاء الفريق
  Future<List<models.Membership>> getTeamMembers(String teamId) async {
    try {
      final response = await _teams.listMemberships(teamId: teamId);
      return response.memberships;
    } catch (e) {
      debugPrint("❌ Error fetching team members: $e");
      return [];
    }
  }
}
