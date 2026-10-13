/// The file stage: one large area that is both the drop target and the
/// gallery of what was dropped.
///
/// Empty, it is the invitation to drop. Filled, the same rectangle becomes the
/// grid — so the place you drop files is the place you then watch them being
/// worked on, rather than a separate zone that goes stale the moment it has
/// done its job.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'file_grid.dart';

class FileStage extends StatefulWidget {
  const FileStage({super.key, required this.controller, this.expand = false});

  final AppController controller;

  /// Fill the height handed down instead of shrink-wrapping. Only safe under a
  /// parent with a bounded height.
  final bool expand;

  @override
  State<FileStage> createState() => _FileStageState();
}

class _FileStageState extends State<FileStage> {
  bool _dragging = false;

  static const _extensions = [
    'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv',
    'jpg', 'jpeg', 'png', 'webp', 'tiff', 'bmp',
  ];

  Future<void> _browseFiles() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: S.current.mediaTypeGroup, extensions: _extensions),
      ],
    );
    if (picked.isEmpty) return;
    widget.controller.addPaths(picked.map((f) => f.path));
  }

  Future<void> _browseFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    widget.controller.addPaths([dir]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final hasFiles = controller.hasFiles;
    final done = controller.results.where((r) => r.isSuccess).length;

    final body = hasFiles
        ? FileGrid(controller: controller, expand: widget.expand)
        : _DropInvitation(
            dragging: _dragging,
            onBrowseFiles: _browseFiles,
            onBrowseFolder: _browseFolder,
          );

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        controller.addPaths(detail.files.map((f) => f.path));
      },
      child: LabCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabCardTitle(
              badge: '1',
              title: S.of(context).filesTitle,
              trailing: hasFiles
                  ? _GridActions(
                      controller: controller,
                      done: done,
                      onBrowseFiles: _browseFiles,
                      onBrowseFolder: _browseFolder,
                    )
                  : null,
            ),
            // A drop anywhere on the card counts, so the whole filled area
            // gets the highlight, not just the empty-state rectangle.
            if (widget.expand)
              Expanded(child: _DragHalo(dragging: _dragging, child: body))
            else
              _DragHalo(dragging: _dragging, child: body),
          ],
        ),
      ),
    );
  }
}

/// Tints the stage while a drag hovers over it.
class _DragHalo extends StatelessWidget {
  const _DragHalo({required this.dragging, required this.child});

  final bool dragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: dragging
            ? LabColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
        border: Border.all(
          color: dragging ? LabColors.primary : Colors.transparent,
          width: 1.6,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: child,
    );
  }
}

class _GridActions extends StatelessWidget {
  const _GridActions({
    required this.controller,
    required this.done,
    required this.onBrowseFiles,
    required this.onBrowseFolder,
  });

  final AppController controller;
  final int done;
  final VoidCallback onBrowseFiles;
  final VoidCallback onBrowseFolder;

  @override
  Widget build(BuildContext context) {
    final count = controller.files.length;
    final s = S.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          controller.isRunning || controller.phase == JobPhase.done
              ? s.doneOf(done, count)
              : s.fileCount(count),
          style: const TextStyle(fontSize: 12, color: LabColors.textMuted),
        ),
        const SizedBox(width: 10),
        _MiniButton(
          icon: Icons.insert_drive_file_outlined,
          tooltip: s.addFiles,
          onPressed: controller.isRunning ? null : onBrowseFiles,
        ),
        _MiniButton(
          icon: Icons.folder_open_outlined,
          tooltip: s.addFolder,
          onPressed: controller.isRunning ? null : onBrowseFolder,
        ),
        _MiniButton(
          icon: Icons.close,
          tooltip: s.clearAll,
          onPressed: controller.isRunning ? null : controller.clearSelection,
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      color: LabColors.textMuted,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
    );
  }
}

class _DropInvitation extends StatelessWidget {
  const _DropInvitation({
    required this.dragging,
    required this.onBrowseFiles,
    required this.onBrowseFolder,
  });

  final bool dragging;
  final VoidCallback onBrowseFiles;
  final VoidCallback onBrowseFolder;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DottedPanel(
      active: dragging,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 40,
                color: dragging ? LabColors.primaryBright : LabColors.textFaint,
              ),
              const SizedBox(height: 14),
              Text(
                dragging ? s.dropHere : s.dropInvitation,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: LabColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  _OutlineButton(
                    icon: Icons.insert_drive_file_outlined,
                    label: s.pickFiles,
                    onPressed: onBrowseFiles,
                  ),
                  _OutlineButton(
                    icon: Icons.folder_open_outlined,
                    label: s.pickFolder,
                    onPressed: onBrowseFolder,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                s.supportedFormats,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: LabColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The outlined rectangle that reads as "put something here".
class DottedPanel extends StatelessWidget {
  const DottedPanel({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
        border: Border.all(
          color: active ? LabColors.primary : LabColors.borderStrong,
        ),
      ),
      child: child,
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: LabColors.primaryBright,
        side: BorderSide(color: LabColors.primary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
        ),
      ),
    );
  }
}

/// Extension used by the home page header badge.
extension MediaSelectionLabel on AppController {
  String selectionBadge(S s) {
    if (!hasFiles) return '';
    return isBulk
        ? '${s.bulkBadge} · ${s.fileCount(files.length)}'
        : s.singleBadge;
  }
}
