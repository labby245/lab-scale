/// Operation toggles: upscale (model, scale, sharpness) and 60 FPS boost,
/// plus the global quality and codec selectors.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;
import 'package:url_launcher/url_launcher.dart';

import '../../core/model_store.dart';
import '../../l10n/strings.dart';
import '../../models/process_options.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class OpsCard extends StatelessWidget {
  const OpsCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final options = controller.options;

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabCardTitle(badge: '2', title: s.opsTitle),

          _OpToggle(
            icon: Icons.zoom_out_map,
            name: s.upscale,
            description: s.upscaleDescription,
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
            name: s.fpsBoost,
            description: controller.capabilities.rife
                ? s.fpsViaRife
                : s.fpsViaFfmpeg,
            enabled: controller.showFpsOption,
            disabledReason: controller.hasFiles
                ? s.fpsOnlyVideoPhotos
                : s.fpsOnlyVideoEmpty,
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
                  label: s.outputQuality,
                  value: options.quality,
                  items: Quality.values,
                  labelOf: s.qualityLabel,
                  onChanged: (q) =>
                      controller.updateOptions((o) => o.copyWith(quality: q)),
                ),
              ),
              if (controller.showFpsOption) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _LabeledDropdown<VideoCodec>(
                    label: s.videoCodec,
                    value: options.codec,
                    items: VideoCodec.values,
                    labelOf: s.codecLabel,
                    hint: controller.capabilities.encoderSummary(s),
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
      confirmButtonText: S.current.pickOutputFolder,
    );
    if (dir == null) return;
    await controller.setOutputDir(dir);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sub = _subfolder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(s.outputFolder),
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
                tooltip: s.changeOutputFolder,
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
                  tooltip: s.resetOutputFolder,
                  color: LabColors.textMuted,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  padding: EdgeInsets.zero,
                ),
              IconButton(
                onPressed: () => controller.revealInFileManager(),
                icon: const Icon(Icons.open_in_new, size: 15),
                tooltip: s.openFolder,
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

  /// Downloadable models stay pickable — choosing one is how you get to its
  /// download button. Only a model that can neither run nor be fetched is
  /// greyed out.
  String _modelLabel(S s, UpscaleModel m) {
    final download = downloadableFor(m);
    if (download != null && !controller.isModelInstalled(m)) {
      return '${s.modelLabel(m)}${s.modelDownloadSuffix(download.sizeBytes)}';
    }
    return s.modelLabel(m);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final options = controller.options;
    final first = controller.firstFile;
    final model = options.upscaleModel;
    final download = downloadableFor(model);

    return _SubSettings(
      children: [
        _LabeledDropdown<UpscaleModel>(
          label: s.upscaleModel,
          value: model,
          items: UpscaleModel.values,
          labelOf: (m) => _modelLabel(s, m),
          // Downloadable models stay pickable to reach their download button
          // — unless no AI model can run here at all.
          disabledOf: (m) =>
              !controller.isModelInstalled(m) &&
              (downloadableFor(m) == null || !controller.capabilities.esrgan),
          onChanged: (m) =>
              controller.updateOptions((o) => o.copyWith(upscaleModel: m)),
        ),
        if (download != null && controller.capabilities.esrgan)
          _ModelDownloadPanel(controller: controller, download: download),
        const SizedBox(height: 14),
        Row(
          children: [
            _FieldLabel(s.outputScale),
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
          controller.dimensionEstimate(s),
          style: const TextStyle(fontSize: 11.5, color: LabColors.textMuted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _FieldLabel(s.sharpness((options.sharpness * 100).round())),
            if ((options.sharpness - 0.3).abs() < 0.001)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  s.defaultTag,
                  style: const TextStyle(
                    fontSize: 11,
                    color: LabColors.textFaint,
                  ),
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
          _Notice(tone: LabColors.warning, text: s.esrganVideoNotice),
        // A missing binary is a broken install; a missing downloadable model
        // is already explained by the download panel above.
        if (controller.capabilities.esrganIssue != null && model.isAi)
          _Notice(tone: LabColors.warning, text: s.noVulkanHint)
        else if (controller.esrganMissing && !controller.capabilities.esrgan)
          _Notice(tone: LabColors.danger, text: s.esrganMissingNotice)
        else if (controller.esrganMissing && download == null)
          _Notice(tone: LabColors.danger, text: s.modelWeightsMissing),
      ],
    );
  }
}

/// Credit, licence and the download button for a model that is not part of
/// the installer. The credit shows whether or not it is installed: the
/// licence asks for attribution wherever the model is used.
class _ModelDownloadPanel extends StatelessWidget {
  const _ModelDownloadPanel({
    required this.controller,
    required this.download,
  });

  final AppController controller;
  final DownloadableModel download;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final model = download.model;
    final installed = controller.isModelInstalled(model);
    final downloading = controller.isDownloading(model);
    final progress = controller.downloadProgress(model);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: LabColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LabColors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!installed) ...[
            Text(
              s.modelNotInstalled(download.sizeBytes),
              style: const TextStyle(
                fontSize: 11.5,
                color: LabColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (downloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: progress, minHeight: 4),
              ),
              const SizedBox(height: 5),
              Text(
                s.downloading(((progress ?? 0) * 100).round()),
                style: const TextStyle(fontSize: 11, color: LabColors.textMuted),
              ),
            ] else
              FilledButton.tonalIcon(
                onPressed: controller.isRunning
                    ? null
                    : () => controller.downloadModel(model),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(s.downloadModel),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
          ],
          InkWell(
            onTap: () => launchUrl(Uri.parse(download.licenseUrl)),
            child: Text(
              s.modelCredit(download.author, download.license),
              style: const TextStyle(
                fontSize: 10.5,
                color: LabColors.textFaint,
                decoration: TextDecoration.underline,
                decorationColor: LabColors.textFaint,
              ),
            ),
          ),
          Text(
            s.nonCommercialNote,
            style: const TextStyle(fontSize: 10.5, color: LabColors.textFaint),
          ),
        ],
      ),
    );
  }
}

// ── FPS sub-settings ────────────────────────────────────────────────────────

class _FpsSettings extends StatelessWidget {
  const _FpsSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final caps = controller.capabilities;
    return _SubSettings(
      children: [
        _LabeledDropdown<InterpEngine>(
          label: s.interpEngine,
          value: controller.options.interpEngine,
          items: InterpEngine.values,
          labelOf: s.interpLabel,
          disabledOf: (e) => e == InterpEngine.rife && !caps.rife,
          hint: caps.rife ? s.rifeActive : s.rifeUnavailable,
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
