/// Live process log, auto-scrolled to the newest line.
library;

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../theme.dart';

class LogCard extends StatefulWidget {
  const LogCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<LogCard> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(LogCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jump after the frame so the new line is already laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.controller.logLines;

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabCardTitle(
            badge: '⚙',
            title: 'Log Proses',
            trailing: widget.controller.isRunning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          Container(
            height: 190,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LabColors.background,
              borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
              border: Border.all(color: LabColors.border),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: lines.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  lines[index],
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: LabColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
