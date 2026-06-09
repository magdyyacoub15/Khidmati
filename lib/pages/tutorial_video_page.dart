import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/language_service.dart';
import '../l10n/app_translations.dart';

class TutorialVideoPage extends StatefulWidget {
  const TutorialVideoPage({super.key});

  @override
  State<TutorialVideoPage> createState() => _TutorialVideoPageState();
}

class _TutorialVideoPageState extends State<TutorialVideoPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String _errorMessage = '';

  final String _videoUrl =
      "https://drive.google.com/uc?export=download&id=1MM3AaOVSnlaw6mIy-HjJCZTMsd8jBeYB";
  final String _videoFileName = "tutorial_video_v2.mp4";

  @override
  void initState() {
    super.initState();
    // Prevent screen from sleeping
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      if (kIsWeb) {
        debugPrint("Running on Web: Redirecting to fallback UI...");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'web_video_fallback';
          });
        }
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_videoFileName');

      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > 1000000) {
          debugPrint("Playing cached tutorial video.");
          await _setupPlayer(file: file);
          return;
        } else {
          await file.delete();
        }
      }

      debugPrint("Streaming from network and caching...");
      await _setupPlayer(url: _videoUrl);
      _downloadVideoInBackground(file);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'video_load_error'
              .tr(context)
              .replaceFirst('%s', e.toString());
        });
      }
    }
  }

  Future<void> _setupPlayer({File? file, String? url}) async {
    if (file != null) {
      _videoPlayerController = VideoPlayerController.file(file);
    } else if (url != null) {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    } else {
      return;
    }

    try {
      await _videoPlayerController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: 9 / 20, // Make it even taller
        allowFullScreen: false,
        fullScreenByDefault: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.redAccent,
          handleColor: Colors.red,
          backgroundColor: Colors.grey.withValues(alpha: 0.5),
          bufferedColor: Colors.white54,
        ),
      );
    } catch (e) {
      debugPrint("Video initialization failed: $e");
      throw Exception("Failed to initialize video player: $e");
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadVideoInBackground(File file) async {
    try {
      final dio = Dio();
      await dio.download(
        _videoUrl,
        file.path,
        onReceiveProgress: (received, total) {},
      );

      if (await file.length() < 100000) {
        if (await file.exists()) await file.delete();
      } else {
        debugPrint("Video downloaded and cached successfully.");
      }
    } catch (e) {
      if (await file.exists()) await file.delete();
      debugPrint("Background download failed: $e");
    }
  }

  @override
  void dispose() {
    // Allow screen to sleep again
    WakelockPlus.disable();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(child: _buildBody()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage.isNotEmpty) {
      bool isWebFallback = _errorMessage == 'web_video_fallback';
      final bool isArabic = LanguageService().currentLocale.value == 'ar';

      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isWebFallback ? Icons.open_in_new : Icons.error_outline,
              color: isWebFallback ? Colors.blue : Colors.red,
              size: 60,
            ),
            const SizedBox(height: 15),
            Text(
              isWebFallback
                  ? (isArabic
                        ? 'لمشاهدة الفيديو التعليمي على متصفح الويب، يرجى الضغط على الزر أدناه لفتحه في نافذة جديدة.'
                        : 'To watch the tutorial video on the web, please click the button below to open it in a new window.')
                  : _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                if (isWebFallback) {
                  final Uri url = Uri.parse(
                    "https://drive.google.com/file/d/1MM3AaOVSnlaw6mIy-HjJCZTMsd8jBeYB/view",
                  );
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  setState(() => _errorMessage = '');
                  _initializeVideo();
                }
              },
              icon: Icon(
                isWebFallback ? Icons.play_circle_fill : Icons.refresh,
                size: 28,
              ),
              label: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Text(
                  isWebFallback
                      ? (isArabic ? 'مشاهدة الفيديو' : 'Watch Video')
                      : "retry".tr(context),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isWebFallback
                    ? Colors.blue
                    : Colors.grey.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const CircularProgressIndicator(color: Colors.blueAccent);
    }

    if (_chewieController != null &&
        _videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: 30.0,
          ), // Raise controls up slightly
          child: Theme(
            data: Theme.of(context).copyWith(
              iconTheme: const IconThemeData(
                color: Colors.white,
                size: 36.0, // Larger buttons
              ),
            ),
            child: Chewie(controller: _chewieController!),
          ),
        ),
      );
    }

    return const CircularProgressIndicator();
  }
}
