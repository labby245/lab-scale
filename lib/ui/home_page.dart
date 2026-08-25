/// Two-column workspace: controls on the left, preview and log on the right.
library;

import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/log_card.dart';
import 'widgets/ops_card.dart';
import 'widgets/preview_card.dart';
import 'widgets/results_card.dart';
import 'widgets/setup_panel.dart';
import 'widgets/source_card.dart';

/// Below this width the two columns stack instead of sitting side by side.
const double _kTwoColumnBreakpoint = 1040;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final error = widget.controller.errorMessage;
    if (error != null) {
      widget.controller.dismissError();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      body: Column(
        children: [
          _Header(controller: controller),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= _kTwoColumnBreakpoint;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Column(
                        children: [
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _LeftColumn(controller: controller),
                                ),
                                const SizedBox(width: LabSpacing.gap),
                                Expanded(
                                  flex: 6,
                                  child: _RightColumn(controller: controller),
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _LeftColumn(controller: controller),
                                const SizedBox(height: LabSpacing.gap),
                                _RightColumn(controller: controller),
                              ],
                            ),
                          const SizedBox(height: LabSpacing.gap),
                          SetupPanel(controller: controller),
                          const SizedBox(height: 20),
                          const _Footer(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SourceCard(controller: controller),
        const SizedBox(height: LabSpacing.gap),
        OpsCard(controller: controller),
        const SizedBox(height: LabSpacing.gap),
        _ProcessButton(controller: controller),
        if (controller.results.isNotEmpty) ...[
          const SizedBox(height: LabSpacing.gap),
          ResultsCard(controller: controller),
        ],
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  const _RightColumn({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PreviewCard(file: controller.firstFile),
        if (controller.logLines.isNotEmpty) ...[
          const SizedBox(height: LabSpacing.gap),
          LogCard(controller: controller),
        ],
      ],
    );
  }
}

class _ProcessButton extends StatelessWidget {
  const _ProcessButton({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final label = !controller.hasFiles
        ? 'Proses File'
        : controller.isBulk
            ? 'Proses ${controller.files.length} File'
            : 'Proses File';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: controller.canProcess ? controller.run : null,
            icon: controller.isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_forward, size: 18),
            label: Text(controller.isRunning ? 'Memproses…' : label),
            style: FilledButton.styleFrom(
              backgroundColor: LabColors.primary,
              disabledBackgroundColor: LabColors.primary.withValues(alpha: 0.25),
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (controller.isRunning || controller.progress != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: controller.progress,
              minHeight: 5,
              backgroundColor: LabColors.borderStrong,
            ),
          ),
        ],
        if (controller.statusText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            controller.statusText,
            style: const TextStyle(fontSize: 12, color: LabColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final badge = controller.selectionBadge;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LabColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [LabColors.primary, LabColors.accent],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.open_in_full, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LabScale',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: LabColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Foto · Video · Upscale · 60 FPS',
                style: TextStyle(fontSize: 11, color: LabColors.textFaint),
              ),
            ],
          ),
          const Spacer(),
          if (badge.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: LabColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: LabColors.primaryBright,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'LabScale · Diproses lokal · FFmpeg + ncnn-vulkan · File asli tidak diubah',
      style: TextStyle(fontSize: 11.5, color: LabColors.textFaint),
    );
  }
}
