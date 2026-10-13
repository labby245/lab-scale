/// Per-file outcome list shown once a job finishes.
library;

import 'package:flutter/material.dart';

import '../../core/pipeline.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class ResultsCard extends StatelessWidget {
  const ResultsCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final results = controller.results;
    final ok = results.where((r) => r.isSuccess).length;

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabCardTitle(badge: '✓', title: s.resultsTitle),
          Text(
            results.any((r) => r.cancelled)
                ? s.succeededCancelled(ok, results.length)
                : s.succeeded(ok, results.length),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ok == results.length ? LabColors.success : LabColors.warning,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            controller.outputDir,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: LabColors.textFaint,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => controller.revealInFileManager(),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(s.openFolderButton),
            style: OutlinedButton.styleFrom(
              foregroundColor: LabColors.primaryBright,
              side: BorderSide(color: LabColors.primary.withValues(alpha: 0.35)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final result in results) _ResultRow(result: result),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final JobResult result;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tone = result.isSuccess
        ? LabColors.success
        : result.cancelled
            ? LabColors.warning
            : LabColors.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.isSuccess
                ? Icons.check_circle_outline
                : result.cancelled
                    ? Icons.remove_circle_outline
                    : Icons.error_outline,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.sourceName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LabColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.isSuccess
                      ? '→ ${result.outputName}'
                      : result.cancelled
                          ? s.cancelled
                          : result.error ?? s.failed,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: result.isSuccess ? LabColors.primaryBright : tone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
