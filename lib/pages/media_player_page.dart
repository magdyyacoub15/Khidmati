import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../services/curriculum_service.dart';

class MediaPlayerPage extends StatefulWidget {
  final DriveFile file;
  final String localPath;

  const MediaPlayerPage({super.key, required this.file, required this.localPath});

  @override
  State<MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends State<MediaPlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.file(File(widget.localPath));
      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        allowFullScreen: widget.file.isVideo,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: widget.file.isAudio ? Colors.purpleAccent : Colors.blueAccent,
          handleColor: widget.file.isAudio ? Colors.purple : Colors.blue,
          backgroundColor: Colors.grey.shade800,
          bufferedColor: Colors.white30,
        ),
        // Aspect ratio is 1 for audio to force the controls to layout nicely if needed
        // but since we override height, it doesn't matter much.
        aspectRatio: widget.file.isAudio ? 1 : _videoPlayerController.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );

      setState(() {});
    } catch (e) {
      debugPrint("Error initializing player: $e");
      setState(() {
        _isError = true;
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAudio = widget.file.isAudio;
    final displayName = widget.file.name.replaceAll(RegExp(r'\.(mp3|m4a|wav|mp4|mkv|avi)$', caseSensitive: false), '');
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(displayName, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isError
            ? const Center(
                child: Text(
                  'حدث خطأ أثناء تشغيل الملف. قد يكون غير مدعوم.',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'Cairo'),
                ),
              )
            : _chewieController != null && _videoPlayerController.value.isInitialized
                ? Column(
                    children: [
                      if (isAudio)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.purple.shade900.withValues(alpha: 0.5), Colors.black],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(40),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.purple.withValues(alpha: 0.1),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.purple.withValues(alpha: 0.3),
                                          blurRadius: 50,
                                          spreadRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.music_note,
                                      size: 100,
                                      color: Colors.purpleAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 40),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo'
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (isAudio)
                        Container(
                          color: Colors.black,
                          height: 100, // Enough height for the progress bar and controls
                          child: Theme(
                            data: ThemeData.dark().copyWith(
                              platform: TargetPlatform.android, // Ensure material controls
                            ),
                            child: Chewie(controller: _chewieController!),
                          ),
                        )
                      else
                        Expanded(
                          child: Center(
                            child: Chewie(controller: _chewieController!),
                          ),
                        ),
                    ],
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.purpleAccent),
                  ),
      ),
    );
  }
}
