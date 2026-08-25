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

import '../theme.dart';

class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.beforePath,
    required this.afterPath,
    this.beforeLabel = 'Asli',
    this.afterLabel = 'Hasil',
  });

  final String beforePath;
  final String afterPath;
  final String beforeLabel;
  final String afterLabel;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  /// Divider position as a fraction of the width.
  double _split = 0.5;

  void _moveTo(double dx, double width) {
    if (width <= 0) return;
    setState(() => _split = (dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final handleX = width * _split;

        return GestureDetector(
          // Tap anywhere to jump the divider there; drag to sweep it.
          onTapDown: (d) => _moveTo(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _moveTo(d.localPosition.dx, width),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Side(path: widget.afterPath),
                ClipRect(
                  clipper: _LeftClipper(_split),
                  child: _Side(path: widget.beforePath),
                ),
                _Handle(x: handleX),
                _Tag(
                  label: widget.beforeLabel,
                  alignment: Alignment.topLeft,
                  visible: _split > 0.12,
                ),
                _Tag(
                  label: widget.afterLabel,
                  alignment: Alignment.topRight,
                  visible: _split < 0.88,
                ),
              ],
            ),
          ),
        );
      },
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
  bool shouldReclip(_LeftClipper oldClipper) =>
      oldClipper.fraction != fraction;
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
