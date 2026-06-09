import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/image_cache_service.dart';

class FullScreenImageGallery extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> localPaths;
  final int initialIndex;
  final String tagPrefix;

  const FullScreenImageGallery({
    super.key,
    this.imageUrls = const [],
    this.localPaths = const [],
    this.initialIndex = 0,
    required this.tagPrefix,
  });

  @override
  State<FullScreenImageGallery> createState() => _FullScreenImageGalleryState();
}

class _FullScreenImageGalleryState extends State<FullScreenImageGallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _totalImages => widget.imageUrls.isNotEmpty
      ? widget.imageUrls.length
      : widget.localPaths.length;

  bool get _isLocal => widget.localPaths.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_totalImages == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Icon(Icons.face, color: Colors.grey, size: 100),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${_currentIndex + 1} / $_totalImages',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _totalImages,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final String pathOrUrl = _isLocal
              ? widget.localPaths[index]
              : widget.imageUrls[index];

          return Center(
            child: Hero(
              tag: '${widget.tagPrefix}_$index',
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4,
                child: _buildImage(pathOrUrl, _isLocal),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImage(String pathOrUrl, bool isLocal) {
    if (isLocal && !kIsWeb) {
      return Image.file(
        File(pathOrUrl),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.broken_image, color: Colors.white, size: 100);
        },
      );
    } else if (!isLocal) {
      return CachedNetworkImage(
        imageUrl: pathOrUrl,
        cacheManager: ImageCacheService.instance,
        fit: BoxFit.contain,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        errorWidget: (context, url, error) =>
            const Icon(Icons.broken_image, color: Colors.white, size: 100),
      );
    } else {
      return const Icon(Icons.broken_image, color: Colors.grey, size: 100);
    }
  }
}
