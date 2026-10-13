/// Full-window viewer: the file at whatever size the window allows.
///
/// The workspace preview was a ~700x300 pane, which is too small to judge an
/// upscale — the whole point of the before/after divider is seeing detail. This
/// takes the entire window instead, and the green button takes the display.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/media_file.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/media_stage.dart';

/// Opens the viewer on [file]. Does nothing if the file is not in the queue.
Future<void> openCompareView(
  BuildContext context,
  AppController controller,
  MediaFile file,
) {
  final index = controller.files.indexWhere((f) => f.path == file.path);
  if (index < 0) return Future.value();

  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) =>
          CompareView(controller: controller, initialIndex: index),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class CompareView extends StatefulWidget {
  const CompareView({
    super.key,
    required this.controller,
    required this.initialIndex,
  });

  final AppController controller;
  final int initialIndex;

  @override
  State<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<CompareView> {
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// A finishing job swaps a file's "after" in under us, and clearing the
  /// selection removes it entirely.
  void _onControllerChanged() {
    if (!mounted) return;
    final count = widget.controller.files.length;
    if (count == 0) {
      Navigator.of(context).maybePop();
      // Rebuild regardless: if the pop cannot happen — the viewer is the root
      // route, say — the empty build must still take over rather than leaving
      // a file on screen that is no longer in the queue.
      setState(() {});
      return;
    }
    setState(() => _index = _index.clamp(0, count - 1));
  }

  void _step(int delta) {
    final count = widget.controller.files.length;
    if (count < 2) return;
    // Wraps, so holding the arrow key sweeps the whole batch.
    setState(() => _index = (_index + delta + count) % count);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.files.isEmpty) return const SizedBox.shrink();

    final file = controller.files[_index];
    final result = controller.resultFor(_index);
    final comparing = canCompare(file, result);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: LabColors.background,
          body: Column(
            children: [
              _ViewerBar(
                file: file,
                position: '${_index + 1}/${controller.files.length}',
                comparing: comparing,
                canStep: controller.files.length > 1,
                onPrevious: () => _step(-1),
                onNext: () => _step(1),
                onClose: () => Navigator.of(context).maybePop(),
                onReveal: result != null && result.isSuccess
                    ? () => controller.revealInFileManager(result.outputPath)
                    : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(LabSpacing.cardRadius),
                    child: MediaStage(
                      // Keyed on the file so switching entries rebuilds the
                      // stage rather than leaving the previous player attached.
                      key: ValueKey(file.path),
                      file: file,
                      result: result,
                      thumbnailer: controller.thumbnailer,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewerBar extends StatelessWidget {
  const _ViewerBar({
    required this.file,
    required this.position,
    required this.comparing,
    required this.canStep,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
    required this.onReveal,
  });

  final MediaFile file;
  final String position;
  final bool comparing;
  final bool canStep;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back, size: 19),
            color: LabColors.textSecondary,
            tooltip: s.back,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LabColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comparing ? s.dragToCompare : s.notProcessedYet,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: LabColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onReveal != null)
            TextButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.folder_open_outlined, size: 15),
              label: Text(
                Platform.isWindows ? s.revealInExplorer : s.revealInFinder,
              ),
              style: TextButton.styleFrom(
                foregroundColor: LabColors.textSecondary,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          if (canStep) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left, size: 21),
              color: LabColors.textSecondary,
              tooltip: s.previous,
            ),
            Text(
              position,
              style: const TextStyle(
                fontSize: 12,
                color: LabColors.textMuted,
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right, size: 21),
              color: LabColors.textSecondary,
              tooltip: s.next,
            ),
          ],
        ],
      ),
    );
  }
}
