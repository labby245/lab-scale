/// Tool availability, shown as a status strip pinned to the bottom of the
/// workspace with the full breakdown one click away.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/binaries.dart';
import '../../core/gpu_probe.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

/// Slim always-visible bar: one dot per external tool, plus the encoder in use.
///
/// This used to be a full-width collapsible card stacked under the columns,
/// which pushed the workspace past one screen for a panel that is glanced at
/// and then ignored. The detail now lives in [_SetupDetailsDialog].
class SetupStatusBar extends StatelessWidget {
  const SetupStatusBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final caps = controller.capabilities;
    final allReady = caps.readyCount == caps.totalCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(LabSpacing.pagePadding, 9, 12, 9),
      decoration: const BoxDecoration(
        color: LabColors.surface,
        border: Border(top: BorderSide(color: LabColors.border)),
      ),
      child: Row(
        children: [
          _ToolDot(ready: caps.ffmpeg, label: 'FFmpeg'),
          const SizedBox(width: 14),
          _ToolDot(ready: caps.esrgan, label: 'Real-ESRGAN'),
          const SizedBox(width: 14),
          _ToolDot(ready: caps.rife, label: 'RIFE'),
          const SizedBox(width: 16),
          const _Separator(),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              caps.encoderSummary(s),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: LabColors.textMuted),
            ),
          ),
          const Spacer(),
          if (!allReady)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                s.aiReady(caps.readyCount, caps.totalCount),
                style: const TextStyle(fontSize: 11.5, color: LabColors.warning),
              ),
            ),
          TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _SetupDetailsDialog(controller: controller),
            ),
            icon: const Icon(Icons.settings_outlined, size: 15),
            label: Text(s.setupStatus),
            style: TextButton.styleFrom(
              foregroundColor: LabColors.textSecondary,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolDot extends StatelessWidget {
  const _ToolDot({required this.ready, required this.label});

  final bool ready;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ready ? LabColors.success : LabColors.textFaint,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: ready ? LabColors.textSecondary : LabColors.textFaint,
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 14, color: LabColors.border);
}

class _SetupDetailsDialog extends StatelessWidget {
  const _SetupDetailsDialog({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // The dialog is its own route, so it does not rebuild when the home page
    // does — without listening here, "Cek ulang" would re-probe and leave the
    // rows showing the previous answer.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final s = S.of(context);
    final caps = controller.capabilities;

    return AlertDialog(
      backgroundColor: LabColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LabSpacing.cardRadius),
      ),
      title: Text(
        s.setupStatus,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToolRow(
              available: caps.ffmpeg,
              name: 'FFmpeg',
              detail: s.ffmpegDetail,
              hint: s.ffmpegHint,
            ),
            _ToolRow(
              available: caps.esrgan,
              name: s.esrganName,
              detail: s.esrganDetail,
              hint: _issueText(s, caps.esrganIssue) ?? s.esrganHint,
            ),
            _ToolRow(
              available: caps.rife,
              name: s.rifeName,
              detail: s.rifeDetail,
              hint: _issueText(s, caps.rifeIssue) ?? s.rifeHint,
            ),
            _EncoderRow(summary: caps.encoderSummary(s)),
            const SizedBox(height: 12),
            Text(
              s.searchedIn(Binaries.searchDirs.first),
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: LabColors.textFaint,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: controller.refreshCapabilities,
          icon: const Icon(Icons.refresh, size: 15),
          label: Text(s.recheck),
          style: TextButton.styleFrom(
            foregroundColor: LabColors.primaryBright,
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.close),
        ),
      ],
    );
  }
}

/// A tool that is installed but cannot run here is a GPU problem, not a
/// missing file, and "copy it into bin/" would send the user the wrong way.
String? _issueText(S s, GpuProbeResult? issue) => switch (issue) {
      null => null,
      GpuProbeResult(failure: GpuProbeFailure.noVulkan) => s.noVulkanShort,
      _ => s.gpuProbeFailed(issue.detail),
    };

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.available,
    required this.name,
    required this.detail,
    required this.hint,
  });

  final bool available;
  final String name;
  final String detail;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            available ? Icons.check_circle : Icons.cancel_outlined,
            size: 16,
            color: available ? LabColors.success : LabColors.textFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LabColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  available ? detail : hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: available ? LabColors.textFaint : LabColors.warning,
                  ),
                ),
              ],
            ),
          ),
          if (!available)
            IconButton(
              tooltip: S.of(context).copyHint,
              iconSize: 15,
              color: LabColors.textFaint,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => Clipboard.setData(ClipboardData(text: hint)),
            ),
        ],
      ),
    );
  }
}

class _EncoderRow extends StatelessWidget {
  const _EncoderRow({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.memory_outlined, size: 16, color: LabColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).videoEncoder,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LabColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(fontSize: 11, color: LabColors.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
