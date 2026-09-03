import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';

import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../domain/status_projection.dart';
import '../theme.dart';
import '../tokens.dart';
import 'status.dart';

/// One icon per stage, so the pipeline is recognisable at a glance rather
/// than read word by word each time.
IconData iconForStage(StageKey key) => switch (key) {
      StageKey.rawMaterial => Ph.stack,
      StageKey.laserCutting => Ph.scissors,
      StageKey.weldingGrinding => Ph.flame,
      StageKey.painting => Ph.paintBrush,
      StageKey.qualityTesting => Ph.shieldCheck,
      StageKey.wiringAssembly => Ph.wrench,
      StageKey.packingLabelling => Ph.package,
      StageKey.readyForDispatch => Ph.warehouse,
      StageKey.dispatch => Ph.truck,
      StageKey.delivery => Ph.mapPin,
    };

/// The ten-step progress rail on Order Detail.
///
/// Every node is tappable and at least 48dp, the current stage is enlarged
/// and centred on open, and each node carries a status glyph rather than
/// relying on position alone.
class StageRail extends StatefulWidget {
  const StageRail({
    super.key,
    required this.order,
    required this.onSelect,
    this.selected,
  });

  final Order order;
  final ValueChanged<StageKey> onSelect;
  final StageKey? selected;

  @override
  State<StageRail> createState() => _StageRailState();
}

class _StageRailState extends State<StageRail> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreCurrent());
  }

  void _centreCurrent() {
    if (!_controller.hasClients) return;
    const nodeWidth = 76.0;
    final index = widget.order.currentStageKey.index;
    final target = (index * nodeWidth) - (_controller.position.viewportDimension / 2) + (nodeWidth / 2);
    _controller.jumpTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.order.currentStageKey;

    return Semantics(
      label: 'Production stages. Currently at '
          '${schemaFor(current).name}, '
          '${widget.order.completedStageCount} of 10 complete.',
      child: SizedBox(
        height: 92,
        child: ListView.builder(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          itemCount: StageKey.ordered.length,
          itemBuilder: (context, index) {
            final key = StageKey.ordered[index];
            final record = widget.order.stage(key);
            return _StageNode(
              schema: schemaFor(key),
              family: record.family,
              status: record.status,
              isCurrent: key == current,
              isSelected: key == widget.selected,
              isFirst: index == 0,
              isLast: index == StageKey.ordered.length - 1,
              onTap: () => widget.onSelect(key),
            );
          },
        ),
      ),
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.schema,
    required this.family,
    required this.status,
    required this.isCurrent,
    required this.isSelected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final StageSchema schema;
  final StatusFamily family;
  final String status;
  final bool isCurrent;
  final bool isSelected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visual = StatusVisual.of(context, family);
    final diameter = isCurrent ? 40.0 : 32.0;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${schema.name}, $status',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: Radii.controlAll,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Connectors are drawn behind the node so the rail reads
                    // as one continuous run.
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 2,
                              color: isFirst
                                  ? Colors.transparent
                                  : family == StatusFamily.notStarted
                                      ? c.hairline
                                      : c.accent,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 2,
                              color: isLast
                                  ? Colors.transparent
                                  : family == StatusFamily.completed
                                      ? c.accent
                                      : c.hairline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: Motion.resolve(context, Motion.quick),
                      curve: Motion.enter,
                      width: diameter,
                      height: diameter,
                      decoration: BoxDecoration(
                        color: c.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCurrent ? visual.text : c.hairlineStrong,
                          width: isCurrent ? 2 : 1.5,
                        ),
                      ),
                      child: Icon(
                        visual.icon,
                        size: isCurrent ? Sizes.iconMd : Sizes.iconSm,
                        color: visual.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                child: Text(
                  schema.shortName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.helper.copyWith(
                    fontSize: 11,
                    height: 1.25,
                    color: isCurrent ? c.ink : c.inkMuted,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
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

/// The tile grows with the reader's text size. A fixed box would clip its own
/// numbers at the larger settings, which is exactly when they matter most.
double stageTileHeightFor(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(Sizes.stageTileHeight);

double stageTileWidthFor(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(Sizes.stageTileWidth);

/// A tile on the pipeline board, standing for one stage across all orders.
///
/// It answers three things at a glance: how much work is here, how much of it
/// needs attention, and how long the oldest job has been waiting.
class StageTile extends StatelessWidget {
  const StageTile({
    super.key,
    required this.schema,
    required this.wip,
    required this.needingAttention,
    required this.oldest,
    required this.onTap,
  });

  final StageSchema schema;
  final int wip;
  final int needingAttention;

  /// Age of the oldest job at this stage.
  final Duration? oldest;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasProblem = needingAttention > 0;

    return Semantics(
      button: true,
      label: '${schema.name}, $wip in progress'
          '${hasProblem ? ', $needingAttention needing attention' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.tileAll,
        child: Container(
          width: stageTileWidthFor(context),
          height: stageTileHeightFor(context),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: Radii.tileAll,
            border: hasProblem
                ? Border(left: BorderSide(color: c.failedFill, width: 3))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    iconForStage(schema.key),
                    size: Sizes.iconSm,
                    color: c.inkMuted,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      schema.shortName,
                      style: AppType.helper.copyWith(
                        color: c.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '$wip',
                style: AppType.numeric(AppType.kpi).copyWith(
                  color: wip == 0 ? c.inkFaint : c.ink,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: Space.xs),
              if (hasProblem)
                Row(
                  children: [
                    Icon(
                      PhFill.warning,
                      size: 12,
                      color: c.failedText,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        '$needingAttention need attention',
                        style: AppType.helper.copyWith(
                          color: c.failedText,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              else if (oldest != null)
                Text(
                  'oldest ${formatDuration(oldest!)}',
                  style: AppType.helper
                      .copyWith(color: c.inkFaint, fontSize: 11),
                )
              else
                Text(
                  'nothing waiting',
                  style: AppType.helper
                      .copyWith(color: c.inkFaint, fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact duration, for elapsed time in queues and on tiles.
String formatDuration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) {
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${d.inHours}h' : '${d.inHours}h ${minutes}m';
  }
  final hours = d.inHours % 24;
  return hours == 0 ? '${d.inDays}d' : '${d.inDays}d ${hours}h';
}

/// A thin progress bar. The accompanying text carries the meaning; the bar
/// only supports it, so the information survives without colour.
class StageProgressBar extends StatelessWidget {
  const StageProgressBar({
    super.key,
    required this.completed,
    required this.total,
    this.showLabel = true,
  });

  final int completed;
  final int total;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fraction = total == 0 ? 0.0 : completed / total;

    return Semantics(
      label: '$completed of $total stages complete',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(height: 4, color: c.hairline),
                AnimatedFractionallySizedBox(
                  duration: Motion.resolve(context, Motion.standard),
                  curve: Motion.enter,
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(height: 4, color: c.accent),
                ),
              ],
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: Space.sm),
            Text(
              '$completed of $total stages complete',
              style: AppType.rowSecondary.copyWith(color: c.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
