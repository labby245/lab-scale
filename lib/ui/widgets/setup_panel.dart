/// Collapsible panel reporting which external tools LabScale can find.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/binaries.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class SetupPanel extends StatelessWidget {
  const SetupPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final caps = controller.capabilities;
    final summary = caps.readyCount == caps.totalCount
        ? '✓ semua fitur AI aktif'
        : '${caps.readyCount}/${caps.totalCount} fitur AI aktif';

    return LabCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          leading: const Icon(Icons.settings_outlined, size: 19),
          title: const Text(
            'Setup & Status',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            summary,
            style: const TextStyle(fontSize: 11.5, color: LabColors.textMuted),
          ),
          children: [
            _ToolRow(
              available: caps.ffmpeg,
              name: 'FFmpeg',
              detail: 'Dekode, enkode, dan filter — wajib ada',
              hint: 'Install FFmpeg, atau salin ffmpeg + ffprobe ke bin/',
            ),
            _ToolRow(
              available: caps.esrgan,
              name: 'Upscale AI (Real-ESRGAN)',
              detail: 'realesrgan-ncnn-vulkan — GPU Vulkan / Metal',
              hint: 'Salin realesrgan-ncnn-vulkan + folder models ke bin/',
            ),
            _ToolRow(
              available: caps.rife,
              name: 'Interpolasi AI (RIFE)',
              detail: 'rife-ncnn-vulkan — 5–10× lebih cepat dari FFmpeg',
              hint: 'Salin rife-ncnn-vulkan + folder model ke bin/',
            ),
            _EncoderRow(summary: caps.encoderSummary),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dicari di: ${Binaries.searchDirs.first}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: LabColors.textFaint,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.refreshCapabilities,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('Cek ulang'),
                  style: TextButton.styleFrom(
                    foregroundColor: LabColors.primaryBright,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
              tooltip: 'Salin petunjuk',
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
                const Text(
                  'Video Encoder',
                  style: TextStyle(fontSize: 12.5, color: LabColors.textPrimary),
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
