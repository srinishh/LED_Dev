import 'package:flutter/material.dart';

import 'tokens.dart';

/// Carries the resolved token set down the tree. Widgets read tokens through
/// `context.colors` / `context.density` rather than importing a palette.
class AppTheme extends InheritedWidget {
  const AppTheme({
    super.key,
    required this.colors,
    required this.density,
    required this.brightness,
    required super.child,
  });

  final AppColors colors;
  final Density density;
  final Brightness brightness;

  static AppTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(theme != null, 'AppTheme is missing from the widget tree.');
    return theme!;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) =>
      colors != oldWidget.colors ||
      density != oldWidget.density ||
      brightness != oldWidget.brightness;
}

extension AppThemeContext on BuildContext {
  AppColors get colors => AppTheme.of(this).colors;
  Density get density => AppTheme.of(this).density;
  bool get isDark => AppTheme.of(this).brightness == Brightness.dark;

  /// Row height for list surfaces, following the active density.
  double get rowHeight => AppTheme.of(this).density.rowHeight;

  /// True when the platform has asked for reduced motion.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

/// Builds the Material theme from the token set. Material is used for its
/// mechanics (ink, focus, semantics, scrolling); the visual language comes
/// entirely from tokens.
ThemeData buildTheme(AppColors c, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.ink,
    onPrimary: c.onInk,
    secondary: c.accent,
    onSecondary: c.ink,
    error: c.failedFill,
    onError: c.surface,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surfaceSunken,
    outline: c.hairlineStrong,
    outlineVariant: c.hairline,
    scrim: c.scrim,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.surface,
    fontFamily: AppType.family,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(
      color: c.hairline,
      thickness: 1,
      space: 1,
    ),
    // Focus is a visible 2px accent ring, never removed.
    focusColor: c.accent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accentText,
      selectionColor: c.accentWash,
      selectionHandleColor: c.accentText,
    ),
    textTheme: TextTheme(
      displayLarge: AppType.kpi.copyWith(color: c.ink),
      headlineLarge: AppType.screenTitle.copyWith(color: c.ink),
      titleLarge: AppType.entityName.copyWith(color: c.ink),
      titleSmall: AppType.sectionTitle.copyWith(color: c.inkFaint),
      bodyLarge: AppType.rowPrimary.copyWith(color: c.ink),
      bodyMedium: AppType.rowSecondary.copyWith(color: c.inkMuted),
      labelLarge: AppType.button.copyWith(color: c.ink),
      labelSmall: AppType.fieldLabel.copyWith(color: c.inkFaint),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: AppType.rowPrimary.copyWith(color: c.onInk),
      actionTextColor: c.accentText,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: Radii.controlAll),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      showDragHandle: false,
      modalBarrierColor: c.scrim,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: Radii.controlAll),
    ),
  );
}

/// Clamps text scaling to the supported range. Beyond [kMaxTextScale] layouts
/// stop being verifiable, so the app caps rather than breaks.
Widget withClampedTextScale(BuildContext context, Widget child) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(
      textScaler: media.textScaler.clamp(
        minScaleFactor: 1.0,
        maxScaleFactor: kMaxTextScale,
      ),
    ),
    child: child,
  );
}
