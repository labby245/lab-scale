/// Two-column workspace: controls on the left, preview and log on the right.
///
/// The wide form is sized to sit inside one window with no page-level scroll —
/// the preview stretches to take whatever height is left over, and each column
/// scrolls on its own only when its own content outgrows the window. Below the
/// breakpoint the columns stack and the whole page scrolls instead.
library;

import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/log_card.dart';
import 'widgets/ops_card.dart';
import 'widgets/results_card.dart';
import 'widgets/setup_panel.dart';
import 'widgets/file_stage.dart';

/// Below this width the two columns stack instead of sitting side by side.
const double _kTwoColumnBreakpoint = 1040;

/// Log height in the one-screen layout — shorter than the stacked default so
/// the preview above it keeps the bulk of the column.
const double _kWideLogHeight = 150;

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
                return constraints.maxWidth >= _kTwoColumnBreakpoint
                    ? _WideWorkspace(controller: controller)
                    : _NarrowWorkspace(controller: controller);
              },
            ),
          ),
          SetupStatusBar(controller: controller),
        ],
      ),
    );
  }
}

/// Side-by-side columns that together fill exactly one window height.
class _WideWorkspace extends StatelessWidget {
  const _WideWorkspace({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LabSpacing.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1560),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: _StageColumn(controller: controller),
              ),
              const SizedBox(width: LabSpacing.gap),
              Expanded(
                flex: 5,
                // The controls are the only part that can outgrow the window
                // (Real-ESRGAN and RIFE both expand when switched on), so this
                // column — and only this column — gets its own scrollbar.
                child: SingleChildScrollView(
                  child: _ControlColumn(controller: controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stacked fallback for narrow windows — the whole page scrolls.
class _NarrowWorkspace extends StatelessWidget {
  const _NarrowWorkspace({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LabSpacing.pagePadding),
      child: Column(
        children: [
          FileStage(controller: controller),
          const SizedBox(height: LabSpacing.gap),
          _ControlColumn(controller: controller),
          if (controller.logLines.isNotEmpty) ...[
            const SizedBox(height: LabSpacing.gap),
            LogCard(controller: controller),
          ],
        ],
      ),
    );
  }
}

class _ControlColumn extends StatelessWidget {
  const _ControlColumn({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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

/// The gallery column: the file stage owns it — drop target when empty, grid
/// once filled — with the log arriving during a run.
///
/// There is no preview pane here any more. A pane this shape could only ever
/// be a few hundred pixels tall, which is not enough to judge an upscale, so
/// clicking a tile opens the full-window viewer instead and the grid keeps the
/// whole column.
class _StageColumn extends StatelessWidget {
  const _StageColumn({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: FileStage(controller: controller, expand: true)),
        if (controller.logLines.isNotEmpty) ...[
          const SizedBox(height: LabSpacing.gap),
          LogCard(controller: controller, height: _kWideLogHeight),
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
          // The app icon itself, so the header mark and the one in the Dock
          // are the same thing. Its rounded corners are baked into the PNG —
          // clipping again here would round them twice.
          Image.asset(
            'assets/logo.png',
            width: 34,
            height: 34,
            filterQuality: FilterQuality.medium,
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
          const SizedBox(width: 14),
          const Text(
            'Diproses lokal · file asli tidak diubah',
            style: TextStyle(fontSize: 11, color: LabColors.textFaint),
          ),
        ],
      ),
    );
  }
}
