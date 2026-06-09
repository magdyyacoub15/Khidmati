// removed dart:io
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../services/curriculum_service.dart';
import '../widgets/premium_background.dart';
import 'media_player_page.dart';

class CurriculumsPage extends StatefulWidget {
  final String? folderId;
  final String? folderName;

  const CurriculumsPage({super.key, this.folderId, this.folderName});

  @override
  State<CurriculumsPage> createState() => _CurriculumsPageState();
}

class _CurriculumsPageState extends State<CurriculumsPage> {
  final CurriculumService _curriculumService = CurriculumService();
  bool _isLoading = true;
  List<DriveFile> _items = [];
  final Map<String, bool> _downloadStatus = {}; // true if downloaded

  @override
  void initState() {
    super.initState();
    _loadContents();
    // Only run the deep background sync if we are at the root folder
    if (widget.folderId == null) {
      _curriculumService.syncAllBackground().then((_) {
        // Refresh UI quietly if mounted
        if (mounted) _loadContents();
      });
    }
  }

  Future<void> _loadContents() async {
    setState(() => _isLoading = true);
    try {
      final currentFolderId = widget.folderId ?? CurriculumService.rootFolderId;
      final items = await _curriculumService.fetchFolderContents(currentFolderId);
      
      // Check download status for files
      for (var item in items) {
        if (!item.isFolder) {
          _downloadStatus[item.id] = await _curriculumService.isDownloaded(item);
        }
      }

      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ [CurriculumsPage] Error loading contents: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل الملفات! يرجى التحقق من الإنترنت.')),
        );
      }
    }
  }

  Future<void> _handleFileTap(DriveFile file) async {
    if (file.isFolder) {
      // Navigate to subfolder
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CurriculumsPage(
            folderId: file.id,
            folderName: file.name,
          ),
        ),
      );
      return;
    }

    // Handle PDF file
    bool isDownloaded = _downloadStatus[file.id] ?? false;

    if (isDownloaded) {
      // Open immediately
      final path = await _curriculumService.getLocalFilePath(file);
      await _openDownloadedFile(file, path);
    } else {
      // Download then open
      _showDownloadDialog(file);
    }
  }

  Future<void> _openDownloadedFile(DriveFile file, String path) async {
    if (file.isVideo || file.isAudio) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaPlayerPage(
            file: file,
            localPath: path,
          ),
        ),
      );
    } else {
      await OpenFilex.open(path);
    }
  }

  Future<void> _showDownloadDialog(DriveFile file) async {
    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'جاري التحميل...',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                file.name,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
              SizedBox(height: 20),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, value, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '${(value * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    try {
      final path = await _curriculumService.downloadFile(file, (progress) {
        progressNotifier.value = progress;
      });

      // Close dialog
      if (mounted) Navigator.pop(context);

      setState(() {
        _downloadStatus[file.id] = true;
      });

      // Open file
      await _openDownloadedFile(file, path);
    } catch (e) {
      // Close dialog
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل الملف. يرجى المحاولة لاحقاً.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.folderName ?? 'المناهج والكرازة',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
        leading: widget.folderId != null
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadContents,
          )
        ],
      ),
      body: PremiumBackground(
        child: SafeArea(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'هذا المجلد فارغ!',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final isFolder = item.isFolder;
                          final isDownloaded = _downloadStatus[item.id] ?? false;

                          Color getAvatarColor(DriveFile f) {
                            if (f.isFolder) return Colors.amber[100]!;
                            if (f.isPdf || f.isWord) return Colors.red[100]!;
                            if (f.isAudio) return Colors.blue[100]!;
                            if (f.isVideo) return Colors.purple[100]!;
                            if (f.isImage) return Colors.green[100]!;
                            return Colors.grey[200]!;
                          }

                          Color getIconColor(DriveFile f) {
                            if (f.isFolder) return Colors.amber[800]!;
                            if (f.isPdf || f.isWord) return Colors.red[700]!;
                            if (f.isAudio) return Colors.blue[700]!;
                            if (f.isVideo) return Colors.purple[700]!;
                            if (f.isImage) return Colors.green[700]!;
                            return Colors.grey[700]!;
                          }

                          IconData getIcon(DriveFile f) {
                            if (f.isFolder) return Icons.folder;
                            if (f.isPdf) return Icons.picture_as_pdf;
                            if (f.isWord) return Icons.description;
                            if (f.isAudio) return Icons.audiotrack;
                            if (f.isVideo) return Icons.video_library;
                            if (f.isImage) return Icons.image;
                            return Icons.insert_drive_file;
                          }

                          return Container(
                            margin: EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: getAvatarColor(item),
                                radius: 24,
                                child: Icon(
                                  getIcon(item),
                                  color: getIconColor(item),
                                  size: 28,
                                ),
                              ),
                              title: Text(
                                item.name.replaceAll(RegExp(r'\.(pdf|doc|docx|mp3|m4a|wav|mp4|mkv|avi|png|jpg|jpeg)$', caseSensitive: false), ''),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: !isFolder
                                  ? Text(
                                      isDownloaded ? 'متاح بدون إنترنت' : 'اضغط للتحميل',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: isDownloaded ? Colors.green[700] : Colors.grey[600],
                                      ),
                                    )
                                  : null,
                              trailing: isFolder
                                  ? Icon(Icons.chevron_right, color: Colors.grey)
                                  : (isDownloaded
                                      ? Icon(Icons.check_circle, color: Colors.green)
                                      : Icon(Icons.download_rounded, color: Colors.blueAccent)),
                              onTap: () => _handleFileTap(item),
                            ),
                          );
                        },
                      ),
        ),
      ),
    );
  }
}
