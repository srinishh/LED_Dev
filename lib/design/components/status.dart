import 'package:flutter/material.dart';

import '../icons.dart';

import '../../domain/status_projection.dart';
import '../theme.dart';
import '../tokens.dart';

/// How a status family looks. Each family carries a colour, an icon and a
/// distinct shape, so meaning survives glare, monochrome printing and
/// colour blindness. Nothing in this app conveys state by colour alone.
class StatusVisual {
  const StatusVisual({
    required this.family,
    required this.icon,
    required this.fill,
    required this.text,
    required this.shape,
  });

  final StatusFamily family;
  final IconData icon;
  final Color fill;
  final Color text;

  /// Silhouette used in the matrix, where cells are too small for a label.
  final StatusShape shape;

  static StatusVisual of(BuildContext context, StatusFamily family) {
    final c = context.colors;
    return switch (family) {
      StatusFamily.notStarted => StatusVisual(
          family: family,
          icon: Ph.circleDashed,
          fill: c.notStartedFill,
          text: c.notStartedText,
          shape: StatusShape.hollowCircle,
        ),
      StatusFamily.inProcess => StatusVisual(
          family: family,
          icon: Ph.circleHalf,
          fill: c.inProcessFill,
          text: c.inProcessText,
          shape: StatusShape.halfCircle,
        ),
      StatusFamily.completed => StatusVisual(
          family: family,
          icon: PhFill.checkCircle,
          fill: c.completedFill,
          text: c.completedText,
          shape: StatusShape.filledCircle,
        ),
      StatusFamily.onHold => StatusVisual(
          family: family,
          icon: PhFill.pause,
          fill: c.onHoldFill,
          text: c.onHoldText,
          shape: StatusShape.square,
        ),
      StatusFamily.failed => StatusVisual(
          family: family,
          icon: PhFill.warning,
          fill: c.failedFill,
          text: c.failedText,
          shape: StatusShape.triangle,
        ),
    };
  }
}

enum StatusShape { hollowCircle, halfCircle, filledCircle, square, triangle }

/// Status as a labelled badge: icon, then the stage's own status wording.
///
/// The label is always the exact status the blueprint defines for that stage,
/// never a normalised substitute, so operators see the vocabulary they use on
/// the floor.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.family,
    required this.label,
    this.emphasis = StatusEmphasis.normal,
    this.maxLines = 1,
  });

  final StatusFamily family;
  final String label;
  final StatusEmphasis emphasis;

  /// Where a badge sits in a narrow row, letting it run to a second line is
  /// better than clipping a status the reader needs to act on.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final visual = StatusVisual.of(context, family);
    final strong = emphasis == StatusEmphasis.strong;

    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.resolve(context, Motion.quick),
        curve: Motion.enter,
        // Never narrower than the icon plus its padding, so a tight parent
        // clips the label rather than crushing the whole badge.
        constraints: const BoxConstraints(
          minHeight: Sizes.badge,
          minWidth: Sizes.iconSm + Space.sm * 2,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        decoration: BoxDecoration(
          color: visual.fill.withValues(alpha: strong ? 0.20 : 0.12),
          borderRadius: Radii.badgeAll,
          border: strong
              ? Border.all(color: visual.fill.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(visual.icon, size: Sizes.iconSm, color: visual.text),
            const SizedBox(width: Space.xs + 2),
            Flexible(
              child: Text(
                label,
                style: AppType.status.copyWith(color: visual.text),
                overflow: TextOverflow.ellipsis,
                maxLines: maxLines,
                softWrap: maxLines > 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusEmphasis { normal, strong }

/// The compact form used as a leading marker on list rows, where the status
/// wording already appears elsewhere in the row.
class StatusGlyph extends StatelessWidget {
  const StatusGlyph({
    super.key,
    required this.family,
    required this.label,
    this.size = Sizes.iconMd,
  });

  final StatusFamily family;

  /// Read out by assistive technology, since the glyph carries no text.
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = StatusVisual.of(context, family);
    return Semantics(
      label: label,
      child: Icon(visual.icon, size: size, color: visual.text),
    );
  }
}

/// A shape-coded cell marker for the order and stage matrix, where there is
/// no room for a label. The shape differs per family so the grid stays
/// readable without relying on hue.
class StatusCellMark extends StatelessWidget {
  const StatusCellMark({
    super.key,
    required this.family,
    required this.semanticLabel,
    this.size = 12,
  });

  final StatusFamily family;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = StatusVisual.of(context, family);
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: Sizes.tableCell,
        height: Sizes.tableCell,
        child: Center(
          child: CustomPaint(
            size: Size.square(size),
            painter: _ShapePainter(shape: visual.shape, colour: visual.text),
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter({required this.shape, required this.colour});

  final StatusShape shape;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = colour
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    final centre = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    switch (shape) {
      case StatusShape.hollowCircle:
        canvas.drawCircle(centre, r - 0.75, stroke);

      case StatusShape.halfCircle:
        canvas.drawCircle(centre, r - 0.75, stroke);
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: r - 0.75),
          -1.5708, // twelve o'clock
          3.1416, // sweep the right half
          true,
          fill,
        );

      case StatusShape.filledCircle:
        canvas.drawCircle(centre, r, fill);

      case StatusShape.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: centre,
              width: size.width * 0.86,
              height: size.height * 0.86,
            ),
            const Radius.circular(1.5),
          ),
          fill,
        );

      case StatusShape.triangle:
        final path = Path()
          ..moveTo(centre.dx, centre.dy - r)
          ..lineTo(centre.dx + r, centre.dy + r * 0.8)
          ..lineTo(centre.dx - r, centre.dy + r * 0.8)
          ..close();
        canvas.drawPath(path, fill);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.shape != shape || old.colour != colour;
}

/// The five-item key for the matrix. It sits directly beneath the table
/// rather than below the scroll fold, because a shape code is useless if the
/// reader has to hunt for its meaning.
class StatusLegend extends StatelessWidget {
  const StatusLegend({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.md,
          ),
      child: Wrap(
        spacing: Space.lg,
        runSpacing: Space.sm,
        children: [
          for (final family in StatusFamily.values)
            _LegendItem(family: family),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.family});

  final StatusFamily family;

  @override
  Widget build(BuildContext context) {
    final visual = StatusVisual.of(context, family);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size.square(10),
          painter: _ShapePainter(shape: visual.shape, colour: visual.text),
        ),
        const SizedBox(width: Space.sm),
        Text(
          family.label,
          style: AppType.helper.copyWith(color: context.colors.inkMuted),
        ),
      ],
    );
  }
}

/// Marks a row whose change has not yet reached the server. Offline is a
/// normal working mode here, so this reads as information rather than as an
/// error.
class PendingSyncMark extends StatelessWidget {
  const PendingSyncMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Change waiting to sync',
      child: Icon(
        Ph.cloudSlash,
        size: Sizes.iconSm,
        color: context.colors.inkMuted,
      ),
    );
  }
}
