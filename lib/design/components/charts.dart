import 'package:flutter/material.dart';

import '../icons.dart';

import '../theme.dart';
import '../tokens.dart';

/// A headline figure.
///
/// Rendered as bare type on the page rather than inside a card, so that a row
/// of them reads as a hierarchy of numbers rather than a grid of boxes. The
/// change figure carries the trend in words; the sparkline only supports it.
class KpiBlock extends StatelessWidget {
  const KpiBlock({
    super.key,
    required this.value,
    required this.caption,
    this.delta,
    this.series = const [],
    this.onTap,
  });

  final String value;
  final String caption;

  /// Change against the previous period. Positive is not automatically good,
  /// so the caller decides the wording.
  final KpiDelta? delta;

  /// Seven points, oldest first. Fewer than four points renders no line,
  /// because a trend cannot be read from two.
  final List<double> series;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      label: '$caption: $value'
          '${delta == null ? '' : ', ${delta!.semanticLabel}'}',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.controlAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppType.kpi.copyWith(color: c.ink),
              ),
              const SizedBox(height: Space.xs),
              Text(
                caption,
                style: AppType.kpiCaption.copyWith(color: c.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (series.length >= 4 || delta != null) ...[
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    if (series.length >= 4)
                      Sparkline(values: series, width: 44, height: 18),
                    if (delta != null) ...[
                      if (series.length >= 4) const SizedBox(width: Space.sm),
                      Flexible(child: _DeltaLabel(delta: delta!)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A period-on-period change.
class KpiDelta {
  const KpiDelta({
    required this.amount,
    required this.period,
    this.higherIsBetter = true,
  });

  final int amount;
  final String period;
  final bool higherIsBetter;

  bool get isFlat => amount == 0;
  bool get isGood => higherIsBetter ? amount > 0 : amount < 0;

  String get label =>
      isFlat ? 'no change' : '${amount > 0 ? '+' : ''}$amount';

  String get semanticLabel => isFlat
      ? 'no change against $period'
      : '${amount.abs()} ${amount > 0 ? 'more' : 'fewer'} than $period';
}

class _DeltaLabel extends StatelessWidget {
  const _DeltaLabel({required this.delta});

  final KpiDelta delta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = delta.isFlat
        ? c.inkMuted
        : delta.isGood
            ? c.completedText
            : c.onHoldText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!delta.isFlat)
          Icon(
            delta.amount > 0
                ? Ph.arrowUp
                : Ph.arrowDown,
            size: 12,
            color: colour,
          ),
        if (!delta.isFlat) const SizedBox(width: 2),
        Flexible(
          child: Text(
            delta.label,
            style: AppType.numeric(AppType.helper).copyWith(
              color: colour,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A small trend line. Deliberately unlabelled: it supports the number beside
/// it rather than standing alone, and the delta text carries the meaning for
/// anyone who cannot read the line.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.width = 44,
    this.height = 18,
  });

  final List<double> values;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 4) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(width, height),
          painter: _SparklinePainter(
            values: values,
            colour: context.colors.accent,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.colour});

  final List<double> values;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 0.001 ? 1.0 : max - min;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - ((values[i] - min) / range) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

/// One row of the work-in-progress chart.
class BarDatum {
  const BarDatum({
    required this.label,
    required this.value,
    required this.semanticLabel,
    this.flagged = false,
    this.onTap,
  });

  final String label;
  final int value;
  final String semanticLabel;

  /// Marks a category that contains a problem. Shown as a glyph, not only as
  /// a colour change.
  final bool flagged;

  final VoidCallback? onTap;
}

/// A horizontal bar chart answering "where is work piling up".
///
/// Horizontal because the categories are long stage names that would truncate
/// on a vertical axis, and because ten categories read comfortably as rows.
/// Every bar is labelled with its own value, so no axis or legend is needed
/// and the chart doubles as its own data table.
class HorizontalBarChart extends StatelessWidget {
  const HorizontalBarChart({
    super.key,
    required this.data,
    this.maxVisible,
    this.emptyMessage = 'Nothing in progress.',
  });

  final List<BarDatum> data;

  /// Rows shown before the list collapses behind a disclosure.
  final int? maxVisible;

  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Text(
          emptyMessage,
          style: AppType.rowSecondary.copyWith(color: c.inkMuted),
        ),
      );
    }

    final peak = data.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    final visible = maxVisible == null
        ? data
        : data.take(maxVisible!).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final datum in visible)
          _BarRow(datum: datum, peak: peak == 0 ? 1 : peak),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.datum, required this.peak});

  final BarDatum datum;
  final int peak;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fraction = datum.value / peak;

    return Semantics(
      label: datum.semanticLabel,
      button: datum.onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: datum.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.tableCell),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  datum.label,
                  style: AppType.rowSecondary.copyWith(color: c.inkSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(
                    children: [
                      Container(height: 8, color: c.raised),
                      AnimatedFractionallySizedBox(
                        duration: Motion.resolve(context, Motion.standard),
                        curve: Motion.enter,
                        widthFactor: fraction.clamp(0.0, 1.0),
                        child: Container(
                          height: 8,
                          color: datum.value == 0 ? c.hairline : c.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (datum.flagged) ...[
                const SizedBox(width: Space.sm),
                Icon(
                  PhFill.warning,
                  size: Sizes.iconSm,
                  color: c.failedText,
                ),
              ],
              const SizedBox(width: Space.md),
              SizedBox(
                width: 28,
                child: Text(
                  '${datum.value}',
                  textAlign: TextAlign.end,
                  style: AppType.numeric(AppType.rowPrimary).copyWith(
                    color: datum.value == 0 ? c.inkFaint : c.ink,
                    fontWeight: FontWeight.w600,
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

/// Compares actual time in a stage against the planned time, answering
/// "which stage is slowing this order down".
class DurationComparison extends StatelessWidget {
  const DurationComparison({
    super.key,
    required this.rows,
  });

  final List<DurationRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Text(
          'No stage has been completed yet, so there is nothing to compare.',
          style: AppType.rowSecondary.copyWith(color: c.inkMuted),
        ),
      );
    }

    final peak = rows
        .map((r) => r.actualHours > r.planHours ? r.actualHours : r.planHours)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        for (final row in rows) _DurationRow(row: row, peak: peak),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            0,
          ),
          child: Row(
            children: [
              Container(width: 12, height: 8, color: c.accent),
              const SizedBox(width: Space.sm),
              Text(
                'actual',
                style: AppType.helper.copyWith(color: c.inkMuted),
              ),
              const SizedBox(width: Space.lg),
              Container(width: 12, height: 8, color: c.hairlineStrong),
              const SizedBox(width: Space.sm),
              Text('plan', style: AppType.helper.copyWith(color: c.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class DurationRow {
  const DurationRow({
    required this.label,
    required this.actualHours,
    required this.planHours,
  });

  final String label;
  final double actualHours;
  final double planHours;

  bool get isOverPlan => actualHours > planHours;
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({required this.row, required this.peak});

  final DurationRow row;
  final double peak;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final safePeak = peak <= 0 ? 1.0 : peak;

    return Semantics(
      label: '${row.label}: took ${row.actualHours.round()} hours against a '
          'plan of ${row.planHours.round()}'
          '${row.isOverPlan ? ', over plan' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: AppType.rowSecondary.copyWith(color: c.inkSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (row.isOverPlan) ...[
                  Icon(
                    Ph.arrowUp,
                    size: 12,
                    color: c.onHoldText,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(
                  '${row.actualHours.round()}h',
                  style: AppType.numeric(AppType.rowSecondary).copyWith(
                    color: row.isOverPlan ? c.onHoldText : c.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Stack(
              children: [
                // Plan sits behind as a reference track.
                FractionallySizedBox(
                  widthFactor: (row.planHours / safePeak).clamp(0.0, 1.0),
                  child: Container(height: 8, color: c.hairlineStrong),
                ),
                FractionallySizedBox(
                  widthFactor: (row.actualHours / safePeak).clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    color: row.isOverPlan ? c.onHoldFill : c.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
