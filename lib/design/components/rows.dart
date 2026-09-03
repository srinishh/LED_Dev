import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';

import '../theme.dart';
import '../tokens.dart';

/// A section heading. Used only on screens carrying three or more distinct
/// modules, where it does real wayfinding work; a screen with one list does
/// not get a label just to look designed.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.count,
    this.padding,
  });

  final String title;
  final Widget? trailing;

  /// Shown beside the title. Answers "how many" before the user counts.
  final int? count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            Space.gutter,
            0,
            Space.gutter,
            Space.md,
          ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: AppType.sectionTitle.copyWith(color: c.inkFaint),
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: Space.sm),
            Text(
              '$count',
              style: AppType.numeric(AppType.sectionTitle)
                  .copyWith(color: c.inkMuted),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: Space.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The list row used across orders, queues and alerts.
///
/// Rows are separated by a single hairline rather than wrapped in a card, so
/// a dense list stays scannable. The whole row is the tap target.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.primary,
    this.secondary,
    this.leading,
    this.trailingTop,
    this.trailingBottom,
    this.statusRow,
    this.onTap,
    this.onLongPress,
    this.showChevron = true,
    this.emphasis = false,
    this.density,
  });

  /// The strongest label in the row, usually an order number.
  final String primary;

  /// Supporting metadata, one line.
  final String? secondary;

  final Widget? leading;

  /// Decision-relevant information on the right, such as a due date.
  final Widget? trailingTop;
  final Widget? trailingBottom;

  /// A status badge, placed below the metadata where it reads as a state
  /// rather than as decoration.
  final Widget? statusRow;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showChevron;

  /// Raises the row when it needs attention.
  final bool emphasis;

  final Density? density;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final minHeight = (density ?? context.density).rowHeight;

    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: leading!,
                ),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      primary,
                      style: AppType.numeric(AppType.entityName).copyWith(
                        color: c.ink,
                        fontWeight:
                            emphasis ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (secondary != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        secondary!,
                        style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (statusRow != null) ...[
                      const SizedBox(height: Space.sm),
                      statusRow!,
                    ],
                  ],
                ),
              ),
              if (trailingTop != null || trailingBottom != null) ...[
                const SizedBox(width: Space.md),
                // Capped so that at large text sizes the trailing metadata
                // cannot squeeze the primary content out of the row.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?trailingTop,
                      if (trailingBottom != null) ...[
                        const SizedBox(height: Space.xs),
                        trailingBottom!,
                      ],
                    ],
                  ),
                ),
              ],
              if (showChevron && onTap != null) ...[
                const SizedBox(width: Space.sm),
                Icon(
                  Ph.caretRight,
                  size: Sizes.iconMd,
                  color: c.inkFaint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The separator between rows. Inset to the left so it aligns under the text
/// column rather than cutting the full width.
class RowSeparator extends StatelessWidget {
  const RowSeparator({super.key, this.inset = Space.gutter});

  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: inset),
        child: Container(height: 1, color: context.colors.hairline),
      );
}

/// A label and value pair, as used on read-only detail screens.
class FieldReadout extends StatelessWidget {
  const FieldReadout({
    super.key,
    required this.label,
    required this.value,
    this.source,
    this.numeric = false,
  });

  final String label;
  final String value;

  /// Named when a value was carried forward, so the operator can see where it
  /// came from instead of wondering why it is fixed.
  final String? source;

  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: AppType.fieldLabel.copyWith(color: c.inkFaint),
              ),
              if (source != null) ...[
                const SizedBox(width: Space.sm),
                Text(
                  'from $source',
                  style: AppType.helper.copyWith(
                    color: c.inkFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            style: numeric
                ? AppType.numeric(AppType.fieldValue).copyWith(color: c.ink)
                : AppType.fieldValue.copyWith(color: c.ink),
          ),
        ],
      ),
    );
  }
}

/// Groups related fields under one heading, so a long form reads as a few
/// short ones.
class Fieldset extends StatelessWidget {
  const Fieldset({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          padding: const EdgeInsets.only(bottom: Space.md),
        ),
        ...children,
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

/// A section that opens on demand. Detail screens use these below the fold so
/// the opening viewport carries only what the user needs first.
class ExpandableSection extends StatefulWidget {
  const ExpandableSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _open = !_open);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: Sizes.touchMin),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.gutter,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: Motion.resolve(context, Motion.quick),
                    child: Icon(
                      Ph.caretRight,
                      size: Sizes.iconMd,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppType.rowPrimary.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: widget.child,
          ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: Motion.resolve(context, Motion.standard),
          sizeCurve: Motion.enter,
        ),
        const RowSeparator(inset: 0),
      ],
    );
  }
}
