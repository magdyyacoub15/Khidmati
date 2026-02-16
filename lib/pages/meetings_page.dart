import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart' as printing;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/status_service.dart';
import '../services/user_service.dart';
import '../services/image_service.dart';
import '../services/permission_service.dart';
import '../services/appwrite_service.dart';
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service

// -------------------------------------------------------------------
// 🧱 MeetingFormPage
// -------------------------------------------------------------------

class MeetingFormPage extends StatefulWidget {
  final String servantName;
  final String groupId;
  final String? teamId;
  final VoidCallback onMeetingSaved;

  const MeetingFormPage({
    super.key,
    required this.servantName,
    required this.groupId,
    this.teamId,
    required this.onMeetingSaved,
  });

  @override
  State<MeetingFormPage> createState() => _MeetingFormPageState();
}

class _MeetingFormPageState extends State<MeetingFormPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();

  final List<File> _selectedImages = [];
  bool _isLoading = false;

  final ImageService _imageService = ImageService();
  final Databases _databases = AppwriteService().databases;

  static const String databaseId = AppwriteService.databaseId;
  static const String collectionId = 'meetings';

  Future<File> compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.jpg",
    );

    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 85,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );

    return result != null ? File(result.path) : file;
  }

  Future<void> _pickMultiImages() async {
    final picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(pickedFiles.map((xfile) => File(xfile.path)));
      });
    }
  }

  Future<void> _saveMeeting() async {
    if (!await PermissionService.canWrite(widget.groupId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ انتهت صلاحية الاشتراك")),
        );
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    List<String> imageLinks = [];
    List<String> fileIds = [];

    try {
      if (_selectedImages.isNotEmpty) {
        for (File imageFile in _selectedImages) {
          File compressedImage = await compressImage(imageFile);
          Map<String, String>? uploadResult = await _imageService.uploadImage(
            compressedImage,
          );

          if (uploadResult != null) {
            imageLinks.add(uploadResult['url']!);
            fileIds.add(uploadResult['id']!);
          } else {
            throw Exception("فشل رفع الصور");
          }
        }
      }

      await _databases.createDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: {
          'title': _titleController.text.trim(),
          'servantName': widget.servantName,
          'date': DateTime.now().toIso8601String(),
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
            caption: "اجتماع جديد: ${_titleController.text.trim()}",
            source: "الاجتماعات",
            teamId: widget.teamId,
            uploaderName: widget.servantName, // 🚀 Pass uploader name
          );
        }
      }

      if (mounted) {
        _titleController.clear();
        _selectedImages.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم حفظ الاجتماع بنجاح"),
            backgroundColor: Colors.green,
          ),
        );
        widget.onMeetingSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ حدث خطأ: $e"), backgroundColor: Colors.red),
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
          colors: [Color(0xFF81D4FA), Color(0xFF0288D1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: "عنوان الاجتماع",
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => v!.isEmpty ? "الرجاء كتابة العنوان" : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickMultiImages,
                icon: const Icon(Icons.photo_library),
                label: Text(
                  _selectedImages.isEmpty
                      ? "اختيار صور للاجتماع (اختياري)"
                      : "تم اختيار (${_selectedImages.length}) صور",
                ),
              ),

              if (_selectedImages.isNotEmpty)
                Container(
                  height: 120,
                  margin: const EdgeInsets.only(top: 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          Image.file(
                            _selectedImages[i],
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _selectedImages.removeAt(i)),
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
                    ),
                  ),
                ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveMeeting,
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
                  label: Text(_isLoading ? "جاري الحفظ..." : "حفظ الاجتماع"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0288D1),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------
// 🧱 MeetingsListPage
// -------------------------------------------------------------------

class MeetingsListPage extends StatefulWidget {
  const MeetingsListPage({super.key});

  @override
  State<MeetingsListPage> createState() => _MeetingsListPageState();
}

class _MeetingsListPageState extends State<MeetingsListPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editTitleController = TextEditingController();

  String _searchQuery = '';
  late TabController _tabController;
  String? _teamId;
  String _myGroupId = '';
  String _currentServantName = '';

  final Databases _databases = AppwriteService().databases;
  final Account _account = AppwriteService().account;
  final Realtime _realtime = Realtime(AppwriteService().client);
  RealtimeSubscription? _userSubscription;

  static const String databaseId = AppwriteService.databaseId;
  static const String collectionId = 'meetings';

  List<models.Document> _meetings = [];
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
    _editTitleController.dispose();
    _tabController.dispose();
    _userSubscription?.close();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _account.get();
      _userSubscription = _realtime.subscribe([
        'databases.$databaseId.collections.users_info.documents.${user.$id}',
      ]);
      _userSubscription!.stream.listen((event) {
        if (mounted) _fetchUserGroupId(user.$id);
      });
      await _fetchUserGroupId(user.$id);

      final name = await UserService().getCurrentUserName();
      if (mounted) setState(() => _currentServantName = name);
    } catch (e) {
      debugPrint("Error loading user: $e");
    }
  }

  Future<void> _fetchUserGroupId(String userId) async {
    // 1. Check Cache
    final cached = await DataCacheService().getCachedUserGroupId(userId);
    if (cached != null) {
      if (mounted) {
        setState(() {
          if (cached['groupId'] != _myGroupId) _myGroupId = cached['groupId']!;
          if (cached['teamId'] != null) _teamId = cached['teamId'];
          _isAdmin = (cached['role'] == 'admin');
        });
        if (_myGroupId.isNotEmpty) _fetchMeetings();
      }
    }

    try {
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: 'users_info',
        documentId: userId,
      );
      final gid = doc.data['groupId'] ?? '';
      final role = doc.data['role'] ?? '';

      // Update Cache
      await DataCacheService().cacheUserGroupId(
        userId,
        gid,
        doc.data['teamId'],
        role,
      );
      if (mounted) {
        setState(() {
          if (gid != _myGroupId) _myGroupId = gid;
          if (doc.data['teamId'] != null) {
            _teamId = doc.data['teamId'] as String;
          }
          _isAdmin = (role == 'admin');
        });
        _canWrite = await PermissionService.canWrite(gid);
        if (mounted) {
          setState(() {
            // Update TabController length if needed
            int newLength = _canWrite ? 2 : 1;
            if (_tabController.length != newLength) {
              _tabController.dispose();
              _tabController = TabController(length: newLength, vsync: this);
            }
          });
          if (gid.isNotEmpty) _fetchMeetings();
        }
      }
    } catch (e) {
      debugPrint("Error fetching gid: $e");
    }
  }

  Future<void> _fetchMeetings() async {
    if (_myGroupId.isEmpty) return;

    // 1. Load from cache
    final cachedList = await DataCacheService().getCachedMeetings(_myGroupId);
    if (cachedList.isNotEmpty) {
      if (mounted) {
        setState(() {
          _meetings = cachedList
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
      await DataCacheService().cacheMeetings(_myGroupId, dataToCache);

      if (mounted) {
        setState(() {
          _meetings = result.documents;
          _isLoadingList = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching meetings: $e");
      if (mounted && _meetings.isEmpty) setState(() => _isLoadingList = false);
    }
  }

  Future<void> _deleteMeeting(
    String docId,
    List<dynamic> fileIds,
    List<dynamic> imageUrls,
  ) async {
    if (!await PermissionService.canWrite(_myGroupId)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("⚠️ لا تملك صلاحية")));
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: const Text("هل أنت متأكد من حذف هذا الاجتماع؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final storage = AppwriteService().storage;
      for (var id in fileIds) {
        try {
          await storage.deleteFile(bucketId: 'images', fileId: id.toString());
        } catch (_) {}
      }

      // 🚀 Remove from Statuses
      final statusService = StatusService(groupId: _myGroupId);
      for (var url in imageUrls) {
        await statusService.deleteStatusByImageUrl(url.toString());
      }

      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: docId,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ تم الحذف")));
        _fetchMeetings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
      }
    }
  }

  Future<void> _editMeeting(models.Document doc) async {
    if (!mounted) return;
    _editTitleController.text = doc.data['title'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تعديل الاجتماع"),
        content: TextField(
          controller: _editTitleController,
          decoration: const InputDecoration(labelText: "عنوان الاجتماع"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _databases.updateDocument(
                  databaseId: databaseId,
                  collectionId: collectionId,
                  documentId: doc.$id,
                  data: {'title': _editTitleController.text.trim()},
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  _fetchMeetings();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("✅ تم التعديل")));
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("❌ خطأ: $e")));
                }
              }
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToPdf(
    String title,
    String servant,
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
        } catch (_) {}
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => [
            pw.Text(
              "📖 $title",
              style: pw.TextStyle(
                fontSize: 20,
                font: alfareesFont,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              "👤 الخادم: $servant",
              style: pw.TextStyle(font: alfareesFont),
            ),
            pw.Text(
              "📅 التاريخ: ${DateFormat('yMMMd', 'ar').format(date)}",
              style: pw.TextStyle(font: alfareesFont),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            if (imageWidgets.isNotEmpty)
              ...imageWidgets
            else
              pw.Text("(لا توجد صور)", style: pw.TextStyle(font: alfareesFont)),
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
    if (_currentServantName.isEmpty) return false;
    final diff = DateTime.now().difference(createdDate).inDays;
    return (authorName == _currentServantName || authorName == "خادم") &&
        diff <= 7;
  }

  @override
  Widget build(BuildContext context) {
    if (_myGroupId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(" الاجتماعات"),
        backgroundColor: const Color(0xFF0288D1),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: "بحث وعرض", icon: Icon(Icons.list)),
            if (_canWrite)
              const Tab(text: "إضافة اجتماع", icon: Icon(Icons.add)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: List
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "بحث...",
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
                        onRefresh: _fetchMeetings,
                        child: _meetings.isEmpty
                            ? const Center(
                                child: Text("لا توجد اجتماعات مضافة"),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: _meetings.length,
                                itemBuilder: (context, index) {
                                  final doc = _meetings[index];
                                  final data = doc.data;
                                  final title = data['title'] ?? 'بدون عنوان';
                                  final servant =
                                      data['servantName'] ?? 'غير معروف';
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
                                    child: ExpansionTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        child: const Icon(
                                          Icons.groups,
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
                                        "$servant • ${DateFormat('MM/dd').format(date)}",
                                      ),
                                      children: [
                                        if (images.isNotEmpty)
                                          SizedBox(
                                            height: 150,
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: images.length,
                                              itemBuilder: (ctx, i) => Padding(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: GestureDetector(
                                                  onTap: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => Scaffold(
                                                        backgroundColor:
                                                            Colors.black,
                                                        appBar: AppBar(
                                                          backgroundColor:
                                                              Colors.black,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
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
                                                                initialPage: i,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: CachedNetworkImage(
                                                      imageUrl: images[i]
                                                          .toString(),
                                                      width: 120,
                                                      fit: BoxFit.cover,
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
                                              ),
                                            ),
                                          ),
                                        OverflowBar(
                                          children: [
                                            TextButton.icon(
                                              icon: const Icon(
                                                Icons.picture_as_pdf,
                                                color: Colors.red,
                                              ),
                                              label: const Text("PDF"),
                                              onPressed: () => _exportToPdf(
                                                title,
                                                servant,
                                                date,
                                                images,
                                              ),
                                            ),
                                            if (_canEdit(servant, date)) ...[
                                              TextButton.icon(
                                                icon: const Icon(
                                                  Icons.edit,
                                                  color: Colors.orange,
                                                ),
                                                label: const Text("تعديل"),
                                                onPressed: () =>
                                                    _editMeeting(doc),
                                              ),
                                              TextButton.icon(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.grey,
                                                ),
                                                label: const Text("حذف"),
                                                onPressed: () => _deleteMeeting(
                                                  doc.$id,
                                                  fileIds,
                                                  images,
                                                ),
                                              ),
                                            ],
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
          if (_canWrite)
            MeetingFormPage(
              servantName: _currentServantName,
              groupId: _myGroupId,
              teamId: _teamId,
              onMeetingSaved: () {
                _tabController.animateTo(0);
                _fetchMeetings();
              },
            ),
        ],
      ),
    );
  }
}
