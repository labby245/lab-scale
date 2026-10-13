/// About LabScale: version, update check, links, licences and the log file.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_links.dart';
import '../../core/update_check.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

Future<void> showLabScaleAbout(
  BuildContext context,
  AppController controller,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AboutDialog(controller: controller),
    );

class _AboutDialog extends StatefulWidget {
  const _AboutDialog({required this.controller});

  final AppController controller;

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  bool _checking = false;
  UpdateStatus? _checked;

  Future<void> _check() async {
    setState(() => _checking = true);
    final status = await widget.controller.checkForUpdates(manual: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = status;
    });
  }

  void _open(String url) => launchUrl(Uri.parse(url));

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final controller = widget.controller;
    final update = controller.pendingUpdate;

    final checkLine = switch (_checked) {
      _ when _checking => s.checkingUpdates,
      UpdateStatus.upToDate => s.upToDate,
      UpdateStatus.failed => s.updateCheckFailed,
      UpdateStatus.available when update != null =>
        s.updateAvailable(update.version),
      _ => null,
    };

    return AlertDialog(
      backgroundColor: LabColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LabSpacing.cardRadius),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/logo.png', width: 48, height: 48),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LabScale',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: LabColors.textPrimary,
                      ),
                    ),
                    Text(
                      s.version(controller.version),
                      style: const TextStyle(
                        fontSize: 12,
                        color: LabColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s.aboutBlurb,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: LabColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.madeBy,
              style: const TextStyle(fontSize: 12, color: LabColors.textMuted),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LinkChip(
                  icon: Icons.code,
                  label: s.sourceCode,
                  onPressed: () => _open(kRepoUrl),
                ),
                _LinkChip(
                  icon: Icons.bug_report_outlined,
                  label: s.reportIssue,
                  onPressed: () => _open(kIssuesUrl),
                ),
                _LinkChip(
                  icon: Icons.gavel_outlined,
                  label: s.licenses,
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'LabScale',
                    applicationVersion: controller.version,
                    applicationLegalese: '© 2026 Labstory Studio · MIT',
                  ),
                ),
                if (controller.logPath != null)
                  _LinkChip(
                    icon: Icons.description_outlined,
                    label: s.openLogFolder,
                    onPressed: () =>
                        controller.revealInFileManager(controller.logPath),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: Text(s.checkUpdates),
                ),
                const SizedBox(width: 12),
                if (checkLine != null)
                  Expanded(
                    child: Text(
                      checkLine,
                      style: const TextStyle(
                        fontSize: 12,
                        color: LabColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            if (update != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _open(update.pageUrl),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text('${s.download} ${update.version}'),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _open(kFotolaneUrl),
              child: Text(
                s.fotolanePitch,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: LabColors.primaryBright,
                ),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _open(kInstagramUrl),
              child: const Text(
                'Instagram @labstory.studio',
                style: TextStyle(fontSize: 11.5, color: LabColors.textMuted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.close),
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 15, color: LabColors.primaryBright),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onPressed,
      backgroundColor: LabColors.surface,
      side: const BorderSide(color: LabColors.borderStrong),
    );
  }
}
