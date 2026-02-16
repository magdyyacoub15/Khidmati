import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/kid.dart';

class DataCacheService {
  static final DataCacheService _instance = DataCacheService._internal();
  factory DataCacheService() => _instance;
  DataCacheService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- User Data Caching ---
  static const String _keyUserData = 'cached_user_data';

  Future<void> cacheUserData(Map<String, dynamic> data) async {
    await _initIfNeeded();
    await _prefs!.setString(_keyUserData, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> getCachedUserData() async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString(_keyUserData);
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  // --- Kids List Caching ---
  static const String _keyKidsList = 'cached_kids_list_';

  Future<void> cacheKidsList(
    String groupId,
    String type,
    List<Kid> kids,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> jsonList = kids
        .map((k) => k.toMap())
        .toList();

    final String key = '$_keyKidsList${groupId}_$type';
    await _prefs!.setString(key, jsonEncode(jsonList));
  }

  Future<List<Kid>> getCachedKidsList(String groupId, String type) async {
    await _initIfNeeded();
    final String key = '$_keyKidsList${groupId}_$type';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((json) => Kid.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  // 🚀 Update Single Kid in Cache (for efficient sync)
  Future<void> updateKidInListCache(
    String groupId,
    String type,
    String kidId,
    Map<String, dynamic> updates,
  ) async {
    await _initIfNeeded();
    final List<Kid> currentList = await getCachedKidsList(groupId, type);
    final int index = currentList.indexWhere((k) => k.id == kidId);
    if (index != -1) {
      // Create new kid with updates
      final Kid oldKid = currentList[index];
      final updatedKid = oldKid.copyWithStatus(
        isVisited: updates['isVisited'],
        visitedBy: updates['visitedBy'],
        photoUrl: updates['photoUrl'],
        name: updates['name'],
        address: updates['address'],
        phoneRequired: updates['phoneRequired'],
        phoneOptional: updates['phoneOptional'],
        phoneRequiredOwner: updates['phoneRequiredOwner'],
        phoneOptionalOwner: updates['phoneOptionalOwner'],
        dateOfBirth: updates['dateOfBirth'] != null
            ? (updates['dateOfBirth'] is DateTime
                  ? updates['dateOfBirth']
                  : DateTime.tryParse(updates['dateOfBirth'].toString()))
            : null,
        locationUrl: updates['locationUrl'],
        localImagePath: updates['localImagePath'],
      );
      currentList[index] = updatedKid;
    }
    await cacheKidsList(groupId, type, currentList);
  }

  // 🚀 Upsert Kid in Cache (Add or Update)
  Future<void> upsertKidInListCache(
    String groupId,
    String type,
    Kid kid,
  ) async {
    await _initIfNeeded();
    final List<Kid> currentList = await getCachedKidsList(groupId, type);
    final int index = currentList.indexWhere((k) => k.id == kid.id);

    if (index != -1) {
      currentList[index] = kid;
    } else {
      currentList.add(kid);
    }
    await cacheKidsList(groupId, type, currentList);
  }

  // 🚀 Remove Kid from Cache
  Future<void> removeKidFromListCache(
    String groupId,
    String type,
    String kidId,
  ) async {
    await _initIfNeeded();
    final List<Kid> currentList = await getCachedKidsList(groupId, type);
    currentList.removeWhere((k) => k.id == kidId);
    await cacheKidsList(groupId, type, currentList);
  }

  // --- Grades Caching ---
  static const String _keyGradesList = 'cached_grades_list_';

  Future<void> cacheGrades(String groupId, List<String> grades) async {
    await _initIfNeeded();
    final String key = '$_keyGradesList$groupId';
    await _prefs!.setString(key, jsonEncode(grades));
  }

  Future<List<String>> getCachedGrades(String groupId) async {
    await _initIfNeeded();
    final String key = '$_keyGradesList$groupId';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];

    try {
      return List<String>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Contact Info Cache (Absence Page) ---
  static const String _keyContactMap = 'cached_contact_map_';

  Future<void> cacheContactMap(
    String groupId,
    String type,
    Map<String, dynamic> data,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyContactMap${groupId}_$type';
    await _prefs!.setString(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>> getCachedContactMap(
    String groupId,
    String type,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyContactMap${groupId}_$type';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return {};

    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  // --- Birthday List Cache ---
  static const String _keyBirthdayList = 'cached_birthday_list_';

  Future<void> cacheBirthdayList(
    String groupId,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyBirthdayList$groupId';
    await _prefs!.setString(key, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> getCachedBirthdayList(
    String groupId,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyBirthdayList$groupId';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];

    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Subscription Prices Cache ---
  static const String _keySubPrices = 'cached_sub_prices';

  Future<void> cacheSubscriptionPrices(Map<String, dynamic> prices) async {
    await _initIfNeeded();
    await _prefs!.setString(_keySubPrices, jsonEncode(prices));
  }

  Future<Map<String, dynamic>?> getCachedSubscriptionPrices() async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString(_keySubPrices);
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  // --- Subscription Status Cache ---
  static const String _keySubStatus = 'cached_sub_status_';

  Future<void> cacheSubscriptionStatus(
    String groupId,
    Map<String, dynamic> statusData,
  ) async {
    await _initIfNeeded();
    final String key = '$_keySubStatus$groupId';
    await _prefs!.setString(key, jsonEncode(statusData));
  }

  Future<Map<String, dynamic>?> getCachedSubscriptionStatus(
    String groupId,
  ) async {
    await _initIfNeeded();
    final String key = '$_keySubStatus$groupId';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  // --- User Group ID Cache ---
  static const String _keyUserGroupId = 'cached_user_group_id_';

  Future<void> cacheUserGroupId(
    String userId,
    String groupId,
    String? teamId,
    String role,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString(
      '$_keyUserGroupId$userId',
      jsonEncode({'groupId': groupId, 'teamId': teamId, 'role': role}),
    );
  }

  Future<Map<String, String>?> getCachedUserGroupId(String userId) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyUserGroupId$userId');
    if (jsonStr == null) return null;
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return {
        'groupId': data['groupId'] as String,
        'teamId': (data['teamId'] as String?) ?? '',
        'role': data['role'] as String,
      };
    } catch (e) {
      return null;
    }
  }

  // --- Preparations List Cache ---
  static const String _keyPrepList = 'cached_prep_list_';

  Future<void> cachePreparations(
    String groupId,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString('$_keyPrepList$groupId', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> getCachedPreparations(
    String groupId,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyPrepList$groupId');
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Meetings List Cache ---
  static const String _keyMeetingsList = 'cached_meetings_list_';

  Future<void> cacheMeetings(
    String groupId,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString('$_keyMeetingsList$groupId', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> getCachedMeetings(String groupId) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyMeetingsList$groupId');
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Attendance Reports Cache ---
  static const String _keyAttendanceReports = 'cached_attendance_reports_';

  Future<void> cacheAttendanceReports(
    String groupId,
    String type,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString(
      '$_keyAttendanceReports${groupId}_$type',
      jsonEncode(data),
    );
  }

  // --- Attendance Status Map Cache (Offline Mode) ---
  static const String _keyAttendanceStatusMap = 'cached_status_map_';

  Future<void> cacheAttendanceStatusMap(
    String groupId,
    String grade,
    String type,
    Map<String, dynamic> data, // Map<KidName, DocumentData>
  ) async {
    await _initIfNeeded();
    final String key = '$_keyAttendanceStatusMap${groupId}_${grade}_$type';
    await _prefs!.setString(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>> getCachedAttendanceStatusMap(
    String groupId,
    String grade,
    String type,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyAttendanceStatusMap${groupId}_${grade}_$type';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return {};

    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getCachedAttendanceReports(
    String groupId,
    String type,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString(
      '$_keyAttendanceReports${groupId}_$type',
    );
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // 🚀 Update Single Status Item (for efficient sync)
  Future<void> updateAttendanceStatusItem(
    String groupId,
    String grade,
    String type,
    String kidName,
    Map<String, dynamic> docData,
  ) async {
    await _initIfNeeded();
    final currentMap = await getCachedAttendanceStatusMap(groupId, grade, type);
    currentMap[kidName] = docData;
    await cacheAttendanceStatusMap(groupId, grade, type, currentMap);
  }

  // 🚀 Remove Single Status Item
  Future<void> removeAttendanceStatusItem(
    String groupId,
    String grade,
    String type,
    String kidName,
  ) async {
    await _initIfNeeded();
    final currentMap = await getCachedAttendanceStatusMap(groupId, grade, type);
    if (currentMap.containsKey(kidName)) {
      currentMap.remove(kidName);
      await cacheAttendanceStatusMap(groupId, grade, type, currentMap);
    }
  }

  // --- Individual Visits Cache ---
  static const String _keyIndividualVisits = 'cached_individual_visits_';

  Future<void> cacheIndividualVisits(
    String groupId,
    String grade,
    List<Map<String, dynamic>> visits,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyIndividualVisits${groupId}_$grade';
    await _prefs!.setString(key, jsonEncode(visits));
  }

  Future<List<Map<String, dynamic>>> getCachedIndividualVisits(
    String groupId,
    String grade,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyIndividualVisits${groupId}_$grade';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];

    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Kid Specific Visits Cache ---
  static const String _keyKidVisits = 'cached_kid_visits_';

  Future<void> cacheKidVisits(
    String groupId,
    String kidName,
    List<Map<String, dynamic>> visits,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyKidVisits${groupId}_$kidName';
    await _prefs!.setString(key, jsonEncode(visits));
  }

  Future<List<Map<String, dynamic>>> getCachedKidVisits(
    String groupId,
    String kidName,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyKidVisits${groupId}_$kidName';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];

    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Visited Reports Cache ---
  static const String _keyVisitedReports = 'cached_visited_reports_';

  Future<void> cacheVisitedReports(
    String groupId,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString('$_keyVisitedReports$groupId', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> getCachedVisitedReports(
    String groupId,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyVisitedReports$groupId');
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Visited Report Details Cache ---
  static const String _keyVisitedDetails = 'cached_visited_details_';

  Future<void> cacheVisitedDetails(
    String reportId,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString('$_keyVisitedDetails$reportId', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>?> getCachedVisitedDetails(
    String reportId,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyVisitedDetails$reportId');
    if (jsonStr == null) return null;
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return null;
    }
  }

  // --- Pending Operations for Offline Mode ---
  static const String _keyPendingOps = 'pending_operations';

  Future<void> addPendingOperation(Map<String, dynamic> operation) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> ops = await getPendingOperations();
    ops.add({
      ...operation,
      'offlineTimestamp': DateTime.now().toIso8601String(),
    });
    await _prefs!.setString(_keyPendingOps, jsonEncode(ops));
  }

  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString(_keyPendingOps);
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  Future<void> clearPendingOperations() async {
    await _initIfNeeded();
    await _prefs!.remove(_keyPendingOps);
  }

  Future<void> removePendingOperation(int index) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> ops = await getPendingOperations();
    if (index >= 0 && index < ops.length) {
      ops.removeAt(index);
      await _prefs!.setString(_keyPendingOps, jsonEncode(ops));
    }
  }

  // --- Study Tracking Cache ---
  static const String _keyStudySubjects = 'cached_study_subjects_';
  static const String _keyStudyGrades = 'cached_study_grades_';

  Future<void> cacheStudySubjects(
    String studentId,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString('$_keyStudySubjects$studentId', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> getCachedStudySubjects(
    String studentId,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyStudySubjects$studentId');
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  Future<void> cacheStudyGrades(
    String studentId,
    String subject,
    List<Map<String, dynamic>> data,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyStudyGrades${studentId}_$subject';
    await _prefs!.setString(key, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> getCachedStudyGrades(
    String studentId,
    String subject,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyStudyGrades${studentId}_$subject';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // --- Helpers ---
  Future<void> _initIfNeeded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> clearCache() async {
    await _initIfNeeded();
    await _prefs!.clear();
  }
}
