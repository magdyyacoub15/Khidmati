import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🚀 Added for kIsWeb
import 'package:intl/intl.dart';
import 'package:appwrite/appwrite.dart' hide Locale;
import 'package:appwrite/models.dart' as models;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import '../services/grade_service.dart';
import '../services/appwrite_service.dart';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
// 🚀 الإضافات لضغط الصور والتخزين المؤقت
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../services/status_service.dart';
import '../services/user_service.dart';
import '../services/image_service.dart';
import '../services/permission_service.dart';
import '../services/data_cache_service.dart';
import '../services/sync_service.dart';

// ✨ إضافات عرض الصور والتكبير
import 'package:cached_network_image/cached_network_image.dart';
import '../models/kid.dart';
import '../services/image_cache_service.dart';
import '../widgets/full_screen_image.dart';
import '../widgets/full_screen_image_gallery.dart'; // 🚀 Added Gallery
import '../l10n/app_translations.dart';

// Unified Kid model

// ----------------------------------------------------
// 🔹 الصفحة الرئيسية: عرض قائمة الفصول
// ----------------------------------------------------

class IndividualVisitedPage extends StatefulWidget {
  final String? kidName;
  final String? grade;
  final String? photoUrl;

  const IndividualVisitedPage({
    super.key,
    this.kidName,
    this.grade,
    this.photoUrl,
  });

  @override
  State<IndividualVisitedPage> createState() => _IndividualVisitedPageState();
}

class _IndividualVisitedPageState extends State<IndividualVisitedPage> {
  List<Kid> _allKids = [];
  List<Kid> _filteredKids = [];
  Map<String, List<Kid>> _kidsByGrade = {};
  bool _isLoading = true;

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  late Realtime _realtime;
  RealtimeSubscription? _kidsSubscription;
  RealtimeSubscription? _userSubscription;

  List<String> _gradeOrder = [];
  String _myGroupId = '';
  String _currentServantName = "unknown_servant";
  final TextEditingController _searchController = TextEditingController();

  static const String databaseId = AppwriteService.databaseId;
  static const String usersCollectionId = 'users_info';
  static const String studentsCollectionId = 'students';

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
    // ⚡ FIX: Removed context-dependent loading to avoid InheritedWidget error
    _loadUserData();
    _loadServantInfo();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadUserData() async {
    // 🚀 1. Try to load from cache FIRST (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        if (mounted) {
          setState(() {
            _myGroupId = cachedCtx['groupId'] ?? '';
          });
          if (_myGroupId.isNotEmpty) {
            _loadCachedKids();
            _fetchKidsFromAppwrite(); // This handles its own errors silently
            _fetchGradeOrder();
            _handleAutoNavigation();
          }
        }
      }
    }

    // 🚀 2. Background Refresh & Realtime Setup
    try {
      final user = await _account.get();
      await UserService().getCurrentUser(); // Sync user to cache

      try {
        final userDoc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: usersCollectionId,
          documentId: user.$id,
        );

        // Update local cache
        await DataCacheService().cacheUserGroupId(
          user.$id,
          userDoc.data['groupId'],
          userDoc.data['teamId'],
          userDoc.data['role'],
        );

        if (mounted) {
          final newGroupId = userDoc.data['groupId'] ?? '';
          if (newGroupId != _myGroupId && newGroupId.isNotEmpty) {
            setState(() {
              _myGroupId = newGroupId;
            });
            _loadCachedKids();
            _fetchKidsFromAppwrite();
            _fetchGradeOrder();
            _handleAutoNavigation();
          }
        }
      } catch (e) {
        debugPrint("Background live user doc fetch failed: $e");
      }

      _userSubscription?.close();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$usersCollectionId.documents.${user.$id}',
      ]);
      _userSubscription!.stream.listen((event) async {
        if (mounted) {
          final data = event.payload;
          final newGroupId = data['groupId'] ?? '';
          if (newGroupId != _myGroupId) {
            setState(() {
              _myGroupId = newGroupId;
            });
            if (_myGroupId.isNotEmpty) {
              _fetchKidsFromAppwrite();
              _fetchGradeOrder();
            }
          }
        }
      });
    } catch (e) {
      debugPrint("Offline mode active or error in _loadUserData: $e");
    }
  }

  void _handleAutoNavigation() {
    if (widget.kidName != null && widget.grade != null) {
      // Small delay to ensure state is initialized and data is loading
      Future.delayed(Duration.zero, () {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => KidVisitTracker(
              kid: Kid(
                id: '', // Minimal kid
                name: widget.kidName!,
                address: '',
                grade: widget.grade!,
                photoUrl: widget.photoUrl,
              ),
              servantName: _currentServantName,
              groupId: _myGroupId,
            ),
          ),
        );
      });
    }
  }

  Future<void> _fetchGradeOrder() async {
    try {
      // 🚀 GradeService already handles caching internally
      final grades = await GradeService(groupId: _myGroupId).getGrades();
      if (mounted) {
        setState(() {
          _gradeOrder = grades;
        });
      }
    } catch (e) {
      debugPrint("Error fetching grades order: $e");
    }
  }

  Future<void> _loadCachedKids() async {
    try {
      final cachedKids = await DataCacheService().getCachedKidsList(
        _myGroupId,
        'all',
      );
      if (cachedKids.isNotEmpty && mounted) {
        setState(() {
          if (_allKids.isEmpty) {
            _allKids = cachedKids;
            _onSearchChanged();
            _isLoading = false;
          }
        });
      }
    } catch (_) {}
  }

  void _updateKidLocally(Kid updatedKid) {
    if (!mounted) return;
    setState(() {
      final index = _allKids.indexWhere((k) => k.id == updatedKid.id);
      if (index != -1) {
        _allKids[index] = updatedKid;
      } else {
        _allKids.add(updatedKid);
      }
      _onSearchChanged();
    });
  }

  @override
  void dispose() {
    _kidsSubscription?.close();
    _userSubscription?.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchKidsFromAppwrite() async {
    try {
      // 1. Initial Fetch
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.limit(1000), // Adjust as needed
        ],
      );

      final kids = result.documents
          .map((doc) => Kid.fromAppwrite(doc))
          .toList();

      // 🚀 Save to cache
      await DataCacheService().cacheKidsList(_myGroupId, 'all', kids);

      if (mounted) {
        setState(() {
          _allKids = kids;
          _onSearchChanged();
          _isLoading = false;
        });
      }

      // 2. Optimized Realtime Listener
      _kidsSubscription?.close();
      _kidsSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$studentsCollectionId.documents',
      ]);

      _kidsSubscription!.stream.listen((event) {
        if (!mounted) return;
        final payload = event.payload;
        if (payload['groupId'] == _myGroupId) {
          // 🚀 DATA OPTIMIZATION: If update, modify only the item locally
          if (event.events.any((e) => e.contains('.update'))) {
            final updatedKid = Kid.fromAppwrite(
              models.Document.fromMap(payload),
            );
            _updateKidLocally(updatedKid);
            // Sync cache too
            DataCacheService().upsertKidInListCache(
              _myGroupId,
              'all',
              updatedKid,
            );
          } else {
            // Re-fetch for create/delete/other
            _reFetchKids();
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Error Snackbar only if we don't have any cached data
        if (_allKids.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${'error_fetching_data'.tr(context)}: $e')),
          );
        }
      }
    }
  }

  Future<void> _reFetchKids() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [Query.equal('groupId', _myGroupId), Query.limit(1000)],
      );
      final kids = result.documents
          .map((doc) => Kid.fromAppwrite(doc))
          .toList();
      if (mounted) {
        setState(() {
          _allKids = kids;
          _onSearchChanged();
        });
      }
    } catch (_) {}
  }

  Map<String, List<Kid>> _groupKidsByGrade(List<Kid> kids) {
    final Map<String, List<Kid>> grouped = {};
    for (var kid in kids) {
      final String grade = kid.grade ?? 'unspecified_grade'.tr(context);
      if (!grouped.containsKey(grade)) {
        grouped[grade] = [];
      }
      grouped[grade]!.add(kid);
    }

    final List<String> gradeKeys = grouped.keys.toList();
    gradeKeys.sort((a, b) {
      final indexA = _gradeOrder.indexOf(a);
      final indexB = _gradeOrder.indexOf(b);

      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(indexB);
      } else if (indexA != -1) {
        return -1;
      } else if (indexB != -1) {
        return 1;
      }
      return a.compareTo(b);
    });

    return {for (var key in gradeKeys) key: grouped[key]!};
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    final filtered = query.isEmpty
        ? _allKids
        : _allKids.where((kid) => kid.matchesQuery(query)).toList();

    setState(() {
      _filteredKids = filtered;
      _kidsByGrade = _groupKidsByGrade(filtered);
    });
  }

  void _loadServantInfo() async {
    final name = await UserService().getCurrentUserName();
    if (mounted) {
      setState(() {
        _currentServantName = name;
      });
    }
  }

  Widget _buildGradeSection(String grade, List<Kid> kids) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: MediaQuery.of(context).size.height * 0.01,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.blue.shade100, width: 1),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width * 0.05,
          vertical: MediaQuery.of(context).size.height * 0.02,
        ),
        leading: Container(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.03),
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            shape: BoxShape.circle,
          ),
          child: Text(
            kids.length.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: MediaQuery.of(context).size.width * 0.04,
            ),
          ),
        ),
        title: Text(
          grade,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: MediaQuery.of(context).size.width * 0.045,
            color: Colors.blue.shade900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'servants_count_kids'
              .tr(context)
              .replaceFirst('%s', kids.length.toString()),
          style: TextStyle(
            fontSize: MediaQuery.of(context).size.width * 0.033,
            color: Colors.grey.shade600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: MediaQuery.of(context).size.width * 0.04,
          color: const Color(0xFF0D47A1),
        ),
        onLongPress: null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GradeKidsPage(
                gradeTitle: grade,
                kids: kids,
                servantName: _currentServantName,
                groupId: _myGroupId,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String title, String value) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: MediaQuery.of(context).size.width * 0.05,
            color: Colors.blue.shade700,
          ),
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.005),
        Text(
          title,
          style: TextStyle(
            fontSize: MediaQuery.of(context).size.width * 0.028,
            color: Colors.grey.shade700,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: MediaQuery.of(context).size.width * 0.038,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('individual_visitation'.tr(context)),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
              color: Colors.white,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.06,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'search_kids_hint'.tr(context),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF0288D1),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xFF0288D1),
                        width: 1.5,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width * 0.04,
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    Icons.people,
                    'total_servants_kids'.tr(context),
                    _allKids.length.toString(),
                  ),
                  _buildStatItem(
                    Icons.class_,
                    'number_of_grades'.tr(context),
                    _kidsByGrade.length.toString(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_filteredKids.isEmpty && _searchController.text.isNotEmpty)
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: MediaQuery.of(context).size.width * 0.15,
                            color: Colors.grey.shade400,
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.02,
                          ),
                          Text(
                            'no_search_results'.tr(context),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.04,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _reFetchKids,
                      child: ListView(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).size.height * 0.01,
                          bottom: MediaQuery.of(context).size.height * 0.02,
                        ),
                        children: _kidsByGrade.entries.map((entry) {
                          if (entry.value.isEmpty) return const SizedBox.shrink();
                          return _buildGradeSection(entry.key, entry.value);
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------
// 🔹 صفحة عرض أطفال فصل معين - مع إضافة نظام الصور
// ----------------------------------------------------

class GradeKidsPage extends StatefulWidget {
  final String gradeTitle;
  final List<Kid> kids;
  final String servantName;
  final String groupId;

  const GradeKidsPage({
    required this.gradeTitle,
    required this.kids,
    required this.servantName,
    required this.groupId,
    super.key,
  });

  @override
  State<GradeKidsPage> createState() => _GradeKidsPageState();
}

class _GradeKidsPageState extends State<GradeKidsPage> {
  final Databases _databases = AppwriteService().databases;
  Map<String, int> _kidVisitCounts = {};
  Map<String, bool> _kidVisitedThisMonth = {};
  Map<String, double> _historicalPercentages = {};
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<Kid> _filteredKids = [];

  static const String visitsCollectionId = 'individual_visits';

  late Realtime _realtime;
  RealtimeSubscription? _kidsSubscription;
  static const String databaseId = 'main_db';
  static const String studentsCollectionId = 'students';

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
    _filteredKids = widget.kids;
    // 🚀 Load from cache FIRST
    _loadCachedVisitCounts();
    _fetchVisitCounts();
    _subscribeToGradeUpdates();
    _searchController.addListener(() {
      _filterKids(_searchController.text);
    });
  }

  @override
  void dispose() {
    _kidsSubscription?.close();
    _visitsSubscription?.close(); // 🔥
    _searchController.dispose();
    super.dispose();
  }

  RealtimeSubscription? _visitsSubscription; // 🔥

  void _subscribeToGradeUpdates() {
    // 1. Subscribe to Students
    try {
      _kidsSubscription?.close();
      _kidsSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$studentsCollectionId.documents',
      ]);

      debugPrint("DEBUG: GradeKidsPage Subscribed to students");

      _kidsSubscription!.stream.listen((event) {
        debugPrint(
          "DEBUG: GradeKidsPage Students Realtime event: ${event.events}",
        );
        if (mounted) {
          final payload = event.payload;
          if (payload['groupId'] == widget.groupId &&
              payload['grade'] == widget.gradeTitle) {
            _refreshPageData();
          }
        }
      });
    } catch (e) {
      debugPrint("DEBUG: GradeKidsPage Students Realtime error: $e");
    }

    // 2. Subscribe to Visits (to update counters) 🔥
    try {
      _visitsSubscription?.close();
      _visitsSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$visitsCollectionId.documents',
      ]);

      debugPrint("DEBUG: GradeKidsPage Subscribed to visits");

      _visitsSubscription!.stream.listen((event) {
        debugPrint(
          "DEBUG: GradeKidsPage Visits Realtime event: ${event.events}",
        );
        if (mounted) {
          final payload = event.payload;
          if (payload['groupId'] == widget.groupId &&
              payload['kidGrade'] == widget.gradeTitle) {
            _fetchVisitCounts();
          }
        }
      });
    } catch (e) {
      debugPrint("DEBUG: GradeKidsPage Visits Realtime error: $e");
    }
  }

  Future<void> _refreshPageData() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('grade', widget.gradeTitle),
          Query.limit(1000),
        ],
      );

      final List<Kid> newKids = result.documents
          .map((doc) => Kid.fromAppwrite(doc))
          .toList();

      if (mounted) {
        setState(() {
          _filteredKids = newKids;
        });
        _fetchVisitCounts();
      }
    } catch (e) {
      debugPrint("DEBUG: GradeKidsPage Refresh error: $e");
    }
  }

  Future<void> _loadCachedVisitCounts() async {
    try {
      final cachedVisits = await DataCacheService().getCachedIndividualVisits(
        widget.groupId,
        widget.gradeTitle,
      );
      if (cachedVisits.isNotEmpty) {
        final Map<String, int> counts = {};
        final Map<String, bool> visitedThisMonth = {};
        final now = DateTime.now();
        final startOfCurrentMonth = DateTime(now.year, now.month, 1);

        // Assuming cachedVisits is a list of visit documents
        for (var kid in widget.kids) {
          final kidVisits = cachedVisits
              .where((doc) => doc['kidName'] == kid.name)
              .toList();
          counts[kid.name] = kidVisits.length;

          bool hasVisitThisMonth = kidVisits.any((doc) {
            final timestampStr = doc['timestamp'];
            if (timestampStr == null) return false;
            return DateTime.parse(timestampStr).isAfter(startOfCurrentMonth);
          });
          visitedThisMonth[kid.name] = hasVisitThisMonth;
        }

        if (mounted) {
          setState(() {
            _kidVisitCounts = counts;
            _kidVisitedThisMonth = visitedThisMonth;
            if (_isLoading) _isLoading = false;
          });
        }
      }
    } catch (_) {}
  }

  void _filterKids(String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      setState(() {
        _filteredKids = widget.kids;
      });
    } else {
      final filtered = widget.kids
          .where((kid) => kid.matchesQuery(query))
          .toList();
      setState(() {
        _filteredKids = filtered;
      });
    }
  }

  Future<void> _fetchVisitCounts() async {
    final Map<String, int> counts = {};
    final Map<String, bool> visitedThisMonth = {};
    final now = DateTime.now();
    final startOfCurrentMonth = DateTime(now.year, now.month, 1);

    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: visitsCollectionId,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('kidGrade', widget.gradeTitle),
          Query.limit(1000),
        ],
      );

      final visits = result.documents;

      for (var kid in widget.kids) {
        final kidVisits = visits
            .where((doc) => doc.data['kidName'] == kid.name)
            .toList();
        counts[kid.name] = kidVisits.length;

        bool hasVisitThisMonth = kidVisits.any((doc) {
          final timestampStr = doc.data['timestamp'];
          if (timestampStr == null) return false;
          return DateTime.parse(timestampStr).isAfter(startOfCurrentMonth);
        });
        visitedThisMonth[kid.name] = hasVisitThisMonth;
      }

      // 🚀 Save to cache
      await DataCacheService().cacheIndividualVisits(
        widget.groupId,
        widget.gradeTitle,
        visits.map((e) => e.data).toList(),
      );

      _calculateHistoricalData(visits);
    } catch (e) {
      debugPrint("Error fetching visit counts from Appwrite: $e");
      // 🚀 Robustness: Don't override if we already have cached data
      if (counts.isEmpty) {
        for (var kid in widget.kids) {
          counts[kid.name] = _kidVisitCounts[kid.name] ?? 0;
          visitedThisMonth[kid.name] = _kidVisitedThisMonth[kid.name] ?? false;
        }
      } else {
        return; // Already have data, don't update state with potentially empty/broken maps
      }
    }

    if (mounted) {
      setState(() {
        _kidVisitCounts = counts;
        _kidVisitedThisMonth = visitedThisMonth;
        _isLoading = false;
      });
    }
  }

  void _calculateHistoricalData(List<models.Document> visits) {
    try {
      final Map<String, Set<String>> monthToKids = {};

      for (var doc in visits) {
        final timestampStr = doc.data['timestamp'];
        final kidName = doc.data['kidName'] as String?;
        if (timestampStr == null || kidName == null) continue;

        final date = DateTime.parse(timestampStr);
        final monthKey =
            "${date.year}-${date.month.toString().padLeft(2, '0')}";

        monthToKids.putIfAbsent(monthKey, () => <String>{}).add(kidName);
      }

      final Map<String, double> historical = {};
      final currentKidsNames = widget.kids.map((k) => k.name).toSet();

      monthToKids.forEach((month, visitedSet) {
        final visitedCurrentKids = visitedSet
            .intersection(currentKidsNames)
            .length;
        historical[month] = widget.kids.isEmpty
            ? 0
            : visitedCurrentKids / widget.kids.length;
      });

      if (mounted) {
        setState(() {
          _historicalPercentages = historical;
        });
      }
    } catch (e) {
      debugPrint("Error calculating historical data: $e");
    }
  }

  double _calculateVisitPercentage() {
    if (widget.kids.isEmpty) return 0.0;
    final visitedKidsCount = _kidVisitedThisMonth.values.where((v) => v).length;
    return visitedKidsCount / widget.kids.length;
  }

  void _showVisitHistoryDialog() {
    final now = DateTime.now();
    final currentMonthKey =
        "${now.year}-${now.month.toString().padLeft(2, '0')}";

    final sortedMonths =
        _historicalPercentages.keys
            .where((month) => month != currentMonthKey)
            .toList()
          ..sort((a, b) => b.compareTo(a));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'visit_history_title'.tr(context),
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: sortedMonths.isEmpty
              ? Text('no_data_available_now'.tr(context))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: sortedMonths.length,
                  itemBuilder: (context, index) {
                    final month = sortedMonths[index];
                    final percentage = _historicalPercentages[month] ?? 0.0;
                    final displayMonth = month.replaceAll("-", " / ");

                    return ListTile(
                      title: Text(displayMonth),
                      trailing: Text(
                        "${(percentage * 100).toStringAsFixed(1)}%",
                        style: TextStyle(
                          color: percentage >= 0.8
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close_button'.tr(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitProgressIndicator() {
    final percentage = _calculateVisitPercentage();
    final visitedCount = _kidVisitedThisMonth.values.where((v) => v).length;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: MediaQuery.of(context).size.height * 0.01,
      ),
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'visit_indicator_current_month'.tr(context),
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width * 0.04,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(percentage * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.04,
                  fontWeight: FontWeight.bold,
                  color: _getPercentageColor(percentage),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.01),
          LinearProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              _getPercentageColor(percentage),
            ),
            borderRadius: BorderRadius.circular(10),
            minHeight: MediaQuery.of(context).size.height * 0.015,
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.008),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'visited_count_out_of'
                    .tr(context)
                    .replaceFirst('%s', visitedCount.toString())
                    .replaceFirst('%s', widget.kids.length.toString()),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.032,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'remaining_count'
                    .tr(context)
                    .replaceFirst('%s', '${widget.kids.length - visitedCount}'),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.032,
                  color: Colors.red.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getPercentageColor(double percentage) {
    if (percentage >= 0.8) return Colors.green;
    if (percentage >= 0.5) return Colors.orange;
    return Colors.red;
  }

  Widget _buildKidTile(BuildContext context, Kid kid, int visitCount) {
    String phoneText = kid.phones.isNotEmpty
        ? kid.getPhoneWithOwner(context, kid.phones.first)
        : 'no_registered_phone'.tr(context);
    Color phoneColor = kid.phones.isNotEmpty
        ? Colors.green.shade700
        : Colors.red.shade500;
    IconData phoneIcon = kid.phones.isNotEmpty ? Icons.call : Icons.cancel;

    Color countColor = visitCount == 0
        ? Colors.red.shade700
        : visitCount == 1
        ? Colors.orange.shade700
        : Colors.green.shade700;
    Color countBgColor = visitCount == 0
        ? Colors.red.shade100
        : visitCount == 1
        ? Colors.orange.shade100
        : Colors.green.shade100;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.04,
        vertical: MediaQuery.of(context).size.height * 0.006,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width * 0.04,
          vertical: MediaQuery.of(context).size.height * 0.01,
        ),
        leading: SizedBox(
          width: MediaQuery.of(context).size.width * 0.14,
          height: MediaQuery.of(context).size.width * 0.14,
          child: Stack(
            children: [
              // 🖼️ الصورة الشخصية مع ميزة التكبير
              GestureDetector(
                onTap: () {
                  if (kid.photoUrl != null || kid.localImagePath != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImage(
                          imageUrl: kid.photoUrl,
                          localPath: kid.localImagePath,
                          tag: 'indiv_${kid.id}',
                        ),
                      ),
                    );
                  }
                },
                child: Hero(
                  tag: 'indiv_${kid.id}',
                  child: CircleAvatar(
                    radius: MediaQuery.of(context).size.width * 0.065,
                    backgroundColor: Colors.grey.shade100,
                    backgroundImage:
                        (kid.localImagePath != null &&
                            kid.localImagePath!.isNotEmpty &&
                            !kIsWeb) // 🚀 Check !kIsWeb
                        ? FileImage(File(kid.localImagePath!))
                        : ((kid.photoUrl != null && kid.photoUrl!.isNotEmpty)
                                  ? CachedNetworkImageProvider(
                                      kid.photoUrl!,
                                      cacheManager: ImageCacheService.instance,
                                    )
                                  : null)
                              as ImageProvider?,
                    child:
                        ((kid.photoUrl == null || kid.photoUrl!.isEmpty) &&
                            (kid.localImagePath == null ||
                                kid.localImagePath!.isEmpty ||
                                kIsWeb)) // 🚀 Check kIsWeb
                        ? Icon(
                            Icons.face,
                            color: Colors.grey.shade400,
                            size: MediaQuery.of(context).size.width * 0.08,
                          )
                        : null,
                  ),
                ),
              ),
              // 🏷️ Badge عدد الزيارات
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: countBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width * 0.055,
                    minHeight: MediaQuery.of(context).size.width * 0.055,
                  ),
                  child: Center(
                    child: Text(
                      visitCount.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: countColor,
                        fontSize: MediaQuery.of(context).size.width * 0.028,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          kid.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: MediaQuery.of(context).size.width * 0.042,
            color: Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.004),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: MediaQuery.of(context).size.width * 0.035,
                  color: Colors.blue.shade600,
                ),
                SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        Kid.openMap(context, kid.locationUrl, kid.address),
                    child: Text(
                      kid.address,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.033,
                        color:
                            (kid.locationUrl != null &&
                                kid.locationUrl!.isNotEmpty)
                            ? Colors.blue.shade700
                            : Colors.grey.shade700,
                        decoration:
                            (kid.locationUrl != null &&
                                kid.locationUrl!.isNotEmpty)
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.004,
              ),
              child: Row(
                children: [
                  Icon(
                    phoneIcon,
                    size: MediaQuery.of(context).size.width * 0.035,
                    color: phoneColor,
                  ),
                  SizedBox(width: MediaQuery.of(context).size.width * 0.01),
                  Expanded(
                    child: Text(
                      phoneText,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.032,
                        color: phoneColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: MediaQuery.of(context).size.width * 0.06,
          color: Colors.grey,
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KidVisitTracker(
                kid: kid,
                servantName: widget.servantName,
                groupId: widget.groupId,
              ),
            ),
          );
          // تحديث البيانات عند العودة من صفحة الزيارات
          _fetchVisitCounts();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Kid> sortedKids = List.from(_filteredKids);

    if (!_isLoading) {
      sortedKids.sort((a, b) {
        final countA = _kidVisitCounts[a.name] ?? 0;
        final countB = _kidVisitCounts[b.name] ?? 0;
        return countA.compareTo(countB);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'grade_kids_title'
              .tr(context)
              .replaceFirst('%s', widget.gradeTitle)
              .replaceFirst('%s', widget.kids.length.toString()),
          style: TextStyle(fontSize: MediaQuery.of(context).size.width * 0.04),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showVisitHistoryDialog,
            tooltip: 'visit_history_tooltip'.tr(context),
          ),
          IconButton(
            icon: Icon(
              Icons.search,
              size: MediaQuery.of(context).size.width * 0.06,
            ),
            onPressed: () {
              showSearch(
                context: context,
                delegate: KidsSearchDelegate(
                  kids: widget.kids,
                  servantName: widget.servantName,
                  visitCounts: _kidVisitCounts,
                  context: context,
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.grey.shade50,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
              color: Colors.white,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.06,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'search_kids_hint'.tr(context),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF0288D1),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xFF0288D1),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (!_isLoading) _buildVisitProgressIndicator(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_filteredKids.isEmpty && _searchController.text.isNotEmpty)
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: MediaQuery.of(context).size.width * 0.15,
                            color: Colors.grey.shade400,
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.02,
                          ),
                          Text(
                            'no_search_results'.tr(context),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize:
                                  MediaQuery.of(context).size.width * 0.04,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshPageData,
                      child: ListView.builder(
                        padding: EdgeInsets.symmetric(
                          vertical: MediaQuery.of(context).size.height * 0.01,
                        ),
                        itemCount: sortedKids.length,
                        itemBuilder: (context, index) {
                          final kid = sortedKids[index];
                          final visitCount = _kidVisitCounts[kid.name] ?? 0;
                          return _buildKidTile(context, kid, visitCount);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------
// 🔹 صفحة البحث المتقدم داخل الصف
// ----------------------------------------------------

class KidsSearchDelegate extends SearchDelegate {
  final List<Kid> kids;
  final String servantName;
  final Map<String, int> visitCounts;
  final BuildContext context;

  KidsSearchDelegate({
    required this.kids,
    required this.servantName,
    required this.visitCounts,
    required this.context,
  });

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear, size: MediaQuery.of(context).size.width * 0.06),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.arrow_back,
        size: MediaQuery.of(context).size.width * 0.06,
      ),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    final List<Kid> filteredKids = query.isEmpty
        ? kids
        : kids.where((kid) => kid.matchesQuery(query)).toList();

    filteredKids.sort((a, b) {
      final countA = visitCounts[a.name] ?? 0;
      final countB = visitCounts[b.name] ?? 0;
      return countA.compareTo(countB);
    });

    if (filteredKids.isEmpty && query.isNotEmpty) {
      return Center(child: Text('no_search_results'.tr(context)));
    }

    return Container(
      color: Colors.grey.shade50,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.01,
        ),
        itemCount: filteredKids.length,
        itemBuilder: (context, index) {
          final kid = filteredKids[index];
          final visitCount = visitCounts[kid.name] ?? 0;

          return Container(
            margin: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width * 0.04,
              vertical: MediaQuery.of(context).size.height * 0.006,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.04,
                vertical: MediaQuery.of(context).size.height * 0.012,
              ),
              leading: CircleAvatar(
                radius: MediaQuery.of(context).size.width * 0.06,
                backgroundColor: visitCount == 0
                    ? Colors.red.shade100
                    : Colors.green.shade100,
                child: Text(
                  visitCount.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: visitCount == 0
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                    fontSize: MediaQuery.of(context).size.width * 0.045,
                  ),
                ),
              ),
              title: Text(
                kid.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: MediaQuery.of(context).size.width * 0.042,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () =>
                        Kid.openMap(context, kid.locationUrl, kid.address),
                    child: Text(
                      kid.address,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.033,
                        color:
                            (kid.locationUrl != null &&
                                kid.locationUrl!.isNotEmpty)
                            ? Colors.blue.shade700
                            : Colors.grey.shade700,
                        decoration:
                            (kid.locationUrl != null &&
                                kid.locationUrl!.isNotEmpty)
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (kid.phones.isNotEmpty) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.004,
                    ),
                    Text(
                      '${'phone_label'.tr(context)} ${kid.getPhoneWithOwner(context, kid.phones.first)}',
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.032,
                        color: Colors.green.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: MediaQuery.of(context).size.width * 0.06,
                color: Colors.grey,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => KidVisitTracker(
                      kid: kid,
                      servantName: servantName,
                      groupId:
                          context
                              .findAncestorStateOfType<_GradeKidsPageState>()
                              ?.widget
                              .groupId ??
                          '',
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------
// 🔹 صفحة تتبع زيارات المخدوم - مع إضافة نظام الصور
// ----------------------------------------------------

class KidVisitTracker extends StatefulWidget {
  final Kid kid;
  final String servantName;
  final String groupId;

  const KidVisitTracker({
    required this.kid,
    required this.servantName,
    required this.groupId,
    super.key,
  });

  @override
  State<KidVisitTracker> createState() => _KidVisitTrackerState();
}

class _KidVisitTrackerState extends State<KidVisitTracker> {
  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  late Realtime _realtime;
  RealtimeSubscription? _visitSubscription;

  final String _collectionName = 'individual_visits';
  static const String databaseId = 'main_db';

  // 🚀 إعدادات رفع الصور
  final ImageService _imageService = ImageService();

  // 🚀 متغيرات رفع الصور
  // 🚀 Modified for Web Support (Use XFile instead of File)
  final List<XFile> _selectedImages = [];
  bool _isUploading = false;
  String? _currentUserEmail;

  List<models.Document> _visits = [];
  bool _isVisitsLoading = true;
  bool _canAddVisit = true; // 🚀 New: Subscription enforcement

  /// Helper function to safely unbox cached Appwrite data that might be nested
  Map<String, dynamic> _getActualData(dynamic inputData) {
    if (inputData is Map<String, dynamic>) {
      if (inputData.containsKey('data') && inputData['data'] is Map) {
        return Map<String, dynamic>.from(inputData['data']);
      }
      return inputData;
    }
    return {};
  }

  @override
  void initState() {
    super.initState();
    _realtime = AppwriteService().realtime;
    _initUser();
    // 🚀 Load from cache FIRST
    _loadCachedVisits();
    _fetchVisits();
    _checkSubscription();
  }

  Future<void> _checkSubscription() async {
    final canWrite = await PermissionService.canWrite(widget.groupId);
    if (mounted) {
      setState(() {
        _canAddVisit = canWrite;
      });
    }
  }

  Future<void> _loadCachedVisits() async {
    try {
      final cachedData = await DataCacheService().getCachedKidVisits(
        widget.groupId,
        widget.kid.name,
      );
      if (cachedData.isNotEmpty && mounted) {
        setState(() {
          if (_visits.isEmpty) {
            _visits = cachedData
                .map((e) => models.Document.fromMap(e))
                .toList();
            _isVisitsLoading = false;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _initUser() async {
    try {
      final user = await _account.get();
      if (mounted) {
        setState(() {
          _currentUserEmail = user.email;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchVisits() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: _collectionName,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('kidName', widget.kid.name),
          Query.orderDesc('timestamp'),
          Query.limit(100),
        ],
      );

      if (mounted) {
        setState(() {
          _visits = result.documents;
          _isVisitsLoading = false;
        });
      }

      // 🚀 Save to cache
      await DataCacheService().cacheKidVisits(
        widget.groupId,
        widget.kid.name,
        result.documents.map((e) => e.toMap()).toList(),
      );

      // 2. Realtime Listener
      _visitSubscription?.close();
      _visitSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.$_collectionName.documents',
      ]);

      _visitSubscription!.stream.listen((event) {
        if (mounted) {
          final payload = event.payload;
          // Filter locally or re-fetch
          if (payload['groupId'] == widget.groupId &&
              payload['kidName'] == widget.kid.name) {
            _reFetchVisits();
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isVisitsLoading = false);
      }
    }
  }

  Future<void> _reFetchVisits() async {
    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: _collectionName,
        queries: [
          Query.equal('groupId', widget.groupId),
          Query.equal('kidName', widget.kid.name),
          Query.orderDesc('timestamp'),
          Query.limit(100),
        ],
      );
      if (mounted) {
        setState(() {
          _visits = result.documents;
        });
      }
    } catch (_) {}
  }

  bool _canDeleteVisit(Map<String, dynamic> visitData) {
    if (_currentUserEmail == null) return false;

    final String? visitServantName = visitData['servantName'] as String?;

    if (visitServantName == widget.servantName) {
      return true;
    }

    if (_currentUserEmail == 'magdyyacoub@gmail.com') {
      return true;
    }

    return false;
  }

  Future<void> _deleteVisit(String visitId) async {
    if (!await PermissionService.canWrite(widget.groupId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('subscription_expired_msg'.tr(context))),
        );
      }
      return;
    }
    try {
      final bool online = await SyncService().isOnline();

      // 🚀 Offline Logic
      if (!online) {
        await DataCacheService().addPendingOperation({
          'type': 'individual_visit_delete',
          'data': {
            'visitId': visitId,
            'groupId': widget.groupId,
            'kidName': widget.kid.name,
            'kidGrade': widget.kid.grade,
          },
        });

        // 🚀 Optimistic UI
        if (mounted) {
          setState(() {
            _visits.removeWhere((v) => v.$id == visitId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('visit_deleted_success_offline'.tr(context)),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        // Update Cache
        await DataCacheService().removeIndividualVisitFromCache(
          widget.groupId,
          widget.kid.grade ?? 'unspecified_grade',
          visitId,
        );
        await DataCacheService().removeKidVisitFromCache(
          widget.groupId,
          widget.kid.name,
          visitId,
        );
        return;
      }

      // 1. جلب بيانات الزيارة قبل حذفها للحصول على معرفات الصور
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: _collectionName,
        documentId: visitId,
      );

      final List<dynamic> imageUrls = doc.data['imageUrls'] ?? [];
      final List<dynamic> publicIds = doc.data['publicIds'] ?? [];

      // 2. حذف الصور من Appwrite Storage
      for (var id in publicIds) {
        if (id != null) {
          await _imageService.deleteImage(id.toString());
        }
      }

      // 3. حذف الصور من صفحة الحالات (Statuses)
      final statusService = StatusService(groupId: widget.groupId);
      for (var url in imageUrls) {
        if (url != null) {
          await statusService.deleteStatusByImageUrl(url.toString());
        }
      }

      // 4. حذف سجل الزيارة من قاعدة البيانات
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: _collectionName,
        documentId: visitId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('visit_deleted_success'.tr(context)),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // 🔥 تحديث فوري للقائمة
        await _reFetchVisits();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'visit_delete_failed'.tr(context)}: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(
    BuildContext context,
    String visitId,
    String visitSubject,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("confirm_delete_title".tr(context)),
          content: Text(
            "confirm_delete_visit_message"
                .tr(context)
                .replaceFirst('%s', visitSubject),
          ),
          actions: [
            TextButton(
              child: Text('cancel'.tr(context)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: Text('delete'.tr(context)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteVisit(visitId);
              },
            ),
          ],
        );
      },
    );
  }

  void _showPhoneOptions(BuildContext context, String phone) {
    final phoneWithOwner = widget.kid.getPhoneWithOwner(context, phone);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
            ),
          ],
        ),
        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.05),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "phone_options_title".tr(context),
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.045,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
            Text(
              widget.kid.name,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.04,
                color: Colors.blue.shade700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              phoneWithOwner,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.035,
                color: Colors.blue.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.phone,
                color: Colors.green,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              title: Text(
                "direct_call_option".tr(context),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.038,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse("tel:$phone"));
              },
            ),
            ListTile(
              leading: Icon(
                Icons.message,
                color: const Color(0xFF25D366),
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              title: Text(
                "whatsapp_message_option".tr(context),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.038,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse("https://wa.me/$phone"));
              },
            ),
            ListTile(
              leading: Icon(
                Icons.content_copy,
                color: Colors.orange,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              title: Text(
                "copy_number_option".tr(context),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.038,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: phone));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "number_copied_success"
                          .tr(context)
                          .replaceFirst('%s', phone),
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 دوال رفع الصور
  Future<dynamic> compressImage(XFile file) async {
    // 🚀 Skip compression on Web
    if (kIsWeb) return file;

    final dir = await getTemporaryDirectory();
    final targetPath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.jpg",
    );

    var result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 85,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );

    return result ?? file;
  }

  Future<void> _addVisit({
    required String title,
    required String subject,
    required DateTime date,
    required TimeOfDay time,
    required String type,
    required String servantName,
  }) async {
    // 🔐 Check Permission
    if (!await PermissionService.canWrite(widget.groupId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("subscription_expired_or_offline".tr(context))),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _isUploading = true;
    });

    final errorMsg = "image_upload_failed".tr(context);
    final statusCaptionBase = "new_visitation_status".tr(context);
    final statusSource = "visitation_source".tr(context);

    try {
      final DateTime visitDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      final String visitId = ID.unique();
      final Map<String, dynamic> visitData = {
        'groupId': widget.groupId,
        'kidName': widget.kid.name,
        'kidGrade': widget.kid.grade,
        'visitType': type,
        'visitTitle': title,
        'subject': subject,
        'timestamp': visitDateTime.toIso8601String(),
        'servantName': servantName,
        'addedAt': DateTime.now().toIso8601String(),
        'imageUrls': [], // Will be filled by sync or if online
        'publicIds': [],
      };

      // 🚀 Offline Logic
      final bool online = await SyncService().isOnline();
      if (!online) {
        final List<String> localPaths = _selectedImages
            .map((f) => f.path)
            .toList();
        await DataCacheService().addPendingOperation({
          'type': 'individual_visit',
          'data': {
            ...visitData,
            'localImagePaths': localPaths,
            'visitId': visitId,
          },
        });

        // 🚀 Optimistic UI
        final tempDoc = models.Document(
          $id: visitId,
          $collectionId: _collectionName,
          $databaseId: databaseId,
          $createdAt: DateTime.now().toIso8601String(),
          $updatedAt: DateTime.now().toIso8601String(),
          $permissions: [],
          data: {
            ...visitData,
            'localImagePaths':
                localPaths, // Keep local paths for immediate display if needed
          },
        );

        if (mounted) {
          setState(() {
            _visits.insert(0, tempDoc);
            _isUploading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('visit_recorded_success_offline'.tr(context)),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _selectedImages.clear();
        }

        // Update Cache
        await DataCacheService().upsertIndividualVisitInCache(
          widget.groupId,
          widget.kid.grade ?? 'unspecified_grade',
          tempDoc.toMap(),
        );
        await DataCacheService().upsertKidVisitInCache(
          widget.groupId,
          widget.kid.name,
          tempDoc.toMap(),
        );
        return;
      }

      // 🚀 رفع الصور إذا كانت موجودة (Online Path)
      List<String> imageLinks = [];
      List<String> publicIds = [];

      if (_selectedImages.isNotEmpty) {
        for (XFile imageFile in _selectedImages) {
          final compressedImage = await compressImage(imageFile);
          Map<String, String>? uploadResult = await _imageService.uploadImage(
            compressedImage,
          );

          if (uploadResult != null) {
            imageLinks.add(uploadResult['url']!);
            publicIds.add(uploadResult['id']!);
          } else {
            throw Exception(errorMsg);
          }
        }
      }

      // حفظ البيانات مع الصور
      final finalData = {
        ...visitData,
        'imageUrls': imageLinks,
        'publicIds': publicIds,
      };

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: _collectionName,
        documentId: visitId,
        data: finalData,
      );

      // 🚀 [NEW] إضافة الصور إلى "الحالات" (Statuses)
      if (imageLinks.isNotEmpty) {
        final statusService = StatusService(groupId: widget.groupId);
        for (String url in imageLinks) {
          await statusService.addStatus(
            imageUrl: url,
            caption: statusCaptionBase
                .replaceFirst('%s', widget.kid.name)
                .replaceFirst('%s', title),
            source: statusSource,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'visit_recorded_success'
                  .tr(context)
                  .replaceFirst('%s', widget.kid.name),
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // 🔥 تحديث فوري للقائمة
        await _reFetchVisits();

        // مسح الصور بعد الحفظ الناجح
        _selectedImages.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'visit_record_failed'.tr(context)}: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // 🚀 دالة عرض معرض الصور
  void _showImageGallery(List<String> imageUrls, int initialIndex) {
    if (imageUrls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageGallery(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          tagPrefix: 'gallery',
        ),
      ),
    );
  }

  String _getLocalizedType(String dbType, BuildContext context) {
    switch (dbType) {
      case 'home_visit':
      case 'زيارة منزلية':
      case 'Home Visit':
        return 'home_visit'.tr(context);
      case 'phone_call':
      case 'مكالمة تليفونية':
      case 'Phone Call':
        return 'phone_call'.tr(context);
      case 'external_meeting':
      case 'تقابل خارجي':
      case 'External Meeting':
        return 'external_meeting'.tr(context);
      case 'study_follow_up':
      case 'متابعة دراسية':
      case 'Study Follow Up':
        return 'study_follow_up'.tr(context);
      case 'spiritual_activity':
      case 'نشاط روحي':
      case 'Spiritual Activity':
        return 'spiritual_activity'.tr(context);
      case 'visit_type_default':
      case 'زيارة':
      case 'Visit':
        return 'visit_type_default'.tr(context);
      default:
        return dbType;
    }
  }

  // 🔥 دالة عرض تفاصيل الزيارة في Dialog
  void _showVisitDetailsDialog(
    Map<String, dynamic> visitData,
    List<String> cachedImageUrls,
  ) {
    // 🚀 Unbox data if wrapped
    visitData = _getActualData(visitData);

    final timestampStr = visitData['timestamp'];
    final date = timestampStr != null
        ? DateTime.parse(timestampStr)
        : DateTime.now();
    final type = _getLocalizedType(
      visitData['visitType'] ?? 'visit_type_default',
      context,
    );

    // Get both remote and local image paths
    final List<dynamic> localImagePaths = visitData['localImagePaths'] ?? [];
    final bool hasUploadedImages = cachedImageUrls.isNotEmpty;
    final bool hasLocalImages = localImagePaths.isNotEmpty;
    final locale = Localizations.localeOf(context).languageCode;
    final servant = visitData['servantName'] ?? 'unknown_servant'.tr(context);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.05),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Header ---
                  Row(
                    children: [
                      Icon(
                        (type.contains('مكالمة') || type.contains('Call'))
                            ? Icons.call_made
                            : Icons.home_filled,
                        color: Colors.blue.shade800,
                        size: MediaQuery.of(context).size.width * 0.08,
                      ),
                      SizedBox(width: MediaQuery.of(context).size.width * 0.03),
                      Expanded(
                        child: Text(
                          visitData['visitTitle'] ??
                              visitData['subject'] ??
                              'no_subject_available'.tr(context),
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.05,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                  Divider(
                    height: MediaQuery.of(context).size.height * 0.03,
                    thickness: 2,
                    color: Colors.grey.shade200,
                  ),

                  // --- Body ---
                  _buildDetailRow(
                    'visit_type_label'.tr(context),
                    type,
                    Icons.category,
                  ),
                  _buildDetailRow(
                    'servant_label'.tr(context),
                    servant,
                    Icons.person,
                  ),
                  _buildDetailRow(
                    'date_label'.tr(context),
                    DateFormat('yyyy/MM/dd', locale).format(date),
                    Icons.calendar_today,
                  ),
                  _buildDetailRow(
                    'time_label'.tr(context),
                    DateFormat('hh:mm a', locale).format(date),
                    Icons.access_time,
                  ),

                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  Text(
                    'visit_subject_details'.tr(context),
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.045,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(
                      MediaQuery.of(context).size.width * 0.04,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Text(
                      visitData['subject'] ??
                          'no_details_available'.tr(context),
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.04,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),

                  // --- Images (if any) ---
                  if (hasUploadedImages || hasLocalImages) ...[
                    SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                    Text(
                      'attached_images_label'.tr(context),
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.045,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.15,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: hasUploadedImages
                            ? cachedImageUrls.length
                            : localImagePaths.length,
                        itemBuilder: (context, index) {
                          final isLocal = !hasUploadedImages;
                          final imagePathOrUrl = isLocal
                              ? localImagePaths[index].toString()
                              : cachedImageUrls[index];

                          return GestureDetector(
                            onTap: () {
                              if (isLocal) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImageGallery(
                                      localPaths: localImagePaths
                                          .map((e) => e.toString())
                                          .toList(),
                                      initialIndex: index,
                                      tagPrefix: 'local_gallery',
                                    ),
                                  ),
                                );
                              } else {
                                _showImageGallery(cachedImageUrls, index);
                              }
                            },
                            child: Container(
                              margin: EdgeInsets.only(
                                right: MediaQuery.of(context).size.width * 0.03,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isLocal
                                    ? Image.file(
                                        File(imagePathOrUrl),
                                        width:
                                            MediaQuery.of(context).size.height *
                                            0.15,
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.15,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  width:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.height *
                                                      0.15,
                                                  height:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.height *
                                                      0.15,
                                                  color: Colors.grey.shade200,
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: imagePathOrUrl,
                                        width:
                                            MediaQuery.of(context).size.height *
                                            0.15,
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.15,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(
                                              width:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.15,
                                              height:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.15,
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                              width:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.15,
                                              height:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.15,
                                              color: Colors.grey.shade200,
                                              child: Icon(
                                                Icons.broken_image,
                                                color: Colors.grey,
                                                size:
                                                    MediaQuery.of(
                                                      context,
                                                    ).size.width *
                                                    0.08,
                                              ),
                                            ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width * 0.1,
                          vertical: MediaQuery.of(context).size.height * 0.015,
                        ),
                      ),
                      child: Text(
                        'close_button'.tr(context),
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width * 0.045,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.005,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: MediaQuery.of(context).size.width * 0.04,
            color: Colors.blue.shade600,
          ),
          SizedBox(width: MediaQuery.of(context).size.width * 0.02),
          Text(
            label,
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width * 0.035,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(width: MediaQuery.of(context).size.width * 0.02),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.035,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddVisitDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController subjectController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    String? selectedTypeKey = 'home_visit';

    final Map<String, String> visitTypesMap = {
      'home_visit': 'home_visit'.tr(context),
      'phone_call': 'phone_call'.tr(context),
      'external_meeting': 'external_meeting'.tr(context),
      'study_follow_up': 'study_follow_up'.tr(context),
      'spiritual_activity': 'spiritual_activity'.tr(context),
    };

    // 🚀 Modified for Web Support (Use XFile)
    List<XFile> localSelectedImages = [];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickImagesLocal() async {
              final picker = ImagePicker();
              final List<XFile> pickedFiles = await picker.pickMultiImage();
              if (pickedFiles.isNotEmpty) {
                setDialogState(() {
                  localSelectedImages.addAll(
                    pickedFiles,
                  ); // 🚀 Store XFiles directly
                });
              }
            }

            void removeImageLocal(int index) {
              setDialogState(() {
                localSelectedImages.removeAt(index);
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔹 العنوان
                    Container(
                      padding: EdgeInsets.all(
                        MediaQuery.of(context).size.width * 0.04,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          "add_new_visit".tr(context),
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width * 0.045,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ),

                    // 🔹 المحتوى القابل للتمرير
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width * 0.02,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // 🔹 حقل عنوان الموضوع
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.8,
                                ),
                                child: TextFormField(
                                  controller: titleController,
                                  decoration: InputDecoration(
                                    labelText: 'visit_title_label'.tr(context),
                                    border: const OutlineInputBorder(),
                                    hintText: 'visit_title_hint'.tr(context),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 16,
                                    ),
                                  ),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                        0.035,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),

                              // 🔹 نوع الزيارة
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.8,
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedTypeKey,
                                  items: visitTypesMap.entries.map((entry) {
                                    return DropdownMenuItem<String>(
                                      value: entry.key,
                                      child: Text(
                                        entry.value,
                                        style: TextStyle(
                                          fontSize:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.033,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedTypeKey = value;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'visit_type_label'.tr(context),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  isExpanded: true,
                                ),
                              ),
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),

                              // 🔹 التاريخ والوقت - معدل
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'date_label'.tr(context),
                                            style: TextStyle(
                                              fontSize:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.033,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          SizedBox(
                                            height:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                0.005,
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: InkWell(
                                              onTap: () async {
                                                final pickedDate =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate: selectedDate,
                                                      firstDate: DateTime(2023),
                                                      lastDate: DateTime.now(),
                                                    );
                                                if (pickedDate != null) {
                                                  setDialogState(() {
                                                    selectedDate = pickedDate;
                                                  });
                                                }
                                              },
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.height *
                                                      0.012,
                                                  horizontal:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.width *
                                                      0.02,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.calendar_today,
                                                      size:
                                                          MediaQuery.of(
                                                            context,
                                                          ).size.width *
                                                          0.035,
                                                      color:
                                                          Colors.blue.shade700,
                                                    ),
                                                    SizedBox(
                                                      width:
                                                          MediaQuery.of(
                                                            context,
                                                          ).size.width *
                                                          0.015,
                                                    ),
                                                    Flexible(
                                                      child: Text(
                                                        DateFormat(
                                                          'yyyy/MM/dd',
                                                          Localizations.localeOf(
                                                            context,
                                                          ).languageCode,
                                                        ).format(selectedDate),
                                                        style: TextStyle(
                                                          fontSize:
                                                              MediaQuery.of(
                                                                context,
                                                              ).size.width *
                                                              0.032,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.02,
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'time_label'.tr(context),
                                            style: TextStyle(
                                              fontSize:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.033,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          SizedBox(
                                            height:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                0.005,
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: InkWell(
                                              onTap: () async {
                                                final pickedTime = await showTimePicker(
                                                  context: context,
                                                  initialTime: selectedTime,
                                                  builder:
                                                      (
                                                        BuildContext context,
                                                        Widget? child,
                                                      ) {
                                                        return Localizations.override(
                                                          context: context,
                                                          locale: Locale(
                                                            Localizations.localeOf(
                                                              context,
                                                            ).languageCode,
                                                          ),
                                                          child: child!,
                                                        );
                                                      },
                                                );
                                                if (pickedTime != null) {
                                                  setDialogState(() {
                                                    selectedTime = pickedTime;
                                                  });
                                                }
                                              },
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.height *
                                                      0.012,
                                                  horizontal:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.width *
                                                      0.02,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.access_time,
                                                      size:
                                                          MediaQuery.of(
                                                            context,
                                                          ).size.width *
                                                          0.035,
                                                      color:
                                                          Colors.blue.shade700,
                                                    ),
                                                    SizedBox(
                                                      width:
                                                          MediaQuery.of(
                                                            context,
                                                          ).size.width *
                                                          0.015,
                                                    ),
                                                    Flexible(
                                                      child: Text(
                                                        selectedTime.format(
                                                          context,
                                                        ),
                                                        style: TextStyle(
                                                          fontSize:
                                                              MediaQuery.of(
                                                                context,
                                                              ).size.width *
                                                              0.032,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
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
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),

                              // 🔹 موضوع الزيارة
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.8,
                                ),
                                child: TextFormField(
                                  controller: subjectController,
                                  decoration: InputDecoration(
                                    labelText: 'visit_subject_label'.tr(
                                      context,
                                    ),
                                    border: const OutlineInputBorder(),
                                    hintText: 'visit_subject_hint'.tr(context),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 16,
                                    ),
                                  ),
                                  maxLines: 3,
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.width *
                                        0.035,
                                  ),
                                ),
                              ),

                              // 🔹 قسم الصور
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.8,
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: _isUploading
                                      ? null
                                      : pickImagesLocal,
                                  icon: Icon(
                                    Icons.photo_library,
                                    size:
                                        MediaQuery.of(context).size.width *
                                        0.04,
                                  ),
                                  label: Text(
                                    localSelectedImages.isEmpty
                                        ? 'add_images_optional'.tr(context)
                                        : 'images_selected'
                                              .tr(context)
                                              .replaceFirst(
                                                '%s',
                                                localSelectedImages.length
                                                    .toString(),
                                              ),
                                    style: TextStyle(
                                      fontSize:
                                          MediaQuery.of(context).size.width *
                                          0.032,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade50,
                                    foregroundColor: Colors.blue.shade700,
                                    minimumSize: Size(
                                      double.infinity,
                                      MediaQuery.of(context).size.height * 0.06,
                                    ),
                                  ),
                                ),
                              ),

                              // 🔹 معرض الصور المختارة
                              if (localSelectedImages.isNotEmpty)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.8,
                                    maxHeight:
                                        MediaQuery.of(context).size.height *
                                        0.12,
                                  ),
                                  child: Container(
                                    padding: EdgeInsets.only(
                                      top:
                                          MediaQuery.of(context).size.height *
                                          0.01,
                                    ),
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: localSelectedImages.length,
                                      itemBuilder: (context, index) {
                                        return Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.008,
                                          ),
                                          child: Stack(
                                            alignment: Alignment.topLeft,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: kIsWeb
                                                    ? Image.network(
                                                        localSelectedImages[index]
                                                            .path,
                                                        height:
                                                            MediaQuery.of(
                                                              context,
                                                            ).size.height *
                                                            0.08,
                                                        width:
                                                            MediaQuery.of(
                                                              context,
                                                            ).size.height *
                                                            0.08,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Image.file(
                                                        File(
                                                          localSelectedImages[index]
                                                              .path,
                                                        ),
                                                        height:
                                                            MediaQuery.of(
                                                              context,
                                                            ).size.height *
                                                            0.08,
                                                        width:
                                                            MediaQuery.of(
                                                              context,
                                                            ).size.height *
                                                            0.08,
                                                        fit: BoxFit.cover,
                                                      ),
                                              ),
                                              Container(
                                                margin: EdgeInsets.all(3),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: InkWell(
                                                  onTap: () =>
                                                      removeImageLocal(index),
                                                  child: Icon(
                                                    Icons.close,
                                                    color: Colors.white,
                                                    size:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width *
                                                        0.03,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),

                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.02,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 🔹 الأزرار
                    Container(
                      padding: EdgeInsets.all(
                        MediaQuery.of(context).size.width * 0.03,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: Text(
                                'cancel_btn'.tr(context),
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize:
                                      MediaQuery.of(context).size.width * 0.04,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.03,
                          ),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical:
                                      MediaQuery.of(context).size.height *
                                      0.015,
                                ),
                              ),
                              onPressed: _isUploading
                                  ? null
                                  : () async {
                                      if (!await PermissionService.canWrite(
                                        widget.groupId,
                                      )) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'subscription_read_only_warning'
                                                    .tr(context),
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      if (titleController.text.trim().isEmpty ||
                                          subjectController.text
                                              .trim()
                                              .isEmpty ||
                                          selectedTypeKey == null) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'required'.tr(context),
                                              ),
                                              backgroundColor:
                                                  Colors.red.shade600,
                                            ),
                                          );
                                        }
                                        return;
                                      }

                                      // 🚀 نقل الصور للمتغير الرئيسي
                                      setState(() {
                                        _selectedImages.clear();
                                        _selectedImages.addAll(
                                          localSelectedImages,
                                        );
                                      });

                                      if (!dialogContext.mounted) return;

                                      Navigator.of(dialogContext).pop();

                                      await _addVisit(
                                        title: titleController.text.trim(),
                                        subject: subjectController.text.trim(),
                                        date: selectedDate,
                                        time: selectedTime,
                                        type: selectedTypeKey!,
                                        servantName: widget.servantName,
                                      );
                                    },
                              child: _isUploading
                                  ? SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.025,
                                      width:
                                          MediaQuery.of(context).size.height *
                                          0.025,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'add_visit_button'.tr(context),
                                      style: TextStyle(
                                        fontSize:
                                            MediaQuery.of(context).size.width *
                                            0.04,
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'visit_records_title'.tr(context).replaceFirst('%s', widget.kid.name),
          style: TextStyle(fontSize: MediaQuery.of(context).size.width * 0.04),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildKidInfoCard(context),
          Expanded(
            child: _isVisitsLoading
                ? const Center(child: CircularProgressIndicator())
                : _visits.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.of(context).size.width * 0.05,
                      ),
                      child: Text(
                        'no_visits_added_yet'
                            .tr(context)
                            .replaceFirst('%s', widget.kid.name),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: MediaQuery.of(context).size.width * 0.04,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(
                      MediaQuery.of(context).size.width * 0.03,
                    ),
                    itemCount: _visits.length,
                    itemBuilder: (context, index) {
                      final visitDoc = _visits[index];
                      // 🚀 Unbox offline payload format if needed
                      final visitData = _getActualData(visitDoc.data);
                      final visitId = visitDoc.$id;
                      final List<String> imageUrls = List<String>.from(
                        visitData['imageUrls'] ?? [],
                      );

                      // 🔥 استخدام عنوان الموضوع بدلاً من موضوع الزيارة في العرض
                      final displayTitle =
                          visitData['visitTitle'] ??
                          visitData['subject'] ??
                          'no_subject_available'.tr(context);

                      final timestampStr = visitData['timestamp'];
                      final date = timestampStr != null
                          ? DateTime.parse(timestampStr)
                          : DateTime.now();

                      return _buildVisitTile(
                        visitId,
                        displayTitle,
                        _getLocalizedType(
                          visitData['visitType'] ?? 'visit_type_default',
                          context,
                        ),
                        visitData['servantName'] ??
                            'unknown_servant'.tr(context),
                        date,
                        visitData,
                        imageUrls,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canAddVisit
          ? FloatingActionButton.extended(
              onPressed: () => _showAddVisitDialog(context),
              icon: Icon(
                Icons.add,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              label: Text(
                'add_new_visit'.tr(context),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.04,
                ),
              ),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            )
          : FloatingActionButton.extended(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('cannot_add_visit_unsubscribed'.tr(context)),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              icon: Icon(
                Icons.lock,
                size: MediaQuery.of(context).size.width * 0.06,
              ),
              label: Text(
                'subscription_expired_or_offline'.tr(context),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.04,
                ),
              ),
              backgroundColor: Colors.grey.shade400,
              foregroundColor: Colors.white,
            ),
    );
  }

  Widget _buildKidInfoCard(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(MediaQuery.of(context).size.width * 0.03),
      padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.kid.photoUrl != null &&
                  widget.kid.photoUrl!.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImage(
                          imageUrl: widget.kid.photoUrl!,
                          tag: widget.kid.photoUrl!,
                        ),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: MediaQuery.of(context).size.width * 0.07,
                    backgroundImage: CachedNetworkImageProvider(
                      widget.kid.photoUrl!,
                    ),
                  ),
                ),
              ] else ...[
                CircleAvatar(
                  radius: MediaQuery.of(context).size.width * 0.07,
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(
                    Icons.person,
                    size: MediaQuery.of(context).size.width * 0.08,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
              SizedBox(width: MediaQuery.of(context).size.width * 0.04),
              Expanded(
                child: Text(
                  widget.kid.name,
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width * 0.05,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(
            height: MediaQuery.of(context).size.height * 0.01,
            thickness: 1,
          ),
          Row(
            children: [
              Icon(
                Icons.class_,
                size: MediaQuery.of(context).size.width * 0.045,
                color: Colors.blue.shade600,
              ),
              SizedBox(width: MediaQuery.of(context).size.width * 0.02),
              Text(
                'grade_label_prefix'
                    .tr(context)
                    .replaceFirst('%s', widget.kid.grade ?? ''),
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.038,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.005),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on,
                size: MediaQuery.of(context).size.width * 0.045,
                color: Colors.blue.shade600,
              ),
              SizedBox(width: MediaQuery.of(context).size.width * 0.02),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Kid.openMap(
                        context,
                        widget.kid.locationUrl,
                        widget.kid.address,
                      ),
                      child: Text(
                        'address_label_prefix'
                            .tr(context)
                            .replaceFirst('%s', widget.kid.address),
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width * 0.038,
                          color:
                              (widget.kid.locationUrl != null &&
                                  widget.kid.locationUrl!.isNotEmpty)
                              ? Colors.blue.shade700
                              : Colors.grey.shade700,
                          decoration:
                              (widget.kid.locationUrl != null &&
                                  widget.kid.locationUrl!.isNotEmpty)
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          fontWeight:
                              (widget.kid.locationUrl != null &&
                                  widget.kid.locationUrl!.isNotEmpty)
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.01),
          if (widget.kid.phones.isNotEmpty) ...[
            SizedBox(height: MediaQuery.of(context).size.height * 0.008),
            Text(
              'phone_numbers_label'.tr(context),
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.04,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.008),
            Column(
              children: widget.kid.phones.map((phone) {
                final phoneWithOwner = widget.kid.getPhoneWithOwner(
                  context,
                  phone,
                );
                return Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(
                    bottom: MediaQuery.of(context).size.height * 0.008,
                  ),
                  child: OutlinedButton.icon(
                    icon: Icon(
                      Icons.phone_in_talk,
                      size: MediaQuery.of(context).size.width * 0.05,
                    ),
                    label: Text(
                      phoneWithOwner,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.035,
                        color: Colors.green.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _showPhoneOptions(context, phone),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: MediaQuery.of(context).size.height * 0.012,
                        horizontal: MediaQuery.of(context).size.width * 0.04,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.03),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_callback,
                    color: Colors.grey.shade600,
                    size: MediaQuery.of(context).size.width * 0.05,
                  ),
                  SizedBox(width: MediaQuery.of(context).size.width * 0.02),
                  Text(
                    'no_phone_numbers_registered'.tr(context),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: MediaQuery.of(context).size.width * 0.035,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisitTile(
    String visitId,
    String title,
    String type,
    String servant,
    DateTime date,
    Map<String, dynamic> visitData,
    List<String> imageUrls,
  ) {
    bool canDelete = _canDeleteVisit(visitData);
    bool hasImages = imageUrls.isNotEmpty;

    return Card(
      margin: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.006,
        horizontal: 0,
      ),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showVisitDetailsDialog(
          visitData,
          imageUrls,
        ), // 🔥 فتح الـ Dialog عند الضغط
        child: Container(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height * 0.12,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              vertical: MediaQuery.of(context).size.height * 0.01,
              horizontal: MediaQuery.of(context).size.width * 0.04,
            ),
            leading: Icon(
              (type.contains('مكالمة') || type.contains('Phone Call'))
                  ? Icons.call_made
                  : Icons.home_filled,
              color: Colors.blue.shade700,
              size: MediaQuery.of(context).size.width * 0.07,
            ),
            title: Text(
              title, // 🔥 عرض عنوان الموضوع بدلاً من موضوع الزيارة
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: MediaQuery.of(context).size.width * 0.04,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.004,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'visit_type_format'.tr(context).replaceFirst('%s', type),
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.033,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.002),
                  Text(
                    'servant_name_format'
                        .tr(context)
                        .replaceFirst('%s', servant),
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.033,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.002),
                  Text(
                    'visit_date_format'
                        .tr(context)
                        .replaceFirst(
                          '%s',
                          DateFormat(
                            'yyyy/MM/dd - hh:mm a',
                            Localizations.localeOf(context).languageCode,
                          ).format(date),
                        ),
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width * 0.033,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // 🚀 عرض مصغرات الصور إذا كانت موجودة
                  if (hasImages ||
                      (visitData['localImagePaths'] != null &&
                          (visitData['localImagePaths'] as List)
                              .isNotEmpty)) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.008,
                    ),
                    Text(
                      'attached_images_label'.tr(context),
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width * 0.032,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.004,
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.08,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: imageUrls.isNotEmpty
                            ? imageUrls.length
                            : (visitData['localImagePaths'] as List).length,
                        itemBuilder: (context, index) {
                          final isLocal = imageUrls.isEmpty;
                          final imagePathOrUrl = isLocal
                              ? visitData['localImagePaths'][index]
                              : imageUrls[index];

                          return GestureDetector(
                            onTap: () {
                              if (!isLocal) {
                                _showImageGallery(imageUrls, index);
                              }
                            },
                            child: Container(
                              margin: EdgeInsets.only(
                                right: MediaQuery.of(context).size.width * 0.02,
                              ),
                              child: isLocal
                                  ? Image.file(
                                      File(imagePathOrUrl),
                                      width:
                                          MediaQuery.of(context).size.height *
                                          0.08,
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.08,
                                      fit: BoxFit.cover,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imagePathOrUrl,
                                      width:
                                          MediaQuery.of(context).size.height *
                                          0.08,
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.08,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width:
                                            MediaQuery.of(context).size.height *
                                            0.08,
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.08,
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            width:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                0.08,
                                            height:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                0.08,
                                            color: Colors.grey.shade200,
                                            child: Icon(
                                              Icons.broken_image,
                                              color: Colors.grey,
                                              size:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.06,
                                            ),
                                          ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: canDelete
                ? IconButton(
                    icon: Icon(
                      Icons.delete,
                      color: Colors.red,
                      size: MediaQuery.of(context).size.width * 0.06,
                    ),
                    onPressed: () =>
                        _showDeleteConfirmation(context, visitId, title),
                  )
                : Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: MediaQuery.of(context).size.width * 0.05,
                  ),
          ),
        ),
      ),
    );
  }
}
