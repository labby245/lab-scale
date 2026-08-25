/// Preview of the selected media — video playback via media_kit, stills via
/// a plain image widget.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/media_file.dart';
import '../theme.dart';

class PreviewCard extends StatefulWidget {
  const PreviewCard({super.key, required this.file});

  /// The file to preview, or null when nothing is selected.
  final MediaFile? file;

  @override
  State<PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<PreviewCard> {
  Player? _player;
  VideoController? _videoController;
  String? _loadedPath;

  @override
  void didUpdateWidget(PreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayer();
  }

  @override
  void initState() {
    super.initState();
    _syncPlayer();
  }

  void _syncPlayer() {
    final file = widget.file;
    final wantsVideo = file != null && file.isVideo;

    if (!wantsVideo) {
      _disposePlayer();
      return;
    }
    if (_loadedPath == file.path) return;

    _disposePlayer();
    final player = Player();
    final controller = VideoController(player);
    player.open(Media(file.path), play: false);
    setState(() {
      _player = player;
      _videoController = controller;
      _loadedPath = file.path;
    });
  }

  void _disposePlayer() {
    final player = _player;
    if (player == null) return;
    _player = null;
    _videoController = null;
    _loadedPath = null;
    player.dispose();
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LabCardTitle(badge: '3', title: 'Preview'),
          ClipRRect(
            borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final file = widget.file;
    if (file == null) return const _EmptyPreview();

    if (file.isImage) {
      return Image.file(
        File(file.path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _EmptyPreview(
          message: 'Tidak dapat menampilkan gambar ini',
        ),
      );
    }

    final controller = _videoController;
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Video(
      controller: controller,
      controls: AdaptiveVideoControls,
      fill: Colors.black,
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_camera_back_outlined,
            size: 46,
            color: LabColors.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            message ?? 'Pilih file video atau foto untuk melihat preview',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: LabColors.textFaint),
          ),
        ],
      ),
    );
  }
}
