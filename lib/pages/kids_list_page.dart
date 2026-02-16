import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appwrite/appwrite.dart';
// import 'package:appwrite/models.dart' as models;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/appwrite_service.dart';
import '../services/user_service.dart';
import '../services/permission_service.dart';
import '../services/image_service.dart';
import '../services/data_cache_service.dart';
import '../services/image_cache_service.dart';
import '../services/sync_service.dart';
import '../models/kid.dart';
import '../widgets/full_screen_image.dart';

// Constants
const String databaseId = 'main_db';
const String studentsCollectionId = 'students';

class KidsListPage extends StatefulWidget {
  final String grade;

  const KidsListPage({required this.grade, super.key});

  @override
  State<KidsListPage> createState() => _KidsListPageState();
}

class _KidsListPageState extends State<KidsListPage> {
  final List<String> _phoneOwners = [
    "الاب",
    "الام",
    "الاخ",
    "الاخت",
    "المخدوم",
  ];

  late Client _client;
  late Databases _databases;
  late Realtime _realtime;
  late Account _account; // 🚀 Added Account
  RealtimeSubscription? _kidsSubscription;

  String _currentUserRole = 'loading';
  String _myGroupId = '';
  String? _teamId;
  String searchText = '';

  List<Kid> _liveKids = [];
  List<Kid> _filteredAndSortedKids = [];

  int _total = 0;
  int _visitedCount = 0;
  bool _isLoading = true;
  String _error = '';
  bool _canWrite = true; // 🚀 Subscription Check

  Timer? _searchTimer;

  bool get _isAdmin => _currentUserRole == 'admin';

  @override
  void initState() {
    super.initState();
    _client = AppwriteService().client;
    _databases = Databases(_client);
    _databases = Databases(_client);
    _realtime = Realtime(_client);
    _account = AppwriteService().account; // 🚀 Init Account

    _loadUserData();
  }

  @override
  void dispose() {
    _kidsSubscription?.close();
    SyncService().stopConnectivityListener(); // 🚀 Stop Listener
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    // 🚀 1. Cache First (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        if (mounted) {
          setState(() {
            _myGroupId = cachedCtx['groupId']!;
            _currentUserRole = cachedCtx['role']!;
            _teamId = cachedCtx['teamId'];
          });
          _canWrite = await PermissionService.canWrite(_myGroupId);
          if (mounted) setState(() {});
          if (_myGroupId.isNotEmpty) {
            _fetchKidsPage();
            _subscribeToKidsUpdates();

            // 🚀 Start Sync now that we have groupId
            SyncService().syncAll(_myGroupId);
            SyncService().startConnectivityListener(_myGroupId);
          }
        }
      }
    } else {
      // Global fallback
      final lastData = await DataCacheService().getCachedUserData();
      if (lastData != null && lastData.containsKey('groupId')) {
        if (mounted) {
          setState(() {
            _myGroupId = lastData['groupId'];
            _currentUserRole = lastData['role'] ?? 'user';
          });
          _canWrite = await PermissionService.canWrite(_myGroupId);
          if (mounted) setState(() {});
          if (_myGroupId.isNotEmpty) {
            _fetchKidsPage();
            _subscribeToKidsUpdates();

            // 🚀 Start Sync now that we have groupId
            SyncService().syncAll(_myGroupId);
            SyncService().startConnectivityListener(_myGroupId);
          }
        }
      }
    }

    // 🚀 2. Background Refresh
    try {
      final user = await _account.get();
      await UserService().getCurrentUser(); // Cache ID

      final uDoc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'users_info',
        documentId: user.$id,
      );

      // Cache Update
      await DataCacheService().cacheUserGroupId(
        user.$id,
        uDoc.data['groupId'],
        uDoc.data['teamId'],
        uDoc.data['role'],
      );

      if (mounted) {
        setState(() {
          _myGroupId = uDoc.data['groupId'] ?? '';
          _currentUserRole = uDoc.data['role'] ?? 'user';
          _teamId = uDoc.data['teamId'];
        });
        _canWrite = await PermissionService.canWrite(_myGroupId);
        if (_myGroupId.isNotEmpty) {
          // 🚀 Start Sync (Network version)
          SyncService().syncAll(_myGroupId);
          SyncService().startConnectivityListener(_myGroupId);

          if (_liveKids.isEmpty) _fetchKidsPage();
        }
      }
    } catch (e) {
      debugPrint("Network fetch failed (offline): $e");
      if (mounted && _myGroupId.isEmpty) {
        setState(() {
          _currentUserRole = 'error';
          _isLoading = false;
        });
      }
    }
  }

  // Restored: _fetchKidsPage
  Future<void> _fetchKidsPage() async {
    if (!mounted) return;

    // 🚀 Load from cache IMMEDIATELY for Instant UI
    if (_liveKids.isEmpty) {
      final cached = await DataCacheService().getCachedKidsList(
        _myGroupId,
        widget.grade,
      );
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _liveKids = cached;
          _updateDerivedLists();
          DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
          _isLoading = false;
        });
      }
    }

    setState(() => _isLoading = _liveKids.isEmpty);

    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.equal('grade', widget.grade),
          Query.limit(1000),
          Query.orderDesc('\$createdAt'),
        ],
      );

      final List<Kid> fetchedKids = result.documents
          .map((doc) => Kid.fromAppwrite(doc))
          .toList();

      if (mounted) {
        setState(() {
          _liveKids = fetchedKids;
          _updateDerivedLists();
          DataCacheService().cacheKidsList(
            _myGroupId,
            widget.grade,
            _liveKids,
          ); // Restored method name
          _isLoading = false;
        });

        // 🚀 Cache for offline access using Grade-specific key
        DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
      }
    } catch (e) {
      debugPrint("Error fetching kids: $e");
      final cachedIds = await DataCacheService().getCachedKidsList(
        _myGroupId,
        widget.grade,
      );
      if (cachedIds.isNotEmpty && mounted) {
        setState(() {
          _liveKids = cachedIds;
          _updateDerivedLists();
          DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _error = "حدث خطأ في جلب البيانات: $e";
          _isLoading = false;
        });
      }
    }
  }

  // Restored Logic: _subscribeToKidsUpdates (Fetch-on-Update)
  void _subscribeToKidsUpdates() {
    final channel =
        'databases.$databaseId.collections.$studentsCollectionId.documents';

    _kidsSubscription = _realtime.subscribe([channel]);

    _kidsSubscription!.stream.listen((event) async {
      final payload = event.payload;
      if (payload['groupId'] != _myGroupId) return;

      final kidId = payload['\$id'];
      final events = event.events;

      if (events.any((e) => e.endsWith('.delete'))) {
        if (mounted) {
          setState(() {
            _liveKids.removeWhere((k) => k.id == kidId);
            _updateDerivedLists();
            DataCacheService().cacheKidsList(
              _myGroupId,
              widget.grade,
              _liveKids,
            );
          });
        }
        return;
      }

      try {
        // ⚡ OPTIMIZATION: Use payload directly instead of fetching
        // This makes updates (like visited status) instant on other devices
        final freshKid = Kid.fromMap(payload, kidId);

        // Ensure the payload has the grade, otherwise fallback to fetch
        if (freshKid.grade == null) {
          // Fallback if payload is partial (rare in Appwrite)
          final doc = await _databases.getDocument(
            databaseId: databaseId,
            collectionId: studentsCollectionId,
            documentId: kidId,
          );
          _processKidUpdate(Kid.fromAppwrite(doc), kidId);
        } else {
          _processKidUpdate(freshKid, kidId);
        }
      } catch (e) {
        debugPrint("Error processing realtime update: $e");
      }
    });
  }

  void _processKidUpdate(Kid freshKid, String kidId) {
    if (!mounted) return;

    final String kidGrade = _normalizeGradeText(freshKid.grade ?? '');
    final String currentGrade = _normalizeGradeText(widget.grade);

    setState(() {
      final index = _liveKids.indexWhere((k) => k.id == kidId);

      if (index != -1) {
        if (kidGrade != currentGrade) {
          _liveKids.removeAt(index);
        } else {
          // Preserve local image path if existing (optimistic UI)
          final existing = _liveKids[index];
          if (existing.localImagePath != null &&
              freshKid.localImagePath == null) {
            _liveKids[index] = freshKid.copyWithStatus(
              localImagePath: existing.localImagePath,
            );
          } else {
            _liveKids[index] = freshKid;
          }
        }
      } else {
        if (kidGrade == currentGrade) {
          _liveKids.insert(0, freshKid);
        }
      }
      _updateDerivedLists();
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
    });

    // Cache Update
    Future(() {
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
    });
  }

  String _normalizeGradeText(String text) {
    return text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .trim();
  }

  void _onSearchChanged(String val) {
    setState(() {
      searchText = val;
      _updateDerivedLists();
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
    });
  }

  // Restored: _updateDerivedLists
  void _updateDerivedLists() {
    _filteredAndSortedKids = _liveKids.where((k) {
      if (searchText.isEmpty) return true;
      return k.matchesQuery(searchText);
    }).toList();

    _filteredAndSortedKids.sort((a, b) {
      if (a.isVisited && !b.isVisited) return 1;
      if (!a.isVisited && b.isVisited) return -1;

      if (a.createdAt != null && b.createdAt != null) {
        return b.createdAt!.compareTo(a.createdAt!);
      }
      return a.name.compareTo(b.name);
    });

    _total = _liveKids.length;
    _visitedCount = _liveKids.where((k) => k.isVisited).length;
  }

  Future<void> _toggleVisited(Kid kid) async {
    if (!_canWrite) {
      _showSnackbar(
        "⚠️ انتهى الاشتراك. يرجى التجديد لتتمكن من تسجيل الافتقاد.",
      );
      return;
    }

    final currentUserName = await UserService().getCurrentUserName();
    final newIsVisited = !kid.isVisited;

    if (kid.isVisited &&
        !newIsVisited &&
        !_isAdmin &&
        kid.visitedBy != currentUserName) {
      _showSnackbar("⚠️ ليس لديك صلاحية لإلغاء حالة الافتقاد لهذا المخدوم.");
      return;
    }

    final index = _liveKids.indexWhere((k) => k.id == kid.id);
    if (index != -1) {
      setState(() {
        _liveKids[index] = _liveKids[index].copyWithStatus(
          isVisited: newIsVisited,
          visitedBy: newIsVisited ? currentUserName : '',
        );
        _updateDerivedLists();
        DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
      });
    }

    try {
      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        documentId: kid.id,
        data: {
          'isVisited': newIsVisited,
          'visitedBy': newIsVisited ? currentUserName : '',
        },
      );

      // Update again after success
      // (Already handled by _updateDerivedLists in setState)
    } catch (e) {
      debugPrint("Update error: $e. Saving to pending operations.");

      // 🚀 Save as pending operation
      await DataCacheService().addPendingOperation({
        'type': 'reminder_visit',
        'data': {
          'studentId': kid.id,
          'isVisited': newIsVisited,
          'visitedBy': currentUserName,
          'groupId': _myGroupId,
          'grade': widget.grade, // 🚀 Required for cache key consistency
        },
      });

      if (mounted) {
        // Optimistic UI state kept
      }

      // Keep the optimistic UI state, don't revert.
      // (Cache is updated via _updateDerivedLists in setState if index != -1)
    }
  }

  // --- DIALOGS (Preserved Image Logic) ---

  void _showAddKidDialog() async {
    if (!await PermissionService.canWrite(_myGroupId)) {
      _showSnackbar("⚠️ انتهت صلاحية الاشتراك");
      return;
    }

    if (!mounted) {
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneRequiredController = TextEditingController();
    final phoneOptionalController = TextEditingController();
    final locationController = TextEditingController();

    String? selectedRequiredOwner;
    String? selectedOptionalOwner;
    DateTime? selectedDateOfBirth;
    File? selectedImage;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("إضافة مخدوم جديد"),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final file = await _pickImage(context);
                          if (file != null) {
                            setDialogState(() => selectedImage = file);
                          }
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: selectedImage != null
                              ? FileImage(selectedImage!)
                              : null,
                          child: selectedImage == null
                              ? const Icon(
                                  Icons.add_a_photo,
                                  size: 30,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "الاسم"),
                        validator: (val) => val!.isEmpty ? "الاسم مطلوب" : null,
                      ),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: "العنوان"),
                        // validator: (val) => val!.isEmpty ? "العنوان مطلوب" : null, // Made optional
                      ),

                      _buildPhoneRow(
                        context,
                        "1",
                        phoneRequiredController,
                        selectedRequiredOwner,
                        (val) =>
                            setDialogState(() => selectedRequiredOwner = val),
                        isRequired: false, // Made optional
                      ),
                      _buildPhoneRow(
                        context,
                        "2",
                        phoneOptionalController,
                        selectedOptionalOwner,
                        (val) =>
                            setDialogState(() => selectedOptionalOwner = val),
                      ),

                      TextFormField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: "رابط الموقع (Google Maps)",
                        ),
                      ),

                      const SizedBox(height: 10),
                      _buildDatePicker(
                        context,
                        selectedDateOfBirth,
                        (date) =>
                            setDialogState(() => selectedDateOfBirth = date),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context); // Close first
                      await _addKid(
                        name: nameController.text.trim(),
                        address: addressController.text.trim(),
                        phoneRequired: phoneRequiredController.text.trim(),
                        phoneOptional: phoneOptionalController.text.trim(),
                        phoneRequiredOwner: selectedRequiredOwner,
                        phoneOptionalOwner: selectedOptionalOwner,
                        dateOfBirth: selectedDateOfBirth,
                        locationUrl: locationController.text.trim(),
                        imageFile: selectedImage, // Changed from _selectedImage
                      );
                    }
                  },
                  child: const Text("إضافة"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addKid({
    required String name,
    String? address, // Made optional
    String? phoneRequired, // Made optional
    String? phoneOptional,
    String? phoneRequiredOwner,
    String? phoneOptionalOwner,
    DateTime? dateOfBirth,
    String? locationUrl,
    File? imageFile,
  }) async {
    // Optimistic Add
    final docId = ID.unique(); // 🚀 Consistent ID
    final tempKid = Kid(
      id: docId,
      name: name,
      address: address ?? '',
      phoneRequired: phoneRequired,
      phoneOptional: phoneOptional,
      phoneRequiredOwner: phoneRequiredOwner,
      phoneOptionalOwner: phoneOptionalOwner,
      dateOfBirth: dateOfBirth,
      locationUrl: locationUrl,
      localImagePath: imageFile?.path,
      grade: widget.grade,
    );

    setState(() {
      _liveKids.insert(0, tempKid);
      _updateDerivedLists();
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
    });

    try {
      String? photoUrl;
      if (imageFile != null) {
        final result = await ImageService().uploadImage(imageFile);
        if (result != null) {
          photoUrl = result['url'];
        }
      }

      List<String> phones = [];
      if (phoneRequired != null && phoneRequired.isNotEmpty) {
        phones.add(phoneRequired);
      }
      if (phoneOptional != null && phoneOptional.isNotEmpty) {
        phones.add(phoneOptional);
      }

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        documentId: docId, // 🚀 Use same ID
        data: {
          'groupId': _myGroupId,
          'name': name,
          'address': address ?? '',
          'phoneRequired': phoneRequired,
          'phoneOptional': phoneOptional,
          'phones': phones,
          'phoneRequiredOwner': phoneRequiredOwner,
          'phoneOptionalOwner': phoneOptionalOwner,
          'grade': widget.grade,
          'locationUrl': locationUrl,
          'photoUrl': photoUrl,
          'dateOfBirth': dateOfBirth?.toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
          'isVisited': false,
          'visitedBy': '',
        },
        permissions: (_teamId != null && _teamId!.isNotEmpty)
            ? [
                Permission.read(Role.team(_teamId!)),
                Permission.update(Role.team(_teamId!)),
                Permission.delete(Role.team(_teamId!)),
              ]
            : null,
      );

      // 🚀 Instant Cache Update (PERSISTENCE)
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);

      if (mounted) {
        _showSnackbar("✅ تم إضافة المخدوم بنجاح");
      }
    } catch (e) {
      debugPrint("Add error: $e. Saving to pending operations.");

      // 🚀 Save as pending operation
      DataCacheService().addPendingOperation({
        'type': 'add_student',
        'data': {
          'groupId': _myGroupId,
          'name': name,
          'address': address ?? '',
          'phoneRequired': phoneRequired,
          'phoneOptional': phoneOptional,
          'phones': [
            if (phoneRequired != null && phoneRequired.isNotEmpty)
              phoneRequired,
            if (phoneOptional != null && phoneOptional.isNotEmpty)
              phoneOptional,
          ],
          'phoneRequiredOwner': phoneRequiredOwner,
          'phoneOptionalOwner': phoneOptionalOwner,
          'grade': widget.grade,
          'locationUrl': locationUrl,
          'localImagePath': imageFile?.path,
          'dateOfBirth': dateOfBirth?.toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
          'isVisited': false,
          'visitedBy': '',
          'teamId': _teamId,
        },
      });

      // Ensure cache is updated with the temp kid
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
    }
  }

  void _showEditKidDialog(Kid kid) async {
    if (!await PermissionService.canWrite(_myGroupId)) {
      _showSnackbar("⚠️ انتهت صلاحية الاشتراك");
      return;
    }

    if (!mounted) {
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: kid.name);
    final addressController = TextEditingController(text: kid.address);
    final phoneRequiredController = TextEditingController(
      text: kid.phoneRequired,
    );
    final phoneOptionalController = TextEditingController(
      text: kid.phoneOptional ?? '',
    );
    final locationController = TextEditingController(
      text: kid.locationUrl ?? '',
    );

    String? selectedRequiredOwner = kid.phoneRequiredOwner;
    if (selectedRequiredOwner != null &&
        !_phoneOwners.contains(selectedRequiredOwner)) {
      selectedRequiredOwner = null;
    }

    String? selectedOptionalOwner = kid.phoneOptionalOwner;
    if (selectedOptionalOwner != null &&
        !_phoneOwners.contains(selectedOptionalOwner)) {
      selectedOptionalOwner = null;
    }

    DateTime? selectedDateOfBirth = kid.dateOfBirth;
    File? selectedImage;
    bool isDeletePhoto = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("تعديل بيانات المخدوم"),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final file = await _pickImage(context);
                          if (file != null) {
                            setDialogState(() {
                              selectedImage =
                                  file; // Changed from _selectedImage
                              isDeletePhoto =
                                  false; // Changed from _isDeletePhoto
                            });
                          }
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: selectedImage != null
                              ? FileImage(selectedImage!)
                              : (kid.photoUrl != null &&
                                            kid.photoUrl!.isNotEmpty &&
                                            !isDeletePhoto // Changed from _isDeletePhoto
                                        ? CachedNetworkImageProvider(
                                            kid.photoUrl!,
                                            cacheManager:
                                                ImageCacheService.instance,
                                          )
                                        : null)
                                    as ImageProvider?,
                          child:
                              (selectedImage ==
                                      null && // Changed from _selectedImage
                                  (kid.photoUrl == null ||
                                      kid.photoUrl!.isEmpty ||
                                      isDeletePhoto)) // Changed from _isDeletePhoto
                              ? const Icon(
                                  Icons.face,
                                  size: 40,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                      ),
                      if (kid.photoUrl != null &&
                          !isDeletePhoto) // Changed from _isDeletePhoto
                        TextButton.icon(
                          label: const Text(
                            "حذف الصورة",
                            style: TextStyle(color: Colors.red),
                          ),
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 16,
                          ),
                          onPressed: () => setDialogState(
                            () => isDeletePhoto = true,
                          ), // Changed from _isDeletePhoto
                        ),

                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "الاسم"),
                        validator: (v) => v!.isEmpty ? "مطلوب" : null,
                      ),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: "العنوان"),
                        // validator: (v) => v!.isEmpty ? "مطلوب" : null, // Made Optional
                      ),

                      _buildPhoneRow(
                        context,
                        "1",
                        phoneRequiredController,
                        selectedRequiredOwner,
                        (val) =>
                            setDialogState(() => selectedRequiredOwner = val),
                        isRequired: false, // Made Optional
                      ),
                      _buildPhoneRow(
                        context,
                        "2",
                        phoneOptionalController,
                        selectedOptionalOwner,
                        (val) =>
                            setDialogState(() => selectedOptionalOwner = val),
                      ),

                      TextFormField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: "رابط الموقع",
                        ),
                      ),
                      _buildDatePicker(
                        context,
                        selectedDateOfBirth,
                        (d) => setDialogState(() => selectedDateOfBirth = d),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      await _editKid(
                        kid: kid,
                        name: nameController.text.trim(),
                        address: addressController.text.trim(),
                        phoneRequired: phoneRequiredController.text.trim(),
                        phoneOptional: phoneOptionalController.text.trim(),
                        phoneRequiredOwner: selectedRequiredOwner,
                        phoneOptionalOwner: selectedOptionalOwner,
                        dateOfBirth: selectedDateOfBirth,
                        locationUrl: locationController.text.trim(),
                        imageFile: selectedImage,
                        isDeletePhoto: isDeletePhoto,
                      );
                    }
                  },
                  child: const Text("حفظ"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editKid({
    required Kid kid,
    required String name,
    String? address, // Made Optional
    String? phoneRequired, // Made Optional
    String? phoneOptional,
    String? phoneRequiredOwner,
    String? phoneOptionalOwner,
    DateTime? dateOfBirth,
    String? locationUrl,
    File? imageFile,
    bool isDeletePhoto = false,
  }) async {
    // Optimistic
    final index = _liveKids.indexWhere((k) => k.id == kid.id);
    if (index != -1) {
      final updated = kid.copyWithStatus(
        name: name,
        address: address ?? '',
        phoneRequired: phoneRequired ?? '',
        phoneOptional: phoneOptional,
        phoneRequiredOwner: phoneRequiredOwner,
        phoneOptionalOwner: phoneOptionalOwner,
        dateOfBirth: dateOfBirth,
        locationUrl: locationUrl,
        localImagePath: imageFile?.path,
        photoUrl: isDeletePhoto ? null : kid.photoUrl,
      );
      setState(() {
        _liveKids[index] = updated;
        _updateDerivedLists();
        DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
      });
    }

    try {
      String? newPhotoUrl = kid.photoUrl;

      if (isDeletePhoto && kid.photoUrl != null && kid.photoUrl!.isNotEmpty) {
        await ImageService().deleteImageByUrl(kid.photoUrl);
        newPhotoUrl = null;
      } else if (imageFile != null) {
        if (kid.photoUrl != null && kid.photoUrl!.isNotEmpty) {
          await ImageService().deleteImageByUrl(kid.photoUrl);
        }
        final result = await ImageService().uploadImage(imageFile);
        if (result != null) newPhotoUrl = result['url'];
      }

      await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        documentId: kid.id,
        data: {
          'name': name,
          'address': address ?? '',
          'phoneRequired': phoneRequired,
          'phoneOptional': phoneOptional,
          'phones': [
            if (phoneRequired != null && phoneRequired.isNotEmpty)
              phoneRequired,
            if (phoneOptional != null && phoneOptional.isNotEmpty)
              phoneOptional,
          ],
          'phoneRequiredOwner': phoneRequiredOwner,
          'phoneOptionalOwner': phoneOptionalOwner,
          'dateOfBirth': dateOfBirth?.toIso8601String(),
          'locationUrl': locationUrl,
          'photoUrl': newPhotoUrl,
        },
      );

      // 🚀 Instant Cache Update (PERSISTENCE)
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);

      _showSnackbar("✅ تم التعديل بنجاح");
    } catch (e) {
      debugPrint("Edit error: $e. Saving to pending operations.");

      // 🚀 Save as pending operation
      DataCacheService().addPendingOperation({
        'type': 'edit_student',
        'data': {
          'studentId': kid.id,
          'name': name,
          'address': address ?? '',
          'phoneRequired': phoneRequired,
          'phoneOptional': phoneOptional,
          'phones': [
            if (phoneRequired != null && phoneRequired.isNotEmpty)
              phoneRequired,
            if (phoneOptional != null && phoneOptional.isNotEmpty)
              phoneOptional,
          ],
          'phoneRequiredOwner': phoneRequiredOwner,
          'phoneOptionalOwner': phoneOptionalOwner,
          'dateOfBirth': dateOfBirth?.toIso8601String(),
          'locationUrl': locationUrl,
          'photoUrl': kid.photoUrl, // Keep existing if failed to upload
          'localImagePath': imageFile?.path,
          'teamId': _teamId, // 🚀 Required for sync permissions
        },
      });

      // Ensure cache is updated with the updated kid
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
      _showSnackbar("ℹ️ تم حفظ التعديلات محلياً.");
    }
  }

  Future<void> _deleteKid(String kidId) async {
    if (!_canWrite) {
      _showSnackbar("⚠️ انتهت صلاحية الاشتراك. المجلد للقراءة فقط.");
      return;
    }
    // ⚡ Optimistic Delete
    final index = _liveKids.indexWhere((k) => k.id == kidId);
    if (index == -1) return;

    final deletedKid = _liveKids[index];
    setState(() {
      _liveKids.removeAt(index);
      _updateDerivedLists();
      DataCacheService().cacheKidsList(_myGroupId, widget.grade, _liveKids);
    });

    try {
      // Delete Image if exists
      if (deletedKid.photoUrl != null && deletedKid.photoUrl!.isNotEmpty) {
        try {
          await ImageService().deleteImageByUrl(deletedKid.photoUrl);
        } catch (_) {}
      }

      // Delete Document
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: studentsCollectionId,
        documentId: kidId,
      );

      // (Already handled by _updateDerivedLists in setState)
      _showSnackbar("🗑️ تم حذف المخدوم بنجاح");
    } catch (e) {
      debugPrint("Delete error: $e. Saving to pending operations.");

      // 🚀 Save as pending operation
      DataCacheService().addPendingOperation({
        'type': 'delete_student',
        'data': {
          'studentId': kidId,
          'teamId':
              _teamId, // 🚀 Required for sync permissions if delete logic needs it
        },
      });

      // (Already handled by _updateDerivedLists in setState)
    }
  }

  // --- HELPERS ---

  Widget _buildPhoneRow(
    BuildContext context,
    String labelSuffix,
    TextEditingController controller,
    String? selectedOwner,
    Function(String?) onChanged, {
    bool isRequired = false,
  }) {
    // Ensure value is valid
    if (selectedOwner != null && !_phoneOwners.contains(selectedOwner)) {
      selectedOwner = null;
    }
    return Row(
      children: [
        Expanded(
          flex: 3, // Allocation for Owner
          child: DropdownButtonFormField<String>(
            isExpanded: true, // Prevents internal overflow
            decoration: InputDecoration(
              labelText: "مالك $labelSuffix",
              labelStyle: const TextStyle(fontSize: 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            initialValue: selectedOwner,
            items: _phoneOwners
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
            validator: (v) => isRequired && v == null ? "مطلوب" : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5, // Allocation for Phone Number
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: isRequired ? "موبايل (اجباري)" : "موبايل (اختياري)",
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) => isRequired && v!.isEmpty ? "مطلوب" : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    BuildContext context,
    DateTime? selected,
    Function(DateTime) onSelect,
  ) {
    return Row(
      children: [
        const Text("تاريخ الميلاد: "),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: selected ?? DateTime(2015),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              initialDatePickerMode: DatePickerMode.year,
            );
            if (d != null) onSelect(d);
          },
          child: Text(
            selected == null
                ? "تعيين"
                : DateFormat('yyyy-MM-dd').format(selected),
          ),
        ),
      ],
    );
  }

  Future<File?> _pickImage(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        CroppedFile? croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'تعديل الصورة',
              toolbarColor: Colors.deepOrange,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: false,
            ),
            IOSUiSettings(title: 'تعديل الصورة'),
          ],
        );
        if (croppedFile != null) {
          return File(croppedFile.path);
        }
      }
    } catch (e) {
      debugPrint("Image picker error: $e");
    }
    return null;
  }

  void _showSnackbar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _openMap(String? url, String address) async {
    if (url != null && url.trim().isNotEmpty) {
      final uri = Uri.parse(
        url.trim().startsWith('http') ? url.trim() : 'https://${url.trim()}',
      );
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        debugPrint("Could not launch URL: $e");
      }
    }

    if (address.isNotEmpty) {
      final query = Uri.encodeComponent(address);
      final googleMapsUrl = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=$query",
      );
      try {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } catch (e) {
        _showSnackbar("تعذر فتح الخريطة: $e");
      }
    } else {
      _showSnackbar("لا يوجد عنوان مسجل");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserRole == 'loading') {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_currentUserRole == 'error') {
      return Scaffold(
        appBar: AppBar(title: const Text("خطأ")),
        body: const Center(child: Text("يرجى اعادة التشغيل")),
      );
    }
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text("المخدومين - ${widget.grade}")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Safety check for empty list vs error
    if (_error.isNotEmpty && _liveKids.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text("المخدومين - ${widget.grade}")),
        body: Center(child: Text("خطأ: $_error")),
      );
    }

    final double percentage = _total == 0 ? 0 : (_visitedCount / _total) * 100;

    return Scaffold(
      appBar: AppBar(title: Text("المخدومين - ${widget.grade}")),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildProgressBar(percentage),
                  const SizedBox(height: 10),
                  Text(
                    "تم افتقاد $_visitedCount من أصل $_total (${percentage.toStringAsFixed(1)}%)",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "بحث اسم المخدوم...",
                      fillColor: Colors.white,
                      filled: true,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchKidsPage, // Use restored logic
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _filteredAndSortedKids.length,
                  itemBuilder: (context, index) {
                    final kid = _filteredAndSortedKids[index];
                    final card = _buildKidCard(kid);

                    if (_isAdmin) {
                      return Dismissible(
                        key: Key(kid.id),
                        direction: _canWrite
                            ? DismissDirection.startToEnd
                            : DismissDirection.none,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          if (!_canWrite) {
                            _showSnackbar("⚠️ انتهت صلاحية الاشتراك");
                            return false;
                          }
                          return await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("تأكيد الحذف"),
                              content: Text("هل أنت متأكد من حذف ${kid.name}؟"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("إلغاء"),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("حذف"),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) => _deleteKid(kid.id),
                        child: card,
                      );
                    }
                    return card;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: (_isAdmin && _canWrite)
          ? FloatingActionButton(
              onPressed: _showAddKidDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildProgressBar(double percentage) {
    return Container(
      height: 20,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: percentage / 100,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Center(
            child: Text(
              "${percentage.toStringAsFixed(1)}%",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKidCard(Kid kid) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: kid.isVisited ? Colors.green.shade50 : Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: GestureDetector(
          onTap: () {
            if (kid.photoUrl != null || kid.localImagePath != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImage(
                    imageUrl: kid.photoUrl,
                    localPath: kid.localImagePath,
                    tag: 'k_${kid.id}',
                  ),
                ),
              );
            }
          },
          child: Hero(
            tag: 'k_${kid.id}',
            child: CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey.shade200,
              backgroundImage:
                  (kid.localImagePath != null && kid.localImagePath!.isNotEmpty)
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
                          kid.localImagePath!.isEmpty))
                  ? const Icon(Icons.face, color: Colors.grey, size: 30)
                  : null,
            ),
          ),
        ),
        title: Text(
          kid.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openMap(kid.locationUrl, kid.address),
              child: Text(
                "📍 ${kid.address}",
                style: TextStyle(
                  color: kid.locationUrl != null ? Colors.blue : Colors.black,
                  decoration: TextDecoration.none, // Removed underline
                ),
              ),
            ),
            if (kid.phones.isNotEmpty)
              Wrap(
                spacing: 5,
                children: kid.phones
                    .map(
                      (p) => GestureDetector(
                        onTap: () => launchUrl(Uri.parse("tel:$p")),
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: p));
                          _showSnackbar("تم النسخ");
                        },
                        child: Chip(
                          label: Text(
                            kid.getPhoneWithOwner(p),
                            style: const TextStyle(fontSize: 11),
                          ),
                          avatar: const Icon(Icons.phone, size: 14),
                          backgroundColor: Colors.blue.shade50,
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            Text(
              kid.isVisited ? "✅ افتقده ${kid.visitedBy}" : "❌ لم يفتقد",
              style: TextStyle(
                color: kid.isVisited ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            kid.isVisited ? Icons.check_circle : Icons.radio_button_unchecked,
            color: kid.isVisited ? Colors.green : Colors.grey,
          ),
          onPressed: () => _toggleVisited(kid),
        ),
        onLongPress: (_isAdmin && _canWrite)
            ? () => _showEditKidDialog(kid)
            : null,
      ),
    );
  }
}
