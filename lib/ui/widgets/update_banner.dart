/// A thin strip under the header when a newer release is published.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final update = controller.pendingUpdate;
    if (update == null) return const SizedBox.shrink();
    final s = S.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 6, 12, 6),
      color: LabColors.primary.withValues(alpha: 0.14),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_alt,
            size: 16,
            color: LabColors.primaryBright,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.updateAvailable(update.version),
              style: const TextStyle(
                fontSize: 12.5,
                color: LabColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(update.pageUrl)),
            child: Text(s.download),
          ),
          TextButton(
            onPressed: controller.dismissUpdate,
            style: TextButton.styleFrom(
              foregroundColor: LabColors.textMuted,
            ),
            child: Text(s.later),
          ),
        ],
      ),
    );
  }
}
