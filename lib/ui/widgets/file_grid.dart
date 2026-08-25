/// The tile grid inside the file stage — every dropped file as a tile, each
/// carrying its own state while a batch runs.
///
/// The point of the grid is that during a batch you can see *which* file is
/// being worked on without reading the log — the active tile lifts out of the
/// dimmed queue and wears its own progress bar.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/media_file.dart';
import '../../state/app_controller.dart';
import '../compare_view.dart';
import '../theme.dart';

/// Tile width the grid aims for; the real width is whatever divides the
/// column evenly nearest to this.
const double _kTileExtent = 168;

class FileGrid extends StatelessWidget {
  const FileGrid({super.key, required this.controller, this.expand = false});

  final AppController controller;

  /// Fill the height handed down instead of shrink-wrapping. Only safe under a
  /// parent with a bounded height.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final files = controller.files;

    final grid = GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: !expand,
      physics: expand ? null : const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _kTileExtent,
        childAspectRatio: 0.82,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) => _FileTile(
        controller: controller,
        file: files[index],
        index: index,
      ),
    );

    // Scrollbar only where the grid owns a bounded height; when shrink-wrapped
    // the page around it is what scrolls.
    return expand ? Scrollbar(child: grid) : grid;
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.controller,
    required this.file,
    required this.index,
  });

  final AppController controller;
  final MediaFile file;
  final int index;

  @override
  Widget build(BuildContext context) {
    final status = controller.statusFor(index);
    final isPreviewing = controller.previewFile?.path == file.path;
    // Everything that is not the file being worked on recedes, so the active
    // tile is the one thing the eye lands on.
    final dimmed = controller.isRunning && status != FileStatus.running;

    return Tooltip(
      message: file.displayName,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: () {
          controller.selectForPreview(file);
          openCompareView(context, controller, file);
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: dimmed ? 0.45 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: LabColors.background,
              borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
              border: Border.all(
                color: isPreviewing ? LabColors.primary : LabColors.border,
                width: isPreviewing ? 1.6 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                LabSpacing.controlRadius - 1,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Poster(controller: controller, file: file),
                        if (file.isVideo) const _VideoMark(),
                        _StatusMark(status: status),
                        if (status == FileStatus.running)
                          _RunningOverlay(progress: controller.fileProgress),
                        if (!controller.isRunning &&
                            controller.phase != JobPhase.done)
                          _RemoveButton(
                            onPressed: () => controller.removeAt(index),
                          ),
                      ],
                    ),
                  ),
                  _Caption(file: file, status: status),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The poster frame, resolved off-thread by [Thumbnailer].
class _Poster extends StatelessWidget {
  const _Poster({required this.controller, required this.file});

  final AppController controller;
  final MediaFile file;

  @override
  Widget build(BuildContext context) {
    final thumbnailer = controller.thumbnailer;
    if (thumbnailer == null) return const _PosterFallback();

    return FutureBuilder<String?>(
      // Keyed on the path so switching selections cannot show the previous
      // file's poster while the new one resolves.
      key: ValueKey(file.path),
      future: thumbnailer.posterFor(file),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          );
        }
        final path = snapshot.data;
        if (path == null) return const _PosterFallback();
        return ColoredBox(
          color: Colors.black,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const _PosterFallback(),
          ),
        );
      },
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: LabColors.textFaint,
        ),
      ),
    );
  }
}

/// Progress bar sitting on the image itself — the thing that makes the active
/// file obvious at a glance.
class _RunningOverlay extends StatelessWidget {
  const _RunningOverlay({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final percent = progress == null ? null : (progress! * 100).round();

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (percent != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          // An indeterminate bar while the stage has no measurable progress
          // (frame extraction reports none), a real one once it does.
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: Colors.black.withValues(alpha: 0.5),
            valueColor: const AlwaysStoppedAnimation(LabColors.primaryBright),
          ),
        ],
      ),
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.status});

  final FileStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      FileStatus.done => (Icons.check_circle, LabColors.success),
      FileStatus.failed => (Icons.error, LabColors.danger),
      _ => (Icons.circle, Colors.transparent),
    };
    if (color == Colors.transparent) return const SizedBox.shrink();

    return Positioned(
      top: 6,
      left: 6,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
}

class _VideoMark extends StatelessWidget {
  const _VideoMark();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      bottom: 6,
      left: 6,
      child: Icon(Icons.play_circle_outline, size: 17, color: Colors.white70),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 13, color: Colors.white70),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.file, required this.status});

  final MediaFile file;
  final FileStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
      color: LabColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            file.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: LabColors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            switch (status) {
              FileStatus.done => 'selesai',
              FileStatus.failed => 'gagal',
              FileStatus.running => 'memproses…',
              FileStatus.queued => file.formattedSize,
            },
            style: TextStyle(
              fontSize: 10,
              color: switch (status) {
                FileStatus.done => LabColors.success,
                FileStatus.failed => LabColors.danger,
                FileStatus.running => LabColors.primaryBright,
                FileStatus.queued => LabColors.textFaint,
              },
            ),
          ),
        ],
      ),
    );
  }
}
