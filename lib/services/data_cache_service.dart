import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart'; // 🚀 Added for Cache Integrity Hashing
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

  // --- Absence Report Cache ---
  static const String _keyAbsenceReport = 'cached_absence_report_';
  static const String _keyAbsenceActions = 'cached_absence_actions_';

  Future<void> cacheAbsenceReport(
    String groupId,
    String type,
    Map<String, dynamic> reportData,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString(
      '$_keyAbsenceReport${groupId}_$type',
      jsonEncode(reportData),
    );
  }

  // 🚀 Cache full report content (for large reports in storage)
  static const String _keyReportContent = 'cached_report_content_';

  Future<void> cacheReportContent(
    String reportId,
    Map<String, dynamic> content,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString('$_keyReportContent$reportId', jsonEncode(content));
  }

  Future<Map<String, dynamic>?> getCachedReportContent(String reportId) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyReportContent$reportId');
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCachedAbsenceReport(
    String groupId,
    String type,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString(
      '$_keyAbsenceReport${groupId}_$type',
    );
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<void> cacheAbsenceActions(
    String reportId,
    List<Map<String, dynamic>> actions,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString(
      '$_keyAbsenceActions$reportId',
      jsonEncode(actions),
    );
  }

  Future<List<Map<String, dynamic>>> getCachedAbsenceActions(
    String reportId,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString('$_keyAbsenceActions$reportId');
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  Future<void> updateSingleAbsenceActionInCache(
    String reportId,
    String kidName,
    Map<String, dynamic> updates,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> actions = await getCachedAbsenceActions(
      reportId,
    );
    final int index = actions.indexWhere((a) => a['kidName'] == kidName);

    if (index != -1) {
      actions[index] = {...actions[index], ...updates};
    } else {
      actions.add({'reportId': reportId, 'kidName': kidName, ...updates});
    }
    await cacheAbsenceActions(reportId, actions);
  }

  // --- Absence Page Simple State Cache ---
  static const String _keyAbsenceState = 'cached_absence_state_';

  Future<void> cacheAbsenceState(
    String groupId,
    String type,
    List<Map<String, dynamic>> state,
  ) async {
    await _initIfNeeded();
    await _prefs!.setString(
      '$_keyAbsenceState${groupId}_$type',
      jsonEncode(state),
    );
  }

  Future<List<Map<String, dynamic>>> getCachedAbsenceState(
    String groupId,
    String type,
  ) async {
    await _initIfNeeded();
    final String? jsonStr = _prefs!.getString(
      '$_keyAbsenceState${groupId}_$type',
    );
    if (jsonStr == null) return [];
    try {
      final List dynamicList = jsonDecode(jsonStr);
      return dynamicList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
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
  static const String _hashSecret =
      'supers3cr3t_manger3_hash!'; // 🚀 Secret Salt

  String _generateHash(String payload) {
    final bytes = utf8.encode(payload + _hashSecret);
    return md5.convert(bytes).toString();
  }

  Future<void> cacheSubscriptionStatus(
    String groupId,
    Map<String, dynamic> statusData,
  ) async {
    await _initIfNeeded();
    final String key = '$_keySubStatus$groupId';

    // 🚀 Security Fix: Calculate Hash for Tamper-Proofing
    final payloadString = jsonEncode(statusData);
    final hash = _generateHash(payloadString);

    final Map<String, dynamic> securePayload = {
      'data': statusData,
      'hash': hash,
    };

    await _prefs!.setString(key, jsonEncode(securePayload));
  }

  Future<Map<String, dynamic>?> getCachedSubscriptionStatus(
    String groupId,
  ) async {
    await _initIfNeeded();
    final String key = '$_keySubStatus$groupId';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return null;

    try {
      final decoded = jsonDecode(jsonStr);

      // 🚀 Migration/Fallback: If it's old unhashed data, return expired for safety or trust it once.
      // Let's trust it if 'hash' is missing to not break existing users immediately, but on next check it will secure it.
      if (!decoded.containsKey('hash') && decoded.containsKey('status')) {
        return decoded as Map<String, dynamic>;
      }

      final Map<String, dynamic> data = decoded['data'];
      final String hash = decoded['hash'];

      // 🚀 Security Fix: Verify Hash
      final expectedHash = _generateHash(jsonEncode(data));
      if (hash != expectedHash) {
        // Tampering Detected! Force Expired completely.
        return {
          'status': 'expired',
          'lastCheck': DateTime.now().toIso8601String(),
        };
      }

      return data;
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

  // 🚀 Remove Preparation from Cache
  Future<void> removePreparationFromCache(String groupId, String docId) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedPreparations(
      groupId,
    );
    currentList.removeWhere((p) => p[r'$id'] == docId);
    await cachePreparations(groupId, currentList);
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

  // 🚀 Remove Meeting from Cache
  Future<void> removeMeetingFromCache(String groupId, String docId) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedMeetings(
      groupId,
    );
    currentList.removeWhere((m) => m[r'$id'] == docId);
    await cacheMeetings(groupId, currentList);
  }

  // 🚀 Update Meeting in Cache (e.g. Title)
  Future<void> updateMeetingInCache(
    String groupId,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedMeetings(
      groupId,
    );
    final index = currentList.indexWhere((m) => m[r'$id'] == docId);
    if (index != -1) {
      currentList[index] = {...currentList[index], ...data};
      await cacheMeetings(groupId, currentList);
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

  // 🚀 Upsert Individual Visit in Cache
  Future<void> upsertIndividualVisitInCache(
    String groupId,
    String grade,
    Map<String, dynamic> visitData,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList =
        await getCachedIndividualVisits(groupId, grade);
    final String visitId = visitData[r'$id'] ?? visitData['visitId'] ?? '';
    final int index = currentList.indexWhere(
      (v) => (v[r'$id'] != null && v[r'$id'] == visitId),
    );

    if (index != -1) {
      currentList[index] = visitData;
    } else {
      currentList.insert(0, visitData);
    }
    await cacheIndividualVisits(groupId, grade, currentList);
  }

  // 🚀 Remove Individual Visit from Cache
  Future<void> removeIndividualVisitFromCache(
    String groupId,
    String grade,
    String visitId,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList =
        await getCachedIndividualVisits(groupId, grade);
    currentList.removeWhere(
      (v) => (v[r'$id'] == visitId || v['visitId'] == visitId),
    );
    await cacheIndividualVisits(groupId, grade, currentList);
  }

  // 🚀 Upsert Kid Visit in Cache
  Future<void> upsertKidVisitInCache(
    String groupId,
    String kidName,
    Map<String, dynamic> visitData,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedKidVisits(
      groupId,
      kidName,
    );
    final String visitId = visitData[r'$id'] ?? visitData['visitId'] ?? '';
    final int index = currentList.indexWhere(
      (v) => (v[r'$id'] != null && v[r'$id'] == visitId),
    );

    if (index != -1) {
      currentList[index] = visitData;
    } else {
      currentList.insert(0, visitData);
    }
    await cacheKidVisits(groupId, kidName, currentList);
  }

  // 🚀 Remove Kid Visit from Cache
  Future<void> removeKidVisitFromCache(
    String groupId,
    String kidName,
    String visitId,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedKidVisits(
      groupId,
      kidName,
    );
    currentList.removeWhere(
      (v) => (v[r'$id'] == visitId || v['visitId'] == visitId),
    );
    await cacheKidVisits(groupId, kidName, currentList);
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
  static String _getPendingOpsKey(String? groupId) =>
      groupId != null ? 'pending_operations_$groupId' : 'pending_operations';

  Future<void> addPendingOperation(
    Map<String, dynamic> operation, {
    String? groupId,
  }) async {
    await _initIfNeeded();

    // 🚀 Auto-extract groupId from data if not provided
    final String? effectiveGroupId =
        groupId ?? operation['data']?['groupId']?.toString();

    final List<Map<String, dynamic>> ops = await getPendingOperations(
      groupId: effectiveGroupId,
    );
    ops.add({
      ...operation,
      'offlineTimestamp': DateTime.now().toIso8601String(),
    });
    await _prefs!.setString(
      _getPendingOpsKey(effectiveGroupId),
      jsonEncode(ops),
    );
  }

  Future<bool> hasPendingOperations(String? groupId) async {
    final ops = await getPendingOperations(groupId: groupId);
    return ops.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getPendingOperations({
    String? groupId,
  }) async {
    await _initIfNeeded();
    final String key = _getPendingOpsKey(groupId);
    final String? jsonStr = _prefs!.getString(key);

    if (jsonStr == null) {
      // 🚀 Migration: If we requested a specific group but found nothing,
      // check if there are old global operations and MOVE them.
      if (groupId != null && groupId.isNotEmpty) {
        final String? globalJson = _prefs!.getString('pending_operations');
        if (globalJson != null) {
          try {
            final List<dynamic> allGlobalOps = jsonDecode(globalJson);
            final List<Map<String, dynamic>> matchingOps = [];
            final List<dynamic> remainingGlobalOps = [];

            for (var op in allGlobalOps) {
              final mapOp = Map<String, dynamic>.from(op as Map);
              if (mapOp['data']?['groupId'] == groupId) {
                matchingOps.add(mapOp);
              } else {
                remainingGlobalOps.add(op);
              }
            }

            if (matchingOps.isNotEmpty) {
              // 1. Save to group-specific key
              await _prefs!.setString(key, jsonEncode(matchingOps));
              // 2. Update global key with remaining items
              if (remainingGlobalOps.isEmpty) {
                await _prefs!.remove('pending_operations');
              } else {
                await _prefs!.setString(
                  'pending_operations',
                  jsonEncode(remainingGlobalOps),
                );
              }
              return matchingOps;
            }
          } catch (_) {}
        }
      }
      return [];
    }

    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  Future<void> clearPendingOperations({String? groupId}) async {
    await _initIfNeeded();
    await _prefs!.remove(_getPendingOpsKey(groupId));

    // Also clear from global if we are clearing a specific group and it exists there
    if (groupId != null) {
      final String? globalJson = _prefs!.getString('pending_operations');
      if (globalJson != null) {
        try {
          final List<dynamic> globalOps = jsonDecode(globalJson);
          final updatedGlobal = globalOps
              .where((op) => op['data']?['groupId'] != groupId)
              .toList();
          if (updatedGlobal.isEmpty) {
            await _prefs!.remove('pending_operations');
          } else {
            await _prefs!.setString(
              'pending_operations',
              jsonEncode(updatedGlobal),
            );
          }
        } catch (_) {}
      }
    }
  }

  Future<void> removePendingOperation(int index, {String? groupId}) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> ops = await getPendingOperations(
      groupId: groupId,
    );
    if (index >= 0 && index < ops.length) {
      final removedOp = ops.removeAt(index);
      await _prefs!.setString(_getPendingOpsKey(groupId), jsonEncode(ops));

      // 🚀 Sync with global if this op was part of it
      if (groupId != null) {
        final String? globalJson = _prefs!.getString('pending_operations');
        if (globalJson != null) {
          try {
            final List<dynamic> globalOps = jsonDecode(globalJson);
            // This is tricky because indices might differ.
            // We search for matching timestamp/type/data.
            globalOps.removeWhere(
              (op) =>
                  op['offlineTimestamp'] == removedOp['offlineTimestamp'] &&
                  op['type'] == removedOp['type'],
            );
            if (globalOps.isEmpty) {
              await _prefs!.remove('pending_operations');
            } else {
              await _prefs!.setString(
                'pending_operations',
                jsonEncode(globalOps),
              );
            }
          } catch (_) {}
        }
      }
    }
  }

  // --- Study Tracking Cache ---
  static const String _keyStudySubjects = 'cached_study_subjects_';
  static const String _keyStudyGrades = 'cached_study_grades_';

  // --- Custom Pages Cache ---
  static const String _keyCustomPages = 'cached_custom_pages_';

  // 🚀 Cache Custom Pages List
  Future<void> cacheCustomPages(
    String groupId,
    List<Map<String, dynamic>> pages,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyCustomPages$groupId';
    await _prefs!.setString(key, jsonEncode(pages));
  }

  // 🚀 Get Cached Custom Pages
  Future<List<Map<String, dynamic>>> getCachedCustomPages(
    String groupId,
  ) async {
    await _initIfNeeded();
    final String key = '$_keyCustomPages$groupId';
    final String? jsonStr = _prefs!.getString(key);
    if (jsonStr == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  // 🚀 Upsert Custom Page in Cache
  Future<void> upsertCustomPageInCache(
    String groupId,
    Map<String, dynamic> pageData,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedCustomPages(
      groupId,
    );
    final String docId = pageData[r'$id'] ?? pageData['id'] ?? '';
    final int index = currentList.indexWhere(
      (p) =>
          (p[r'$id'] != null && p[r'$id'] == docId) ||
          p['name'] == pageData['name'],
    );

    if (index != -1) {
      currentList[index] = pageData;
    } else {
      currentList.add(pageData);
    }
    await cacheCustomPages(groupId, currentList);
  }

  // 🚀 Remove Custom Page from Cache
  Future<void> removeCustomPageFromCache(String groupId, String docId) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedCustomPages(
      groupId,
    );
    currentList.removeWhere((p) => p[r'$id'] == docId || p['id'] == docId);
    await cacheCustomPages(groupId, currentList);
  }

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

  // 🚀 Upsert Study Subject in Cache
  Future<void> upsertStudySubjectInCache(
    String studentId,
    Map<String, dynamic> subjectData,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedStudySubjects(
      studentId,
    );
    final int index = currentList.indexWhere(
      (s) =>
          s[r'$id'] == subjectData[r'$id'] || s['name'] == subjectData['name'],
    );

    if (index != -1) {
      currentList[index] = subjectData;
    } else {
      currentList.add(subjectData);
    }
    await cacheStudySubjects(studentId, currentList);
  }

  // 🚀 Remove Study Subject from Cache
  Future<void> removeStudySubjectFromCache(
    String studentId,
    String subjectId,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedStudySubjects(
      studentId,
    );
    currentList.removeWhere((s) => s[r'$id'] == subjectId);
    await cacheStudySubjects(studentId, currentList);
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

  // 🚀 Upsert Study Grade in Cache
  Future<void> upsertStudyGradeInCache(
    String studentId,
    String subject,
    Map<String, dynamic> gradeData,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedStudyGrades(
      studentId,
      subject,
    );
    final int index = currentList.indexWhere(
      (g) => g[r'$id'] == gradeData[r'$id'],
    );

    if (index != -1) {
      currentList[index] = gradeData;
    } else {
      currentList.add(gradeData);
    }
    await cacheStudyGrades(studentId, subject, currentList);
  }

  // 🚀 Remove Study Grade from Cache
  Future<void> removeStudyGradeFromCache(
    String studentId,
    String subject,
    String gradeId,
  ) async {
    await _initIfNeeded();
    final List<Map<String, dynamic>> currentList = await getCachedStudyGrades(
      studentId,
      subject,
    );
    currentList.removeWhere((g) => g[r'$id'] == gradeId);
    await cacheStudyGrades(studentId, subject, currentList);
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
