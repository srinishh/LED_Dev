import 'package:flutter/widgets.dart';

/// The app's icon set: Phosphor, bundled as a font asset.
///
/// The glyphs are declared here rather than taken from a package, because the
/// published Flutter binding subclasses [IconData], which this version of
/// Flutter no longer permits. Declaring the codepoints directly keeps the same
/// icon family and costs one file instead of a dependency.
///
/// One family throughout, one stroke weight. Outline is the default; filled is
/// reserved for status, so fill itself carries meaning rather than decoration.

const String _regular = 'Phosphor';
const String _fill = 'PhosphorFill';

/// Outline icons, used for actions, navigation and objects.
abstract final class Ph {
  static const arrowDown =
      IconData(0xe03e, fontFamily: _regular);
  static const arrowLeft =
      IconData(0xe058, fontFamily: _regular);
  static const arrowUp =
      IconData(0xe08e, fontFamily: _regular);
  static const arrowsClockwise =
      IconData(0xe094, fontFamily: _regular);
  static const arrowsDownUp =
      IconData(0xe098, fontFamily: _regular);
  static const barcode =
      IconData(0xe0b8, fontFamily: _regular);
  static const bell =
      IconData(0xe0ce, fontFamily: _regular);
  static const calendarBlank =
      IconData(0xe10a, fontFamily: _regular);
  static const camera =
      IconData(0xe10e, fontFamily: _regular);
  static const caretDown =
      IconData(0xe136, fontFamily: _regular);
  static const caretRight =
      IconData(0xe13a, fontFamily: _regular);
  static const check =
      IconData(0xe182, fontFamily: _regular);
  static const checkCircle =
      IconData(0xe184, fontFamily: _regular);
  static const circle =
      IconData(0xe18a, fontFamily: _regular);
  static const circleDashed =
      IconData(0xe602, fontFamily: _regular);
  static const circleHalf =
      IconData(0xe18c, fontFamily: _regular);
  static const clock =
      IconData(0xe19a, fontFamily: _regular);
  static const clockCounterClockwise =
      IconData(0xe1a0, fontFamily: _regular);
  static const cloudSlash =
      IconData(0xe1b6, fontFamily: _regular);
  static const dotsThreeCircle =
      IconData(0xe200, fontFamily: _regular);
  static const dotsThreeVertical =
      IconData(0xe208, fontFamily: _regular);
  static const filePlus =
      IconData(0xe236, fontFamily: _regular);
  static const fileText =
      IconData(0xe23a, fontFamily: _regular);
  static const flame =
      IconData(0xe624, fontFamily: _regular);
  static const floppyDisk =
      IconData(0xe248, fontFamily: _regular);
  static const flowArrow =
      IconData(0xe6ec, fontFamily: _regular);
  static const funnelSimple =
      IconData(0xe268, fontFamily: _regular);
  static const identificationBadge =
      IconData(0xe6f6, fontFamily: _regular);
  static const info =
      IconData(0xe2ce, fontFamily: _regular);
  static const lock =
      IconData(0xe2fa, fontFamily: _regular);
  static const lockOpen =
      IconData(0xe306, fontFamily: _regular);
  static const magnifyingGlass =
      IconData(0xe30c, fontFamily: _regular);
  static const mapPin =
      IconData(0xe316, fontFamily: _regular);
  static const moon =
      IconData(0xe330, fontFamily: _regular);
  static const package =
      IconData(0xe390, fontFamily: _regular);
  static const paintBrush =
      IconData(0xe6f0, fontFamily: _regular);
  static const paperclip =
      IconData(0xe39a, fontFamily: _regular);
  static const pencilSimple =
      IconData(0xe3b4, fontFamily: _regular);
  static const playCircle =
      IconData(0xe3d2, fontFamily: _regular);
  static const plus =
      IconData(0xe3d4, fontFamily: _regular);
  static const rows =
      IconData(0xe5a2, fontFamily: _regular);
  static const scissors =
      IconData(0xeae0, fontFamily: _regular);
  static const shieldCheck =
      IconData(0xe40c, fontFamily: _regular);
  static const signature =
      IconData(0xebac, fontFamily: _regular);
  static const squaresFour =
      IconData(0xe464, fontFamily: _regular);
  static const stack =
      IconData(0xe466, fontFamily: _regular);
  static const sun =
      IconData(0xe472, fontFamily: _regular);
  static const tray =
      IconData(0xe4aa, fontFamily: _regular);
  static const truck =
      IconData(0xe4b4, fontFamily: _regular);
  static const warehouse =
      IconData(0xecd4, fontFamily: _regular);
  static const warning =
      IconData(0xe4e0, fontFamily: _regular);
  static const warningCircle =
      IconData(0xe4e2, fontFamily: _regular);
  static const wrench =
      IconData(0xe5d4, fontFamily: _regular);
  static const x =
      IconData(0xe4f6, fontFamily: _regular);
}

/// Filled icons. Reserved for status glyphs and for the few places where a
/// mark must read as a state rather than as something to tap.
abstract final class PhFill {
  static const checkCircle =
      IconData(0xe184, fontFamily: _fill);
  static const dotsThreeCircle =
      IconData(0xe200, fontFamily: _fill);
  static const flowArrow =
      IconData(0xe6ec, fontFamily: _fill);
  static const lock =
      IconData(0xe2fa, fontFamily: _fill);
  static const mapPin =
      IconData(0xe316, fontFamily: _fill);
  static const package =
      IconData(0xe390, fontFamily: _fill);
  static const pause =
      IconData(0xe39e, fontFamily: _fill);
  static const squaresFour =
      IconData(0xe464, fontFamily: _fill);
  static const warning =
      IconData(0xe4e0, fontFamily: _fill);
  static const warningCircle =
      IconData(0xe4e2, fontFamily: _fill);
}
