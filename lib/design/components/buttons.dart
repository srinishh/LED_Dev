import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';

import '../theme.dart';
import '../tokens.dart';

enum ButtonKind { primary, secondary, tertiary, destructive }

/// The app's button.
///
/// A disabled button always states why. Silently inert controls are the main
/// reason operational software feels broken, so [disabledReason] is printed
/// directly beneath the control and read out to assistive technology.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = ButtonKind.primary,
    this.icon,
    this.disabledReason,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;

  /// One sentence naming the cause and the fix. Shown when the button is
  /// disabled.
  final String? disabledReason;

  /// True while an action is running. The button stays visible and keeps its
  /// width so the layout does not jump.
  final bool busy;

  final bool expand;

  bool get _enabled => onPressed != null && !busy;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget._enabled;

    final (background, foreground, border) = switch (widget.kind) {
      ButtonKind.primary => (
          enabled ? c.ink : c.raised,
          enabled ? c.onInk : c.inkDisabled,
          null,
        ),
      ButtonKind.secondary => (
          Colors.transparent,
          enabled ? c.ink : c.inkDisabled,
          enabled ? c.ink : c.hairline,
        ),
      ButtonKind.tertiary => (
          Colors.transparent,
          enabled ? c.accentText : c.inkDisabled,
          null,
        ),
      ButtonKind.destructive => (
          Colors.transparent,
          enabled ? c.failedText : c.inkDisabled,
          enabled ? c.failedFill.withValues(alpha: 0.4) : c.hairline,
        ),
    };

    final height =
        widget.kind == ButtonKind.tertiary ? Sizes.touchMin : Sizes.control;

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: enabled ? null : widget.disabledReason,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: AnimatedContainer(
          duration: Motion.resolve(context, Motion.instant),
          curve: Motion.enter,
          height: height,
          width: widget.expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: widget.kind == ButtonKind.tertiary ? Space.md : Space.xl,
          ),
          decoration: BoxDecoration(
            // Pressed state changes colour only. Moving the button would
            // shift everything around it.
            color: _pressed
                ? Color.alphaBlend(c.ink.withValues(alpha: 0.10), background)
                : background,
            borderRadius: Radii.controlAll,
            border: border == null ? null : Border.all(color: border, width: 1.5),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.busy) ...[
                SizedBox(
                  width: Sizes.iconMd,
                  height: Sizes.iconMd,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(foreground),
                  ),
                ),
                const SizedBox(width: Space.md),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, size: Sizes.iconMd, color: foreground),
                const SizedBox(width: Space.sm),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: AppType.button.copyWith(color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final reason = widget.disabledReason;
    if (enabled || reason == null || reason.isEmpty) return button;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Ph.info,
                size: Sizes.iconSm,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                reason,
                style: AppType.helper.copyWith(color: c.inkMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// An icon-only control. Always carries a semantics label, and always has a
/// full-size hit area even when the glyph is small.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.badgeCount,
    this.colour,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Shown as a count on the glyph, for unread alerts.
  final int? badgeCount;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    final count = badgeCount ?? 0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: count > 0 ? '$semanticLabel, $count unread' : semanticLabel,
      excludeSemantics: true,
      child: InkResponse(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onPressed!();
              }
            : null,
        radius: Sizes.touchMin / 2,
        child: SizedBox(
          width: Sizes.touchMin,
          height: Sizes.touchMin,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: Sizes.iconLg,
                color: enabled ? (colour ?? c.ink) : c.inkDisabled,
              ),
              if (count > 0)
                Positioned(
                  top: 8,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    decoration: BoxDecoration(
                      color: c.failedFill,
                      borderRadius: Radii.pillAll,
                      border: Border.all(color: c.surface, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: AppType.helper.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar that holds a screen's primary action. It keeps the action in the
/// same place on every screen, so the reach never has to be relearned.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({super.key, required this.primary, this.secondary});

  /// The screen's single primary action.
  final Widget primary;

  /// An optional lower-emphasis action, placed beneath the primary one.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.lg,
        bottom: Space.lg + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
        boxShadow: Elevation.stickyBar(c),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (secondary != null) ...[
            const SizedBox(height: Space.sm),
            secondary!,
          ],
        ],
      ),
    );
  }
}
