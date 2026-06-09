// 🚀 Required for Uint8List is in foundation.dart
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'appwrite_service.dart';

class ImageService {
  final Storage _storage = AppwriteService().storage;

  // ⚠️ يجب إنشاء Bucket في Appwrite وتسميته 'images' أو تغييره هنا
  static const String bucketId = 'images';

  /// Uploads an image to Appwrite Storage and returns its ID
  Future<Map<String, String>?> uploadImage(dynamic imageFile) async {
    try {
      InputFile fileInput;

      if (kIsWeb) {
        // Web: Use bytes
        if (imageFile is Uint8List) {
          fileInput = InputFile.fromBytes(
            bytes: imageFile,
            filename: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
        } else if (imageFile is XFile) {
          // 🚀 Robust check for XFile on web
          final bytes = await imageFile.readAsBytes();
          fileInput = InputFile.fromBytes(
            bytes: bytes,
            filename: imageFile.name,
          );
        } else {
          debugPrint(
            "⚠️ Web Upload: Unsupported type ${imageFile.runtimeType}",
          );
          throw Exception("Unsupported image type for Web upload");
        }
      } else {
        // Mobile: Use path
        String path = '';
        if (imageFile is File) {
          path = imageFile.path;
        } else if (imageFile is XFile) {
          path = imageFile.path;
        } else if (imageFile is String) {
          path = imageFile;
        } else {
          debugPrint(
            "⚠️ Mobile Upload: Unsupported type ${imageFile.runtimeType}",
          );
          throw Exception("Unsupported image type for Mobile upload");
        }
        fileInput = InputFile.fromPath(path: path);
      }

      final file = await _storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: fileInput,
      );

      final imageUrl =
          '${AppwriteService.endpoint}/storage/buckets/$bucketId/files/${file.$id}/view?project=${AppwriteService.projectId}';

      return {'url': imageUrl, 'id': file.$id};
    } catch (e) {
      debugPrint("❌ Appwrite Storage Upload Failed: $e");
      return null;
    }
  }

  /// Deletes an image from Appwrite Storage
  Future<bool> deleteImage(String fileId) async {
    try {
      await _storage.deleteFile(bucketId: bucketId, fileId: fileId);
      return true;
    } catch (e) {
      debugPrint("❌ Appwrite Storage Delete Failed: $e");
      return false;
    }
  }

  /// Helper to delete image using its full URL
  Future<bool> deleteImageByUrl(String? url) async {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      // Expected URL format: .../buckets/[bucketId]/files/[fileId]/view...
      // We look for the 'files' segment and take the next one as the ID.
      final filesIndex = segments.indexOf('files');
      if (filesIndex != -1 && filesIndex + 1 < segments.length) {
        final fileId = segments[filesIndex + 1];
        return await deleteImage(fileId);
      }
    } catch (e) {
      debugPrint("❌ Error parsing URL for deletion: $e");
    }
    return false;
  }
}
