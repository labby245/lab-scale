/// Before/after comparison: one image laid over the other, with a divider you
/// drag to reveal each side.
///
/// Both sides are drawn into the same box with `BoxFit.contain`, and the
/// "before" copy is clipped to the left of the divider. Because an upscale
/// preserves aspect ratio, the two land pixel-for-pixel on top of each other —
/// which is the whole point: anything that moves as you drag is a real
/// difference, not a layout artefact.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../theme.dart';

class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.beforePath,
    required this.afterPath,
    this.beforeLabel,
    this.afterLabel,
  });

  final String beforePath;
  final String afterPath;

  /// Null means the plain "Original" / "Result" in the current language.
  final String? beforeLabel;
  final String? afterLabel;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  /// Divider position as a fraction of the width.
  double _split = 0.5;

  /// Dragging must track the finger exactly; the snap buttons look better
  /// sweeping across. Same value, two different durations.
  Duration _glide = Duration.zero;

  /// Both sides are held back until both have decoded, so the comparison
  /// never appears one half at a time — the upscaled side is several times
  /// the pixels of the original and would otherwise always arrive second.
  bool _ready = false;
  Object? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmUp();
  }

  @override
  void didUpdateWidget(CompareSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beforePath != widget.beforePath ||
        oldWidget.afterPath != widget.afterPath) {
      _ready = false;
      _warmUp();
    }
  }

  Future<void> _warmUp() async {
    final token = Object();
    _pending = token;
    try {
      await Future.wait([
        precacheImage(FileImage(File(widget.beforePath)), context),
        precacheImage(FileImage(File(widget.afterPath)), context),
      ]);
    } catch (_) {
      // A missing or undecodable file falls through to the normal error
      // builder rather than leaving the stage blank forever.
    }
    // A newer pair may have been requested while these were decoding.
    if (!mounted || _pending != token) return;
    setState(() => _ready = true);
  }

  void _moveTo(double dx, double width) {
    if (width <= 0) return;
    setState(() {
      _glide = Duration.zero;
      _split = (dx / width).clamp(0.0, 1.0);
    });
  }

  void _snapTo(double value) {
    setState(() {
      _glide = const Duration(milliseconds: 260);
      _split = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final beforeLabel = widget.beforeLabel ?? s.before;
    final afterLabel = widget.afterLabel ?? s.after;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          // Tap anywhere to jump the divider there; drag to sweep it.
          onTapDown: (d) => _moveTo(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _moveTo(d.localPosition.dx, width),
          child: ColoredBox(
            color: Colors.black,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _split),
              duration: _glide,
              curve: Curves.easeOutCubic,
              builder: (context, split, _) => Stack(
                fit: StackFit.expand,
                children: [
                  _Side(path: widget.afterPath),
                  ClipRect(
                    clipper: _LeftClipper(split),
                    child: _Side(path: widget.beforePath),
                  ),
                  if (split > 0.001 && split < 0.999) _Handle(x: width * split),
                  _Tag(
                    label: beforeLabel,
                    alignment: Alignment.topLeft,
                    visible: split > 0.12,
                  ),
                  _Tag(
                    label: afterLabel,
                    alignment: Alignment.topRight,
                    visible: split < 0.88,
                  ),
                  _SnapBar(
                    split: split,
                    beforeLabel: beforeLabel,
                    afterLabel: afterLabel,
                    compareLabel: s.compare,
                    onSnap: _snapTo,
                  ),
                  // Covers rather than replaces the comparison: the widgets
                  // below are already laid out and simply become visible
                  // together once both sides have decoded.
                  if (!_ready)
                    const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One click to see a whole side, instead of having to drag the divider all
/// the way across every time.
class _SnapBar extends StatelessWidget {
  const _SnapBar({
    required this.split,
    required this.beforeLabel,
    required this.afterLabel,
    required this.compareLabel,
    required this.onSnap,
  });

  final double split;
  final String beforeLabel;
  final String afterLabel;
  final String compareLabel;
  final ValueChanged<double> onSnap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(10),
        // Scales down rather than overflowing when the stage is narrow — a
        // half-width comparison pane, or a very tall portrait image.
        child: FittedBox(fit: BoxFit.scaleDown, child: _bar()),
      ),
    );
  }

  Widget _bar() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SnapChip(
            label: beforeLabel,
            selected: split > 0.999,
            onPressed: () => onSnap(1),
          ),
          _SnapChip(
            label: compareLabel,
            selected: split > 0.001 && split < 0.999,
            onPressed: () => onSnap(0.5),
          ),
          _SnapChip(
            label: afterLabel,
            selected: split < 0.001,
            onPressed: () => onSnap(0),
          ),
        ],
      ),
    );
  }
}

class _SnapChip extends StatelessWidget {
  const _SnapChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? LabColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : LabColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      // Both sides must align exactly, so neither may be nudged by the
      // default alignment of a differently-sized bitmap.
      alignment: Alignment.center,
      errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  const _LeftClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper oldClipper) => oldClipper.fraction != fraction;
}

class _Handle extends StatelessWidget {
  const _Handle({required this.x});

  final double x;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: math.max(0, x - 14),
      top: 0,
      bottom: 0,
      width: 28,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(width: 2, height: double.infinity, color: Colors.white),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.code,
                  size: 15,
                  color: LabColors.background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.alignment,
    required this.visible,
  });

  final String label;
  final Alignment alignment;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: visible ? 1 : 0,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
