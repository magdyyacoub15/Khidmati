import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageCacheService {
  static const key = 'customImageCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30), // 🗓️ Keep images for 30 days
      maxNrOfCacheObjects: 500, // 📦 Store up to 500 images
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}
