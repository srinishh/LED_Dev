import 'package:flutter/widgets.dart';

/// Design tokens: the single source of visual truth.
///
/// No literal colour, size, radius or duration may appear in feature code.
/// Everything resolves through this file, so a change here is a change
/// everywhere and both themes stay in lockstep.

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

/// Semantic colour set. Two instances exist: [AppColors.light] and
/// [AppColors.dark]. Feature code never names a hex value; it names a role.
@immutable
class AppColors {
  const AppColors({
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkDisabled,
    required this.accent,
    required this.accentText,
    required this.accentWash,
    required this.onInk,
    required this.hairline,
    required this.hairlineStrong,
    required this.raised,
    required this.scrim,
    required this.notStartedFill,
    required this.notStartedText,
    required this.inProcessFill,
    required this.inProcessText,
    required this.completedFill,
    required this.completedText,
    required this.onHoldFill,
    required this.onHoldText,
    required this.failedFill,
    required this.failedText,
  });

  final Color surface;
  final Color surfaceSunken;
  final Color surfaceRaised;

  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color inkFaint;
  final Color inkDisabled;

  /// Fills, strokes, progress and indicators only. At full saturation the
  /// brand teal is 2.0:1 on white, so it must never carry text. Text uses
  /// [accentText].
  final Color accent;
  final Color accentText;
  final Color accentWash;

  final Color onInk;
  final Color hairline;
  final Color hairlineStrong;
  final Color raised;
  final Color scrim;

  // Status families. Each is always paired with an icon and a text label in
  // the UI, so colour is never the sole carrier of meaning.
  final Color notStartedFill;
  final Color notStartedText;
  final Color inProcessFill;
  final Color inProcessText;
  final Color completedFill;
  final Color completedText;
  final Color onHoldFill;
  final Color onHoldText;
  final Color failedFill;
  final Color failedText;

  static const light = AppColors(
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF7F9FA),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF00132A),
    inkSecondary: Color(0xFF3A4A5C),
    inkMuted: Color(0xFF5C6B7A),
    inkFaint: Color(0xFF8A96A3),
    inkDisabled: Color(0xFFB4BCC4),
    accent: Color(0xFF05DBB2),
    accentText: Color(0xFF05A98A),
    accentWash: Color(0x1A05DBB2),
    onInk: Color(0xFFFFFFFF),
    hairline: Color(0x1A00132A),
    hairlineStrong: Color(0x3300132A),
    raised: Color(0x0800132A),
    scrim: Color(0x8000132A),
    notStartedFill: Color(0xFFE4E8EC),
    notStartedText: Color(0xFF5C6B7A),
    inProcessFill: Color(0xFF05DBB2),
    inProcessText: Color(0xFF05A98A),
    completedFill: Color(0xFF0E7C66),
    completedText: Color(0xFF0E7C66),
    onHoldFill: Color(0xFFF0A020),
    onHoldText: Color(0xFF8A5200),
    failedFill: Color(0xFFC02B2B),
    failedText: Color(0xFFA31F1F),
  );

  /// Night shift. Tokens are remapped, never inverted, and the teal is
  /// desaturated so it does not vibrate against the dark ground.
  static const dark = AppColors(
    surface: Color(0xFF00132A),
    surfaceSunken: Color(0xFF000B18),
    surfaceRaised: Color(0xFF0A2038),
    ink: Color(0xFFF2F6F9),
    inkSecondary: Color(0xFFB8C4D0),
    inkMuted: Color(0xFF8494A4),
    inkFaint: Color(0xFF6B7B8B),
    inkDisabled: Color(0xFF4A5A6A),
    accent: Color(0xFF2FE8C4),
    accentText: Color(0xFF4FEFD0),
    accentWash: Color(0x242FE8C4),
    onInk: Color(0xFF00132A),
    hairline: Color(0x1FFFFFFF),
    hairlineStrong: Color(0x3DFFFFFF),
    raised: Color(0x0FFFFFFF),
    scrim: Color(0xB3000B18),
    notStartedFill: Color(0xFF2A3A4A),
    notStartedText: Color(0xFF8494A4),
    inProcessFill: Color(0xFF2FE8C4),
    inProcessText: Color(0xFF4FEFD0),
    completedFill: Color(0xFF3DBFA0),
    completedText: Color(0xFF3DBFA0),
    onHoldFill: Color(0xFFF5B54A),
    onHoldText: Color(0xFFF5B54A),
    failedFill: Color(0xFFF06A6A),
    failedText: Color(0xFFF06A6A),
  );
}

// ---------------------------------------------------------------------------
// Spacing, radius, sizing
// ---------------------------------------------------------------------------

/// 8px-based spacing scale. Use these names, never a raw number.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;

  /// Horizontal screen inset.
  static const double gutter = 20;

  /// Vertical rhythm between major sections.
  static const double section = 32;
}

/// One radius system, applied consistently. Nothing oversized.
abstract final class Radii {
  static const Radius badge = Radius.circular(4);
  static const Radius control = Radius.circular(8);
  static const Radius tile = Radius.circular(12);
  static const Radius sheet = Radius.circular(20);
  static const Radius pill = Radius.circular(999);

  static const BorderRadius badgeAll = BorderRadius.all(badge);
  static const BorderRadius controlAll = BorderRadius.all(control);
  static const BorderRadius tileAll = BorderRadius.all(tile);
  static const BorderRadius pillAll = BorderRadius.all(pill);
  static const BorderRadius sheetTop =
      BorderRadius.only(topLeft: sheet, topRight: sheet);
}

/// Minimum interactive sizes. The floor is 48 everywhere; operational
/// surfaces used with gloves go to 56 and 72.
abstract final class Sizes {
  static const double touchMin = 48;
  static const double control = 56;
  static const double appBar = 56;
  static const double bottomNav = 56;
  static const double searchField = 48;
  static const double chip = 36;
  static const double badge = 24;
  static const double rowComfortable = 64;
  static const double rowOperational = 72;
  static const double offlineStrip = 36;
  static const double tableCell = 44;
  static const double stageTileWidth = 140;
  static const double stageTileHeight = 112;

  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;
}

/// Layered surfaces. Elevation is logical, not decorative: no glass, no
/// gradients, no shadow on a resting row.
abstract final class Elevation {
  static List<BoxShadow> stickyBar(AppColors c) => [
        BoxShadow(
          color: c.ink.withValues(alpha: 0.06),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> sheet(AppColors c) => [
        BoxShadow(
          color: c.ink.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, -8),
        ),
      ];
}

/// Paint order for overlapping surfaces.
abstract final class ZIndex {
  static const int content = 0;
  static const int stickyBar = 10;
  static const int fab = 20;
  static const int bottomNav = 40;
  static const int sheet = 100;
  static const int toast = 1000;
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Durations and curves. Exits run at roughly 65% of enters so the interface
/// feels responsive rather than sluggish.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasis = Duration(milliseconds: 280);
  static const Duration exit = Duration(milliseconds: 150);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve leave = Curves.easeInCubic;

  /// Per-item delay for staggered list entrances.
  static const Duration stagger = Duration(milliseconds: 35);
  static const int staggerCap = 6;

  /// Collapses a duration to zero when the platform asks for reduced motion.
  /// Call this rather than passing a Duration straight through.
  static Duration resolve(BuildContext context, Duration d) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? Duration.zero
          : d;
}

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

/// Row height preference. Operational surfaces assume gloves.
enum Density {
  comfortable(Sizes.rowComfortable),
  operational(Sizes.rowOperational);

  const Density(this.rowHeight);
  final double rowHeight;
}

/// The type scale. Every role is named; feature code never builds a TextStyle
/// from scratch.
abstract final class AppType {
  static const String family = 'Inter';

  /// Applied to all numeric data so columns align and figures do not jitter
  /// as values update.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle screenTitle = TextStyle(
    fontFamily: family,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.52,
    height: 1.20,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.78,
    height: 1.30,
  );

  static const TextStyle kpi = TextStyle(
    fontFamily: family,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.02,
    height: 1.10,
    fontFeatures: tabular,
  );

  static const TextStyle kpiCaption = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const TextStyle entityName = TextStyle(
    fontFamily: family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.17,
    height: 1.30,
  );

  static const TextStyle rowPrimary = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const TextStyle rowSecondary = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.40,
  );

  static const TextStyle fieldLabel = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.48,
    height: 1.30,
  );

  static const TextStyle fieldValue = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const TextStyle status = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.13,
    height: 1.25,
  );

  static const TextStyle button = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.16,
    height: 1.20,
  );

  static const TextStyle helper = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle tableCell = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.30,
    fontFeatures: tabular,
  );

  /// Numeric variant of any role, for quantities, identifiers and timestamps.
  static TextStyle numeric(TextStyle base) =>
      base.copyWith(fontFeatures: tabular);
}

/// Text scaling is honoured up to this factor without layout breaking. Rows
/// grow in height rather than truncating.
const double kMaxTextScale = 1.6;
