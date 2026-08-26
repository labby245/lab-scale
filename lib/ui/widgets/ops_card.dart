/// Operation toggles: upscale (model, scale, sharpness) and 60 FPS boost,
/// plus the global quality and codec selectors.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;

import '../../models/process_options.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class OpsCard extends StatelessWidget {
  const OpsCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.options;

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LabCardTitle(badge: '2', title: 'Operasi'),

          _OpToggle(
            icon: Icons.zoom_out_map,
            name: 'Upscale',
            description: 'Perbesar resolusi dengan AI atau Lanczos',
            value: options.upscale,
            onChanged: (v) =>
                controller.updateOptions((o) => o.copyWith(upscale: v)),
          ),
          if (options.upscale) _UpscaleSettings(controller: controller),

          const SizedBox(height: 4),
          // Always shown, even for a photo-only selection. It used to vanish
          // entirely, which read as the app having lost a feature its own
          // subtitle advertises; greyed out with a reason is honest instead.
          _OpToggle(
            icon: Icons.speed,
            name: 'Boost ke $kTargetFps FPS',
            description: controller.capabilities.rife
                ? 'Motion interpolation via RIFE AI'
                : 'Motion interpolation via FFmpeg minterpolate',
            enabled: controller.showFpsOption,
            disabledReason: controller.hasFiles
                ? 'Hanya untuk video — pilihan saat ini foto semua'
                : 'Hanya untuk video — pilih klip dulu',
            value: options.fpsBoost,
            onChanged: (v) =>
                controller.updateOptions((o) => o.copyWith(fpsBoost: v)),
          ),
          if (controller.showFpsOption && options.fpsBoost)
            _FpsSettings(controller: controller),

          const SizedBox(height: LabSpacing.gap),
          const Divider(height: 1),
          const SizedBox(height: LabSpacing.gap),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LabeledDropdown<Quality>(
                  label: 'Kualitas Output',
                  value: options.quality,
                  items: Quality.values,
                  labelOf: (q) => q.label,
                  onChanged: (q) =>
                      controller.updateOptions((o) => o.copyWith(quality: q)),
                ),
              ),
              if (controller.showFpsOption) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _LabeledDropdown<VideoCodec>(
                    label: 'Codec Video',
                    value: options.codec,
                    items: VideoCodec.values,
                    labelOf: (c) => c.label,
                    hint: controller.capabilities.encoderSummary,
                    onChanged: (c) =>
                        controller.updateOptions((o) => o.copyWith(codec: c)),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: LabSpacing.gap),
          _OutputFolderRow(controller: controller),
        ],
      ),
    );
  }
}

/// Where results land. Lives here rather than behind a dialog because it is
/// the first thing people look for and the last place they think to open.
class _OutputFolderRow extends StatelessWidget {
  const _OutputFolderRow({required this.controller});

  final AppController controller;

  /// The subfolder a dropped folder's results will go into, if the selection
  /// came from exactly one folder.
  String? get _subfolder {
    final roots = controller.files
        .map((f) => f.sourceRoot)
        .whereType<String>()
        .toSet();
    if (roots.length != 1) return null;
    return '${pth.basename(roots.first)}_upscaled';
  }

  Future<void> _pick() async {
    final dir = await getDirectoryPath(
      confirmButtonText: 'Pilih folder output',
    );
    if (dir == null) return;
    await controller.setOutputDir(dir);
  }

  @override
  Widget build(BuildContext context) {
    final sub = _subfolder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Folder Output'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: LabColors.background,
            borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
            border: Border.all(color: LabColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 16,
                color: LabColors.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.outputDir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: LabColors.textSecondary,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '└ $sub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: LabColors.primaryBright,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: controller.isRunning ? null : _pick,
                icon: const Icon(Icons.edit_outlined, size: 15),
                tooltip: 'Ubah folder output',
                color: LabColors.textMuted,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
              ),
              if (!controller.usesDefaultOutputDir)
                IconButton(
                  onPressed:
                      controller.isRunning ? null : controller.resetOutputDir,
                  icon: const Icon(Icons.settings_backup_restore, size: 15),
                  tooltip: 'Kembalikan ke folder bawaan',
                  color: LabColors.textMuted,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  padding: EdgeInsets.zero,
                ),
              IconButton(
                onPressed: () => controller.revealInFileManager(),
                icon: const Icon(Icons.open_in_new, size: 15),
                tooltip: 'Buka folder',
                color: LabColors.textMuted,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Upscale sub-settings ────────────────────────────────────────────────────

class _UpscaleSettings extends StatelessWidget {
  const _UpscaleSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.options;
    final first = controller.firstFile;

    return _SubSettings(
      children: [
        _LabeledDropdown<UpscaleModel>(
          label: 'Model Upscale',
          value: options.upscaleModel,
          items: UpscaleModel.values,
          labelOf: (m) => m.label,
          disabledOf: (m) => !controller.isModelInstalled(m),
          hint: UpscaleModel.values.every(controller.isModelInstalled)
              ? null
              : 'Model yang redup belum terpasang — jalankan '
                  'tools/fetch_binaries --extra-models',
          onChanged: (m) =>
              controller.updateOptions((o) => o.copyWith(upscaleModel: m)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const _FieldLabel('Skala Output'),
            const Spacer(),
            for (var scale = kMinScale; scale <= kMaxScale; scale++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _ScaleChip(
                  scale: scale,
                  selected: options.upscaleScale == scale,
                  onTap: () => controller
                      .updateOptions((o) => o.copyWith(upscaleScale: scale)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          controller.dimensionEstimate,
          style: const TextStyle(fontSize: 11.5, color: LabColors.textMuted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _FieldLabel('Sharpness  ${(options.sharpness * 100).round()}%'),
            if ((options.sharpness - 0.3).abs() < 0.001)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text(
                  '(default)',
                  style: TextStyle(fontSize: 11, color: LabColors.textFaint),
                ),
              ),
          ],
        ),
        Slider(
          value: options.sharpness,
          onChanged: (v) =>
              controller.updateOptions((o) => o.copyWith(sharpness: v)),
        ),
        if (options.useEsrgan && first != null && first.isVideo)
          const _Notice(
            tone: LabColors.warning,
            text: 'Real-ESRGAN pada video diproses per-frame — '
                'gunakan untuk klip pendek.',
          ),
        if (controller.esrganMissing)
          const _Notice(
            tone: LabColors.danger,
            text: 'realesrgan-ncnn-vulkan tidak ditemukan — '
                'lihat panel Setup & Status di bawah.',
          ),
      ],
    );
  }
}

// ── FPS sub-settings ────────────────────────────────────────────────────────

class _FpsSettings extends StatelessWidget {
  const _FpsSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final caps = controller.capabilities;
    return _SubSettings(
      children: [
        _LabeledDropdown<InterpEngine>(
          label: 'Engine Interpolasi',
          value: controller.options.interpEngine,
          items: InterpEngine.values,
          labelOf: (e) => e.label,
          disabledOf: (e) => e == InterpEngine.rife && !caps.rife,
          hint: caps.rife
              ? '✓ RIFE aktif'
              : '⚠ RIFE belum tersedia — pakai FFmpeg',
          onChanged: (e) =>
              controller.updateOptions((o) => o.copyWith(interpEngine: e)),
        ),
      ],
    );
  }
}

// ── Shared building blocks ──────────────────────────────────────────────────

class _OpToggle extends StatelessWidget {
  const _OpToggle({
    required this.icon,
    required this.name,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.disabledReason,
  });

  final IconData icon;
  final String name;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// A greyed-out row still tells the user the feature exists. Hiding it makes
  /// the app look like it lost a feature it advertises.
  final bool enabled;

  /// Replaces [description] while disabled, to say *why* it is unavailable.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final subtitle = enabled ? description : (disabledReason ?? description);

    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: enabled ? LabColors.primaryBright : LabColors.textFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? LabColors.textPrimary
                          : LabColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: LabColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubSettings extends StatelessWidget {
  const _SubSettings({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6, right: 6, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LabColors.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
        border: Border.all(color: LabColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: LabColors.textSecondary,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.disabledOf,
    this.hint,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final bool Function(T)? disabledOf;
  final String? hint;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: LabColors.surfaceRaised,
            borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
            border: Border.all(color: LabColors.borderStrong),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              padding: const EdgeInsets.symmetric(vertical: 10),
              dropdownColor: LabColors.surfaceRaised,
              borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
              style: const TextStyle(
                fontSize: 12.5,
                color: LabColors.textPrimary,
              ),
              items: [
                for (final item in items)
                  DropdownMenuItem<T>(
                    value: item,
                    enabled: !(disabledOf?.call(item) ?? false),
                    child: Text(
                      labelOf(item),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: (disabledOf?.call(item) ?? false)
                            ? LabColors.textFaint
                            : LabColors.textPrimary,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 5),
          Text(
            hint!,
            style: const TextStyle(fontSize: 11, color: LabColors.textFaint),
          ),
        ],
      ],
    );
  }
}

class _ScaleChip extends StatelessWidget {
  const _ScaleChip({
    required this.scale,
    required this.selected,
    required this.onTap,
  });

  final int scale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? LabColors.primary.withValues(alpha: 0.22)
              : LabColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? LabColors.primary : LabColors.borderStrong,
          ),
        ),
        child: Text(
          '$scale×',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? LabColors.primaryBright : LabColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.tone, required this.text});

  final Color tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: tone),
      ),
    );
  }
}
