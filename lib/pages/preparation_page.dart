import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🚀 Added for kIsWeb
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart' as printing;
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/grade_service.dart';
import '../services/status_service.dart';
import '../services/user_service.dart';
import '../services/image_service.dart';
import '../services/permission_service.dart';
import '../services/appwrite_service.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service
import '../services/language_service.dart'; // ✅ Added Language Service
import '../services/sync_service.dart'; // 🚀 Added Sync Service
import '../l10n/app_translations.dart'; // ✅ Added Translation Support

// -------------------------------------------------------------------
// 🧱 PreparationForm
// -------------------------------------------------------------------

class PreparationForm extends StatefulWidget {
  final String servantName;
  final String groupId;
  final String? teamId;
  final VoidCallback onSaved;

  const PreparationForm({
    super.key,
    required this.servantName,
    required this.groupId,
    this.teamId,
    required this.onSaved,
  });

  @override
  State<PreparationForm> createState() => _PreparationFormState();
}

class _PreparationFormState extends State<PreparationForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();

  List<String> _grades = [];
  String? _selectedGrade;
  // 🚀 Modified for Web Support (Use XFile instead of File)
  final List<XFile> _selectedImages = [];
  bool _isLoading = false;

  final ImageService _imageService = ImageService();
  final Databases _databases = AppwriteService().databases;

  static const String databaseId = AppwriteService.databaseId;
  static const String collectionId = 'preparations';

  @override
  void initState() {
    super.initState();
    _fetchGrades();
  }

  Future<void> _fetchGrades() async {
    // 1. Try Cache
    try {
      final cachedGrades = await DataCacheService().getCachedGrades(
        widget.groupId,
      );
      if (cachedGrades.isNotEmpty) {
        if (mounted) {
          setState(() {
            _grades = cachedGrades;
            if (_selectedGrade == null && _grades.isNotEmpty) {
              _selectedGrade = _grades.first;
            }
          });
        }
      }
    } catch (_) {}

    // 2. Refresh
    try {
      final grades = await GradeService(groupId: widget.groupId).getGrades();
      await DataCacheService().cacheGrades(
        widget.groupId,
        grades,
      ); // Update Cache

      if (mounted) {
        setState(() {
          _grades = grades;
          if (_grades.isNotEmpty && _selectedGrade == null) {
            _selectedGrade = _grades.first;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching grades: $e");
    }
  }

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

    return result ?? file; // Return XFile/File (dynamic handles it in upload)
  }

  Future<void> _pickMultiImages() async {
    final picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(pickedFiles); // 🚀 Store XFiles directy
      });
    }
  }

  Future<void> _saveLesson() async {
    if (!_formKey.currentState!.validate()) return;

    final String imageUploadFailedMsg = 'image_upload_failed'.tr(context);
    final String newPreparationMsg = 'new_preparation'.tr(context);
    final String preparationSourceMsg = 'preparation_source'.tr(context);

    if (widget.groupId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('wait_for_data_load'.tr(context))));
      return;
    }

    final hasPermission = await PermissionService.canWrite(widget.groupId);
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('service_frozen'.tr(context)),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    final String titleStr = _titleController.text.trim();
    final String dateStr = DateTime.now().toIso8601String();

    final Map<String, dynamic> syncData = {
      'title': titleStr,
      'servantName': widget.servantName,
      'grade': _selectedGrade,
      'date': dateStr,
      'groupId': widget.groupId,
      'teamId': widget.teamId,
      'localImagePaths': _selectedImages.map((e) => e.path).toList(),
    };

    try {
      // 🚀 Offline Logic
      final bool online = await SyncService().isOnline();
      if (!online) {
        await DataCacheService().addPendingOperation({
          'type': 'preparation_add',
          'data': syncData,
        });

        // Optimistic UI Feedback
        if (mounted) {
          _titleController.clear();
          _selectedImages.clear();
          setState(
            () => _selectedGrade = _grades.isNotEmpty ? _grades.first : null,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('offline_congratulation_queued'.tr(context)),
              backgroundColor: Colors.blueGrey,
            ),
          );
          widget.onSaved();
        }
        return;
      }

      List<String> imageLinks = [];
      List<String> fileIds = [];
      if (_selectedImages.isNotEmpty) {
        for (XFile imageFile in _selectedImages) {
          // 🚀 Compress (returns XFile or File, dynamic is fine for uploadImage)
          final compressedImage = await compressImage(imageFile);

          Map<String, String>? uploadResult = await _imageService.uploadImage(
            compressedImage,
          );

          if (uploadResult != null) {
            imageLinks.add(uploadResult['url']!);
            fileIds.add(uploadResult['id']!);
          } else {
            throw Exception(imageUploadFailedMsg);
          }
        }
      }

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: {
          'title': titleStr,
          'servantName': widget.servantName,
          'grade': _selectedGrade,
          'date': dateStr,
          'imageUrls': imageLinks,
          'fileIds': fileIds,
          'groupId': widget.groupId,
        },
        permissions: (widget.teamId != null && widget.teamId!.isNotEmpty)
            ? [
                Permission.read(Role.team(widget.teamId!)),
                Permission.update(Role.team(widget.teamId!)),
                Permission.delete(Role.team(widget.teamId!)),
              ]
            : null,
      );

      if (imageLinks.isNotEmpty) {
        final statusService = StatusService(groupId: widget.groupId);
        for (String url in imageLinks) {
          await statusService.addStatus(
            imageUrl: url,
            caption: newPreparationMsg.replaceFirst('%s', titleStr),
            source: preparationSourceMsg,
            teamId: widget.teamId,
            uploaderName: widget.servantName, // 🚀 Pass uploader name
          );
        }
      }

      if (mounted) {
        _titleController.clear();
        _selectedImages.clear();
        setState(
          () => _selectedGrade = _grades.isNotEmpty ? _grades.first : null,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('lesson_saved_success'.tr(context)),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      debugPrint("❌ Error saving lesson: $e");
      // Network retry
      if (e is AppwriteException &&
          (e.type == 'network_error' ||
              e.message?.contains('Socket') == true)) {
        await DataCacheService().addPendingOperation({
          'type': 'preparation_add',
          'data': syncData,
        });
        if (mounted) {
          _titleController.clear();
          _selectedImages.clear();
          setState(
            () => _selectedGrade = _grades.isNotEmpty ? _grades.first : null,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('offline_congratulation_queued'.tr(context)),
              backgroundColor: Colors.blueGrey,
            ),
          );
          widget.onSaved();
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('lesson_saved_error'.tr(context)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFB3E5FC), Color(0xFF0288D1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedGrade),
                decoration: InputDecoration(
                  labelText: 'select_grade_prep'.tr(context),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                initialValue: _selectedGrade,
                items: _grades
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedGrade = v),
                validator: (v) =>
                    v == null ? 'please_select_grade_prep'.tr(context) : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'subject_title'.tr(context),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) =>
                    v!.isEmpty ? 'enter_subject_title'.tr(context) : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickMultiImages,
                icon: const Icon(Icons.photo_library),
                label: Text(
                  _selectedImages.isEmpty
                      ? 'choose_images_optional'.tr(context)
                      : 'images_selected'
                            .tr(context)
                            .replaceFirst(
                              '%s',
                              _selectedImages.length.toString(),
                            ),
                ),
              ),

              if (_selectedImages.isNotEmpty)
                Container(
                  height: 120,
                  margin: const EdgeInsets.only(top: 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Stack(
                          children: [
                            kIsWeb
                                ? Image.network(
                                    _selectedImages[index]
                                        .path, // On web XFile.path is a blob URL
                                    height: 120,
                                    width: 120,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(_selectedImages[index].path),
                                    height: 120,
                                    width: 120,
                                    fit: BoxFit.cover,
                                  ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: InkWell(
                                onTap: () => setState(
                                  () => _selectedImages.removeAt(index),
                                ),
                                child: const CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  radius: 12,
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveLesson,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isLoading
                        ? 'saving_action'.tr(context)
                        : 'save_subject_action'.tr(context),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------
// 🧱 PreparationListAndFormPage
// -------------------------------------------------------------------

class PreparationListAndFormPage extends StatefulWidget {
  const PreparationListAndFormPage({super.key});

  @override
  State<PreparationListAndFormPage> createState() =>
      _PreparationListAndFormPageState();
}

class _PreparationListAndFormPageState extends State<PreparationListAndFormPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;

  String _myGroupId = '';
  String? _teamId;
  String _currentServantName = '';

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Realtime _realtime = AppwriteService().realtime;
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String collectionId = 'preparations';

  List<models.Document> _preparations = [];
  bool _isLoadingList = true;
  bool _isAdmin = false;
  bool _canWrite = true;

  @override
  void initState() {
    super.initState();
    // Default 2 tabs, but we update it after _loadUserData
    _tabController = TabController(length: 2, vsync: this);
    _loadUserData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _userSubscription?.close();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    // 🚀 1. Try to load from cache IMMEDIATELY (Non-blocking)
    final cachedUserId = await UserService().getCachedUserId();
    if (cachedUserId != null) {
      final cachedCtx = await DataCacheService().getCachedUserGroupId(
        cachedUserId,
      );
      if (cachedCtx != null) {
        if (mounted) {
          setState(() {
            if (cachedCtx['groupId'] != _myGroupId) {
              _myGroupId = cachedCtx['groupId']!;
            }
            if (cachedCtx['teamId'] != null) {
              _teamId = cachedCtx['teamId'];
            }
            _isAdmin = (cachedCtx['role'] == 'admin');
          });
          _canWrite = await PermissionService.canWrite(_myGroupId);
          if (mounted) {
            setState(() {
              int newLength = _canWrite ? 2 : 1;
              if (_tabController.length != newLength) {
                _tabController.dispose();
                _tabController = TabController(length: newLength, vsync: this);
              }
            });
            if (_myGroupId.isNotEmpty) _fetchPreparations();
          }
        }
      }
    }

    // 🚀 2. Background Network Refresh (Silent)
    try {
      final name = await UserService().getCurrentUserName();
      if (mounted) setState(() => _currentServantName = name);

      final user = await _account.get();
      final userId = user.$id;

      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'users_info',
        documentId: userId,
      );

      final gid = doc.data['groupId'] ?? '';
      final role = doc.data['role'] ?? '';
      final currentTeamId = doc.data['teamId'] as String?;

      await DataCacheService().cacheUserGroupId(
        userId,
        gid,
        currentTeamId,
        role,
      );

      if (mounted) {
        setState(() {
          if (gid != _myGroupId) {
            _myGroupId = gid;
          }
          if (currentTeamId != null) {
            _teamId = currentTeamId;
          }
          _isAdmin = (role == 'admin');
        });

        _canWrite = await PermissionService.canWrite(_myGroupId);
        if (mounted) {
          setState(() {
            int newLength = _canWrite ? 2 : 1;
            if (_tabController.length != newLength) {
              _tabController.dispose();
              _tabController = TabController(length: newLength, vsync: this);
            }
          });
          if (_myGroupId.isNotEmpty) _fetchPreparations();
        }
      }

      _userSubscription?.close();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.users_info.documents.$userId',
      ]);

      _userSubscription!.stream.listen((event) {
        if (mounted) {
          final payloadGid = event.payload['groupId'] ?? '';
          final payloadRole = event.payload['role'] ?? '';
          final payloadTeamId = event.payload['teamId'] as String?;

          setState(() {
            if (payloadGid != _myGroupId) {
              _myGroupId = payloadGid;
            }
            if (payloadTeamId != null) {
              _teamId = payloadTeamId;
            }
            _isAdmin = (payloadRole == 'admin');
          });

          PermissionService.canWrite(_myGroupId).then((can) {
            if (mounted) {
              setState(() {
                _canWrite = can;
                int newLength = _canWrite ? 2 : 1;
                if (_tabController.length != newLength) {
                  _tabController.dispose();
                  _tabController = TabController(
                    length: newLength,
                    vsync: this,
                  );
                }
              });
              if (_myGroupId.isNotEmpty) _fetchPreparations();
            }
          });
        }
      });
    } catch (e) {
      debugPrint("Offline mode active or error loading user: $e");
    }
  }

  Future<void> _fetchPreparations() async {
    if (_myGroupId.isEmpty) return;

    // 1. Load from cache
    final cachedList = await DataCacheService().getCachedPreparations(
      _myGroupId,
    );
    if (cachedList.isNotEmpty) {
      if (mounted) {
        setState(() {
          _preparations = cachedList
              .map((d) => models.Document.fromMap(d))
              .toList();
          _isLoadingList = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingList = true);
    }

    try {
      final result = await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('groupId', _myGroupId),
          Query.orderDesc('date'),
          Query.limit(100),
        ],
      );

      // Update Cache
      final List<Map<String, dynamic>> dataToCache = result.documents
          .map((d) => d.toMap())
          .toList();
      await DataCacheService().cachePreparations(_myGroupId, dataToCache);

      if (mounted) {
        setState(() {
          _preparations = result.documents;
          _isLoadingList = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching preparations: $e");
      if (mounted && _preparations.isEmpty) {
        setState(() => _isLoadingList = false);
      }
    }
  }

  Future<void> _deletePreparation(
    String docId,
    List<dynamic> fileIds,
    List<dynamic> imageUrls,
  ) async {
    bool hasPermission = await PermissionService.canWrite(_myGroupId);
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('no_permission'.tr(context))));
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_confirmation_title'.tr(context)),
        content: Text('delete_preparation_warning'.tr(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel_btn'.tr(context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'delete_btn'.tr(context),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final syncData = {
      'docId': docId,
      'groupId': _myGroupId,
      'fileIds': fileIds,
      'imageUrls': imageUrls,
    };

    try {
      // 🚀 Offline Logic
      final bool online = await SyncService().isOnline();
      if (!online) {
        await DataCacheService().addPendingOperation({
          'type': 'preparation_delete',
          'data': syncData,
        });

        // Optimistic UI Update
        await DataCacheService().removePreparationFromCache(_myGroupId, docId);
        if (mounted) {
          setState(() {
            _preparations.removeWhere((doc) => doc.$id == docId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('deleted_success'.tr(context))),
          );
        }
        return;
      }

      // Delete Images
      final storage = AppwriteService().storage;
      for (var id in fileIds) {
        try {
          await storage.deleteFile(bucketId: 'images', fileId: id.toString());
        } catch (e) {
          debugPrint("Error deleting file $id: $e");
        }
      }

      // 🚀 Remove from Statuses
      final statusService = StatusService(groupId: _myGroupId);
      for (var url in imageUrls) {
        await statusService.deleteStatusByImageUrl(url.toString());
      }

      // Delete Doc
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: docId,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('deleted_success'.tr(context))));
        _fetchPreparations(); // Refresh list
      }
    } catch (e) {
      if (mounted) {
        // Appwrite error: Network?
        if (e is AppwriteException &&
            (e.type == 'network_error' ||
                e.message?.contains('Socket') == true)) {
          await DataCacheService().addPendingOperation({
            'type': 'preparation_delete', // Changed from meeting_delete
            'data': syncData,
          });
          if (!mounted) return; // Added mounted check
          await DataCacheService().removePreparationFromCache(
            // Changed from removeMeetingFromCache
            _myGroupId,
            docId,
          );
          if (!mounted) return;
          setState(() {
            _preparations.removeWhere(
              (doc) => doc.$id == docId,
            ); // Changed from _meetings
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('deleted_success'.tr(context))),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'delete_failed'
                  .tr(context)
                  .replaceFirst(
                    '%s',
                    e.toString(),
                  ), // Changed from error_occurred
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportToPdf(
    BuildContext context,
    String title,
    String servant,
    String grade,
    DateTime date,
    List<dynamic> imageUrls,
  ) async {
    try {
      final pdf = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/Alfares.ttf');
      final alfareesFont = pw.Font.ttf(fontData);

      final List<pw.Widget> imageWidgets = [];
      for (final url in imageUrls) {
        try {
          final image = await printing.networkImage(url.toString());
          imageWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain, height: 300),
              ),
            ),
          );
        } catch (e) {
          // ignore error
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => [
            pw.Text(
              'title_format'.tr(context).replaceFirst('%s', title),
              style: pw.TextStyle(
                fontSize: 20,
                font: alfareesFont,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'servant_format'.tr(context).replaceFirst('%s', servant),
              style: pw.TextStyle(font: alfareesFont),
            ),
            pw.Text(
              'grade_format'.tr(context).replaceFirst('%s', grade),
              style: pw.TextStyle(font: alfareesFont),
            ),
            pw.Text(
              'date_format'
                  .tr(context)
                  .replaceFirst(
                    '%s',
                    DateFormat(
                      'yMMMd',
                      LanguageService().currentLocale.value,
                    ).format(date),
                  ),

              style: pw.TextStyle(font: alfareesFont),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            if (imageWidgets.isNotEmpty)
              ...imageWidgets
            else
              pw.Text(
                'no_images'.tr(context),
                style: pw.TextStyle(font: alfareesFont),
              ),
          ],
        ),
      );

      await printing.Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      debugPrint("Error PDF: $e");
    }
  }

  bool _canEdit(String authorName, DateTime createdDate) {
    if (_myGroupId.isEmpty) return false;
    if (_isAdmin) return true;
    final diff = DateTime.now().difference(createdDate).inDays;
    return (authorName == _currentServantName ||
            authorName == 'servant_relation'.tr(context)) &&
        diff <= 7;
  }

  Map<String, dynamic> _getActualData(models.Document doc) {
    final rawDataField = doc.data['data'];
    if (rawDataField is Map<String, dynamic>) {
      return rawDataField;
    }
    return doc.data;
  }

  @override
  Widget build(BuildContext context) {
    if (_myGroupId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('preparation_and_curricula'.tr(context)),
        backgroundColor: const Color(0xFF0288D1),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              text: 'lessons_archive'.tr(context),
              icon: const Icon(Icons.history),
            ),
            if (_canWrite)
              Tab(
                text: 'prepare_new_lesson'.tr(context),
                icon: const Icon(Icons.edit_note),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Search & List
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'search_subject_title'.tr(context),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingList
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _fetchPreparations,
                        child: _preparations.isEmpty
                            ? Center(
                                child: Text(
                                  'no_subjects_added_list'.tr(context),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: _preparations.length,
                                itemBuilder: (context, index) {
                                  final doc = _preparations[index];
                                  final data = _getActualData(doc);
                                  final title =
                                      data['title'] ?? 'untitled'.tr(context);
                                  final servant =
                                      data['servantName'] ??
                                      'unknown_prep'.tr(context);
                                  final grade = data['grade'] ?? '';
                                  final dateStr = data['date'];
                                  DateTime date = DateTime.now();
                                  if (dateStr != null) {
                                    date = DateTime.parse(dateStr);
                                  }

                                  final images =
                                      data['imageUrls'] as List<dynamic>? ?? [];
                                  final fileIds =
                                      data['fileIds'] as List<dynamic>? ?? [];

                                  if (_searchQuery.isNotEmpty &&
                                      !title.toLowerCase().contains(
                                        _searchQuery,
                                      )) {
                                    return const SizedBox.shrink();
                                  }

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ExpansionTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        child: const Icon(
                                          Icons.menu_book,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      title: Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        "$servant • $grade • ${DateFormat('MM/dd', LanguageService().currentLocale.value).format(date)}",
                                      ),
                                      children: [
                                        if (images.isNotEmpty)
                                          SizedBox(
                                            height: 150,
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              itemCount: images.length,
                                              itemBuilder: (ctx, i) {
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 8,
                                                      ),
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) => Scaffold(
                                                            appBar: AppBar(
                                                              backgroundColor:
                                                                  Colors.black,
                                                              foregroundColor:
                                                                  Colors.white,
                                                            ),
                                                            backgroundColor:
                                                                Colors.black,
                                                            body: PhotoViewGallery.builder(
                                                              itemCount:
                                                                  images.length,
                                                              builder: (context, index) {
                                                                return PhotoViewGalleryPageOptions(
                                                                  imageProvider:
                                                                      NetworkImage(
                                                                        images[index]
                                                                            .toString(),
                                                                      ),
                                                                  initialScale:
                                                                      PhotoViewComputedScale
                                                                          .contained,
                                                                  minScale:
                                                                      PhotoViewComputedScale
                                                                          .contained *
                                                                      0.8,
                                                                  maxScale:
                                                                      PhotoViewComputedScale
                                                                          .covered *
                                                                      2,
                                                                );
                                                              },
                                                              scrollPhysics:
                                                                  const BouncingScrollPhysics(),
                                                              backgroundDecoration:
                                                                  const BoxDecoration(
                                                                    color: Colors
                                                                        .black,
                                                                  ),
                                                              pageController:
                                                                  PageController(
                                                                    initialPage:
                                                                        i,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: CachedNetworkImage(
                                                        imageUrl: images[i]
                                                            .toString(),
                                                        fit: BoxFit.cover,
                                                        width: 120,
                                                        placeholder:
                                                            (
                                                              context,
                                                              url,
                                                            ) => const Center(
                                                              child:
                                                                  CircularProgressIndicator(),
                                                            ),
                                                        errorWidget:
                                                            (
                                                              context,
                                                              url,
                                                              error,
                                                            ) => const Icon(
                                                              Icons.error,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        OverflowBar(
                                          children: [
                                            TextButton.icon(
                                              icon: const Icon(
                                                Icons.picture_as_pdf,
                                                color: Colors.red,
                                              ),
                                              label: Text(
                                                "pdf_label".tr(context),
                                              ),

                                              onPressed: () => _exportToPdf(
                                                context,
                                                title,
                                                servant,
                                                grade,
                                                date,
                                                images,
                                              ),
                                            ),
                                            if (_canEdit(servant, date))
                                              TextButton.icon(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.grey,
                                                ),
                                                label: Text(
                                                  'delete_btn'.tr(context),
                                                ),
                                                onPressed: () =>
                                                    _deletePreparation(
                                                      doc.$id,
                                                      fileIds,
                                                      images,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
          // 2. Add New Lesson Form
          if (_canWrite)
            PreparationForm(
              servantName: _currentServantName,
              groupId: _myGroupId,
              teamId: _teamId,
              onSaved: () {
                _tabController.animateTo(0);
                _fetchPreparations();
              },
            ),
        ],
      ),
    );
  }
}
