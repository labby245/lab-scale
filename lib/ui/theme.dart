/// LabScale dark theme — carries over the indigo-on-slate palette from the
/// original web UI so the desktop app feels like the same product.
library;

import 'package:flutter/material.dart';

class LabColors {
  LabColors._();

  static const background = Color(0xFF0A0C16);
  static const surface = Color(0xFF12162A);
  static const surfaceRaised = Color(0xFF161B33);
  static const border = Color(0x14FFFFFF);
  static const borderStrong = Color(0x26FFFFFF);

  static const primary = Color(0xFF6366F1);
  static const primaryBright = Color(0xFF818CF8);
  static const accent = Color(0xFF8B5CF6);

  static const textPrimary = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
  static const textFaint = Color(0xFF475569);

  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFF87171);
}

class LabSpacing {
  LabSpacing._();

  static const double cardRadius = 14;
  static const double controlRadius = 10;
  static const double cardPadding = 18;
  static const double gap = 14;
}

ThemeData buildLabScaleTheme() {
  const scheme = ColorScheme.dark(
    primary: LabColors.primary,
    secondary: LabColors.accent,
    surface: LabColors.surface,
    error: LabColors.danger,
    onPrimary: Colors.white,
    onSurface: LabColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LabColors.background,
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: LabColors.textPrimary,
      ),
      bodyMedium: TextStyle(fontSize: 13.5, color: LabColors.textSecondary),
      bodySmall: TextStyle(fontSize: 12, color: LabColors.textMuted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    dividerColor: LabColors.border,
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(LabColors.surfaceRaised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
          ),
        ),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: LabColors.primary,
      inactiveTrackColor: LabColors.borderStrong,
      thumbColor: LabColors.primaryBright,
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : LabColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? LabColors.primary
            : LabColors.borderStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: LabColors.surfaceRaised,
      contentTextStyle: const TextStyle(color: LabColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LabSpacing.controlRadius),
      ),
    ),
  );
}

/// The rounded panel every section of the UI sits inside.
class LabCard extends StatelessWidget {
  const LabCard({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(LabSpacing.cardPadding),
      decoration: BoxDecoration(
        color: LabColors.surface,
        borderRadius: BorderRadius.circular(LabSpacing.cardRadius),
        border: Border.all(color: LabColors.border),
      ),
      child: child,
    );
  }
}

/// Numbered section heading, e.g. "① Pilih File".
class LabCardTitle extends StatelessWidget {
  const LabCardTitle({super.key, required this.badge, required this.title, this.trailing});

  final String badge;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LabSpacing.gap),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LabColors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: LabColors.primaryBright,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}
