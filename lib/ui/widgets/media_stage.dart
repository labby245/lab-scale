/// The black rectangle a file is shown in — image, video, or a before/after
/// comparison once the file has been through the pipeline.
///
/// Kept separate from any card or page chrome so the workspace and the
/// full-window viewer can both show the same thing at different sizes.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/pipeline.dart';
import '../../core/thumbnailer.dart';
import '../../l10n/strings.dart';
import '../../models/media_file.dart';
import '../theme.dart';
import 'compare_slider.dart';

/// True when [result] gives us a second image to compare [file] against.
bool canCompare(MediaFile? file, JobResult? result) =>
    file != null &&
    result != null &&
    result.isSuccess &&
    File(result.outputPath).existsSync();

class MediaStage extends StatefulWidget {
  const MediaStage({
    super.key,
    required this.file,
    this.result,
    this.thumbnailer,
  });

  /// The file to show, or null when nothing is selected.
  final MediaFile? file;

  /// The finished job for [file], when there is one. Its output is the
  /// "after" side of the comparison.
  final JobResult? result;

  /// Needed only to still a video for comparison.
  final Thumbnailer? thumbnailer;

  @override
  State<MediaStage> createState() => _MediaStageState();
}

class _MediaStageState extends State<MediaStage> {
  Player? _player;
  VideoController? _videoController;
  String? _loadedPath;

  /// Video only: play the clip rather than compare two stills.
  bool _playing = false;

  bool get _canCompare => canCompare(widget.file, widget.result);

  /// Playback shows the result when there is one — that is the thing being
  /// judged — and the source otherwise.
  String? get _playbackPath {
    final file = widget.file;
    if (file == null || !file.isVideo) return null;
    return _canCompare ? widget.result!.outputPath : file.path;
  }

  bool get _showsPlayer {
    final file = widget.file;
    if (file == null || !file.isVideo) return false;
    return _playing || !_canCompare;
  }

  @override
  void didUpdateWidget(MediaStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new file starts in comparison mode rather than inheriting the previous
    // file's choice.
    if (oldWidget.file?.path != widget.file?.path) _playing = false;
    _syncPlayer();
  }

  @override
  void initState() {
    super.initState();
    _syncPlayer();
  }

  void _syncPlayer() {
    final wanted = _showsPlayer ? _playbackPath : null;

    if (wanted == null) {
      _disposePlayer();
      return;
    }
    if (_loadedPath == wanted) return;

    _disposePlayer();
    final player = Player();
    final controller = VideoController(player);
    player.open(Media(wanted), play: false);
    setState(() {
      _player = player;
      _videoController = controller;
      _loadedPath = wanted;
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
    final file = widget.file;
    final offersToggle = _canCompare && file != null && file.isVideo;

    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBody(),
          // Centred: the corners belong to the comparison's Original/Result
          // tags, and a corner toggle covered the "Result" one.
          if (offersToggle)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: _ModeToggle(
                playing: _playing,
                  onChanged: (value) {
                    setState(() => _playing = value);
                    _syncPlayer();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final file = widget.file;
    if (file == null) return const _EmptyStage();

    if (_canCompare && !_showsPlayer) {
      final after = widget.result!.outputPath;
      if (file.isImage) {
        return CompareSlider(beforePath: file.path, afterPath: after);
      }
      return _VideoCompare(
        thumbnailer: widget.thumbnailer,
        beforePath: file.path,
        afterPath: after,
      );
    }

    if (file.isImage) {
      return Image.file(
        File(file.path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _EmptyStage(
          message: S.of(context).cannotShowImage,
        ),
      );
    }

    final controller = _videoController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Video(
      controller: controller,
      controls: AdaptiveVideoControls,
      fill: Colors.black,
    );
  }
}

/// Comparing two clips means comparing one frame from each — the player cannot
/// show two videos at once, and a scrubbed pair would drift out of sync.
class _VideoCompare extends StatefulWidget {
  const _VideoCompare({
    required this.thumbnailer,
    required this.beforePath,
    required this.afterPath,
  });

  final Thumbnailer? thumbnailer;
  final String beforePath;
  final String afterPath;

  @override
  State<_VideoCompare> createState() => _VideoCompareState();
}

class _VideoCompareState extends State<_VideoCompare> {
  /// Held across rebuilds. Built inside build() it would be a *new* future
  /// every frame, so FutureBuilder would drop back to `waiting` each time —
  /// during a running batch the controller notifies on every log line, which
  /// left the comparison flashing a spinner and resetting the divider.
  Future<List<String?>>? _frames;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_VideoCompare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beforePath != widget.beforePath ||
        oldWidget.afterPath != widget.afterPath) {
      _start();
    }
  }

  void _start() {
    final maker = widget.thumbnailer;
    _frames = maker == null
        ? null
        : Future.wait([
            maker.posterForPath(widget.beforePath, isVideo: true),
            maker.posterForPath(widget.afterPath, isVideo: true),
          ]);
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    if (frames == null) {
      return _EmptyStage(message: S.of(context).previewUnavailable);
    }

    return FutureBuilder<List<String?>>(
      future: frames,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final frames = snapshot.data;
        if (frames == null || frames[0] == null || frames[1] == null) {
          return _EmptyStage(message: S.of(context).cannotGrabFrames);
        }
        return CompareSlider(
          beforePath: frames[0]!,
          afterPath: frames[1]!,
          beforeLabel: S.of(context).beforeFrame,
          afterLabel: S.of(context).afterFrame,
        );
      },
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.playing, required this.onChanged});

  final bool playing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            icon: Icons.compare_arrows,
            label: S.of(context).compare,
            selected: !playing,
            onPressed: () => onChanged(false),
          ),
          const SizedBox(width: 4),
          _ModeChip(
            icon: Icons.play_arrow,
            label: S.of(context).play,
            selected: playing,
            onPressed: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? LabColors.primary.withValues(alpha: 0.9)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : LabColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: selected ? Colors.white : LabColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({this.message});

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
            message ?? S.of(context).emptyPreview,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: LabColors.textFaint),
          ),
        ],
      ),
    );
  }
}
