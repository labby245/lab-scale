/// File selection: drag & drop target plus file/folder browse buttons.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../theme.dart';

class SourceCard extends StatefulWidget {
  const SourceCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<SourceCard> {
  bool _dragging = false;

  static const _typeGroup = XTypeGroup(
    label: 'Media',
    extensions: [
      'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv',
      'jpg', 'jpeg', 'png', 'webp', 'tiff', 'bmp',
    ],
  );

  Future<void> _browseFiles() async {
    final picked = await openFiles(acceptedTypeGroups: const [_typeGroup]);
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

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LabCardTitle(badge: '1', title: 'Pilih File'),
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) {
              setState(() => _dragging = false);
              controller.addPaths(detail.files.map((f) => f.path));
            },
            child: _DropZone(
              dragging: _dragging,
              onBrowseFiles: _browseFiles,
              onBrowseFolder: _browseFolder,
            ),
          ),
          if (controller.hasFiles) ...[
            const SizedBox(height: LabSpacing.gap),
            _SelectionSummary(controller: controller),
          ],
        ],
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.dragging,
    required this.onBrowseFiles,
    required this.onBrowseFolder,
  });

  final bool dragging;
  final VoidCallback onBrowseFiles;
  final VoidCallback onBrowseFolder;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: dragging
            ? LabColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
        border: Border.all(
          color: dragging ? LabColors.primary : LabColors.borderStrong,
          width: dragging ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.upload_file_outlined,
            size: 34,
            color: dragging ? LabColors.primaryBright : LabColors.textFaint,
          ),
          const SizedBox(height: 12),
          const Text(
            'Drag & drop file video / foto atau folder di sini',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: LabColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: [
              _OutlineButton(
                icon: Icons.insert_drive_file_outlined,
                label: 'Pilih File',
                onPressed: onBrowseFiles,
              ),
              _OutlineButton(
                icon: Icons.folder_open_outlined,
                label: 'Pilih Folder',
                onPressed: onBrowseFolder,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Video: MP4 · MOV · WEBM · MKV · AVI   |   Foto: JPG · PNG · WEBP · TIFF',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: LabColors.textFaint),
          ),
        ],
      ),
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

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final first = controller.firstFile!;
    final isBulk = controller.isBulk;

    final title = isBulk
        ? '${controller.files.length} file dipilih'
        : first.displayName;
    final subtitle = isBulk
        ? 'Referensi: ${first.displayName}'
        : first.formattedSize;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: LabColors.surfaceRaised,
        borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
        border: Border.all(color: LabColors.border),
      ),
      child: Row(
        children: [
          Icon(
            isBulk
                ? Icons.folder_copy_outlined
                : (first.isImage ? Icons.image_outlined : Icons.movie_outlined),
            size: 22,
            color: LabColors.primaryBright,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: LabColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: LabColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: controller.isRunning ? null : controller.clearSelection,
            icon: const Icon(Icons.close, size: 18),
            color: LabColors.textFaint,
            tooltip: 'Hapus pilihan',
          ),
        ],
      ),
    );
  }
}

/// Extension used by the home page header badge.
extension MediaSelectionLabel on AppController {
  String get selectionBadge {
    if (!hasFiles) return '';
    return isBulk ? 'Bulk · ${files.length} file' : 'Single File';
  }
}
