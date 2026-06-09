import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriveFile {
  final String id;
  final String name;
  final String modifiedTime;
  final String mimeType;

  DriveFile({
    required this.id,
    required this.name,
    required this.modifiedTime,
    required this.mimeType,
  });

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  bool get isPdf => name.toLowerCase().endsWith('.pdf');
  bool get isWord => name.toLowerCase().endsWith('.doc') || name.toLowerCase().endsWith('.docx');
  bool get isAudio => name.toLowerCase().endsWith('.mp3') || name.toLowerCase().endsWith('.wav') || name.toLowerCase().endsWith('.m4a');
  bool get isVideo => name.toLowerCase().endsWith('.mp4') || name.toLowerCase().endsWith('.mkv') || name.toLowerCase().endsWith('.avi');
  bool get isImage => name.toLowerCase().endsWith('.png') || name.toLowerCase().endsWith('.jpg') || name.toLowerCase().endsWith('.jpeg');

  bool get isAllowedFile {
    if (isFolder) return true;
    return isPdf || isWord || isAudio || isVideo || isImage;
  }

  factory DriveFile.fromJson(Map<String, dynamic> json) {
    return DriveFile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      modifiedTime: json['modifiedTime'] ?? '',
      mimeType: json['mimeType'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'modifiedTime': modifiedTime,
        'mimeType': mimeType,
      };
}

class CurriculumService {
  static const String rootFolderId = '1EpaOE1hTnZ-tTPBeYzIlMAUdYLDUVPSu';
  static const String _apiKey = 'AIzaSyDKqYWDp2lOwargDgqzTxc-Yh351SKieH4';
  static const String _metadataKey = 'curriculum_metadata';

  // Fetch the contents of a specific folder
  Future<List<DriveFile>> fetchFolderContents(String folderId) async {
    debugPrint("🚀 [CurriculumService] Fetching from Google Drive API for folder: $folderId");
    final url = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q='$folderId'+in+parents&orderBy=folder,name&fields=files(id,name,modifiedTime,mimeType)&key=$_apiKey");

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List files = data['files'];
      
      List<DriveFile> driveFiles = files.map((f) => DriveFile.fromJson(f))
          .where((file) => file.isAllowedFile)
          .toList();
      return driveFiles;
    } else {
      debugPrint("❌ [CurriculumService] Error from Google Drive API: ${response.body}");
      throw Exception("Failed to fetch files from Google Drive: ${response.body}");
    }
  }

  // Read local metadata
  Future<Map<String, DriveFile>> _getLocalMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final String? metadataStr = prefs.getString(_metadataKey);
    if (metadataStr == null) return {};

    final Map<String, dynamic> decoded = json.decode(metadataStr);
    final Map<String, DriveFile> result = {};
    decoded.forEach((key, value) {
      result[key] = DriveFile.fromJson(value);
    });
    return result;
  }

  // Save local metadata
  Future<void> _saveLocalMetadata(Map<String, DriveFile> metadata) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> encoded = {};
    metadata.forEach((key, value) {
      encoded[key] = value.toJson();
    });
    await prefs.setString(_metadataKey, json.encode(encoded));
  }

  // Get local directory for saving curriculums
  Future<String> _getLocalPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final curriculumDir = Directory('${dir.path}/curriculums');
    if (!await curriculumDir.exists()) {
      await curriculumDir.create(recursive: true);
    }
    return curriculumDir.path;
  }

  // Check if a file is already downloaded and up-to-date
  Future<bool> isDownloaded(DriveFile driveFile) async {
    final metadata = await _getLocalMetadata();
    final localFile = metadata[driveFile.id];
    
    if (localFile != null && localFile.modifiedTime == driveFile.modifiedTime) {
      final localPath = await _getLocalPath();
      final file = File('$localPath/${driveFile.name}');
      return await file.exists();
    }
    return false;
  }

  // Get local file path for a downloaded file
  Future<String> getLocalFilePath(DriveFile driveFile) async {
    final localPath = await _getLocalPath();
    return '$localPath/${driveFile.name}';
  }

  // Download a file from Google Drive on-demand
  Future<String> downloadFile(DriveFile file, Function(double) onProgress) async {
    debugPrint("🚀 [CurriculumService] Downloading file: ${file.name}");
    final url = Uri.parse("https://www.googleapis.com/drive/v3/files/${file.id}?alt=media&key=$_apiKey");
    
    final request = http.Request('GET', url);
    final response = await http.Client().send(request);

    if (response.statusCode == 200) {
      final localPath = await _getLocalPath();
      final localFile = File('$localPath/${file.name}');
      final sink = localFile.openWrite();
      
      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(downloadedBytes / totalBytes);
        }
      });
      
      await sink.close();

      // Update metadata to remember it's downloaded
      final metadata = await _getLocalMetadata();
      metadata[file.id] = file;
      await _saveLocalMetadata(metadata);
      
      debugPrint("🚀 [CurriculumService] Download completed: ${file.name}");
      return localFile.path;
    } else {
      throw Exception("Failed to download file: ${file.name}");
    }
  }

  // --- Background Sync ---
  Future<void> syncAllBackground() async {
    try {
      debugPrint("🚀 [CurriculumService] Starting background sync...");
      final driveFiles = await _fetchAllDriveFilesRecursively();
      final localMetadata = await _getLocalMetadata();
      final localPath = await _getLocalPath();

      // Find files to download or update
      List<DriveFile> filesToDownload = [];
      for (var file in driveFiles) {
        final localFile = localMetadata[file.id];
        if (localFile == null || localFile.modifiedTime != file.modifiedTime) {
          filesToDownload.add(file);
        }
      }

      for (var file in filesToDownload) {
        debugPrint("🚀 [CurriculumService] Background downloading: ${file.name}");
        await _downloadFileSilent(file, localPath);
        localMetadata[file.id] = file;
        await _saveLocalMetadata(localMetadata);
      }

      // Check for removed files
      final driveFileIds = driveFiles.map((f) => f.id).toSet();
      final keysToRemove = <String>[];
      
      for (var localFile in localMetadata.values) {
        if (!driveFileIds.contains(localFile.id)) {
          // File was deleted from Google Drive
          final fileToDelete = File('$localPath/${localFile.name}');
          if (await fileToDelete.exists()) {
            await fileToDelete.delete();
            debugPrint("🚀 [CurriculumService] Background deleted: ${localFile.name}");
          }
          keysToRemove.add(localFile.id);
        }
      }

      for (var key in keysToRemove) {
        localMetadata.remove(key);
      }
      
      if (keysToRemove.isNotEmpty) {
        await _saveLocalMetadata(localMetadata);
      }
      
      debugPrint("🚀 [CurriculumService] Background sync completed.");
    } catch (e) {
      debugPrint("❌ [CurriculumService] Background sync failed: $e");
    }
  }

  Future<List<DriveFile>> _fetchAllDriveFilesRecursively([String folderId = rootFolderId]) async {
    final url = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q='$folderId'+in+parents&fields=files(id,name,modifiedTime,mimeType)&key=$_apiKey");

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List files = data['files'];
      
      List<DriveFile> allFiles = [];
      
      for (var f in files) {
        if (f['mimeType'] == 'application/vnd.google-apps.folder') {
          final subFiles = await _fetchAllDriveFilesRecursively(f['id']);
          allFiles.addAll(subFiles);
        } else {
          final driveFile = DriveFile.fromJson(f);
          if (driveFile.isAllowedFile) {
            allFiles.add(driveFile);
          }
        }
      }
      return allFiles;
    } else {
      throw Exception("Failed to fetch files recursively");
    }
  }

  Future<void> _downloadFileSilent(DriveFile file, String path) async {
    final url = Uri.parse("https://www.googleapis.com/drive/v3/files/${file.id}?alt=media&key=$_apiKey");
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final localFile = File('$path/${file.name}');
      await localFile.writeAsBytes(response.bodyBytes);
    }
  }
}
