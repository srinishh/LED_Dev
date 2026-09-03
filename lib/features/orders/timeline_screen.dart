import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/shell.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';
import '../../state/async_view.dart';

void openTimeline(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TimelineScreen(orderId: orderId),
    ),
  );
}

/// The full history of one order.
///
/// Read top to bottom this answers every question the blueprint asks of the
/// record: when material arrived, when cutting started, who welded, when
/// painting finished, which checks passed or failed, when assembly and
/// packing were done, when the invoice was raised, and when the order was
/// dispatched and delivered.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  /// Empty means everything. Filtering here is about finding one event in a
  /// long run, not about hiding the record.
  final Set<_EventGroup> _groups = {};

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    final events = ref.watch(timelineProvider(widget.orderId));

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: NestedAppBar(
        title: 'Timeline',
        subtitle: order?.orderNo,
      ),
      body: events.view(
        loading: () => const SkeletonList(count: 7),
        error: (message, canRetry) => AppErrorState(
          message: message,
          onRetry: canRetry
              ? () => ref.invalidate(timelineProvider(widget.orderId))
              : null,
        ),
        denied: (message) => AppPermissionState(message: message),
        data: (all) {
          if (all.isEmpty) {
            return const AppEmptyState(
              icon: Ph.clockCounterClockwise,
              title: 'No events yet',
              body: 'The history builds itself as work is recorded against '
                  'this order.',
            );
          }

          final shown = _groups.isEmpty
              ? all.reversed.toList()
              : all.reversed
                  .where((e) => _groups.contains(_groupOf(e.type)))
                  .toList();

          return Column(
            children: [
              _GroupFilter(
                selected: _groups,
                onToggle: (group) => setState(() {
                  _groups.contains(group)
                      ? _groups.remove(group)
                      : _groups.add(group);
                }),
              ),
              Expanded(
                child: shown.isEmpty
                    ? AppEmptyState(
                        icon: Ph.funnelSimple,
                        title: 'No matching events',
                        body: 'No events of that kind were recorded for this '
                            'order.',
                        actionLabel: 'Show everything',
                        onAction: () => setState(_groups.clear),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        padding: const EdgeInsets.only(bottom: Space.xxxl),
                        itemBuilder: (context, index) => TimelineRow(
                          event: shown[index],
                          isLast: index == shown.length - 1,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Broad kinds of event, for filtering a long history.
enum _EventGroup {
  progress('Progress'),
  quality('Quality'),
  problems('Problems'),
  logistics('Logistics');

  const _EventGroup(this.label);
  final String label;
}

_EventGroup _groupOf(TimelineEventType type) => switch (type) {
      TimelineEventType.qualityRecorded => _EventGroup.quality,
      TimelineEventType.blocked ||
      TimelineEventType.overridden =>
        _EventGroup.problems,
      TimelineEventType.dispatched ||
      TimelineEventType.delivered =>
        _EventGroup.logistics,
      _ => _EventGroup.progress,
    };

class _GroupFilter extends StatelessWidget {
  const _GroupFilter({required this.selected, required this.onToggle});

  final Set<_EventGroup> selected;
  final ValueChanged<_EventGroup> onToggle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.md,
        ),
        child: Wrap(
          spacing: Space.sm,
          children: [
            for (final group in _EventGroup.values)
              AppChip(
                label: group.label,
                selected: selected.contains(group),
                onTap: () => onToggle(group),
              ),
          ],
        ),
      );
}

/// One event on the rail.
///
/// Failures, holds and overrides carry a coloured rule so they can be found
/// while scrolling a long history, rather than reading as ordinary progress.
class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.event,
    this.isLast = false,
    this.compact = false,
  });

  final TimelineEvent event;
  final bool isLast;

  /// The three-event summary on Order Detail drops the rail and the duration.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (colour, icon) = switch (event.severity) {
      EventSeverity.critical => (c.failedText, PhFill.warning),
      EventSeverity.warning => (c.onHoldText, PhFill.pause),
      EventSeverity.normal => (
          _isCompletion(event.type) ? c.completedText : c.inkMuted,
          _iconFor(event.type),
        ),
    };
    final notable = event.severity != EventSeverity.normal;

    return Semantics(
      label: '${event.summary}. ${event.actor}. ${_time(event.at)}.'
          '${event.detail == null ? '' : ' ${event.detail}'}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          Space.md,
          Space.gutter,
          Space.md,
        ),
        decoration: notable
            ? BoxDecoration(
                color: colour.withValues(alpha: 0.05),
                border: Border(left: BorderSide(color: colour, width: 4)),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Icon(icon, size: Sizes.iconMd, color: colour),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 32,
                        margin: const EdgeInsets.only(top: Space.xs),
                        color: c.hairline,
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 2, right: Space.md),
                child: Icon(icon, size: Sizes.iconMd, color: colour),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.summary,
                    style: AppType.rowPrimary.copyWith(
                      color: c.ink,
                      fontWeight:
                          notable ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${event.actor}. ${_time(event.at)}.',
                    style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                  ),
                  if (event.detail != null) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      event.detail!,
                      style: AppType.helper.copyWith(color: c.inkSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (event.stageKey != null && !compact) ...[
              const SizedBox(width: Space.sm),
              Text(
                schemaFor(event.stageKey!).shortName,
                style: AppType.helper.copyWith(color: c.inkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _isCompletion(TimelineEventType type) =>
      type == TimelineEventType.stageCompleted ||
      type == TimelineEventType.delivered;

  static IconData _iconFor(TimelineEventType type) => switch (type) {
        TimelineEventType.orderCreated => Ph.filePlus,
        TimelineEventType.stageStarted => Ph.playCircle,
        TimelineEventType.stageCompleted => PhFill.checkCircle,
        TimelineEventType.statusChanged => Ph.arrowsClockwise,
        TimelineEventType.qualityRecorded => Ph.shieldCheck,
        TimelineEventType.blocked => PhFill.lock,
        TimelineEventType.overridden => Ph.lockOpen,
        TimelineEventType.fieldEdited => Ph.pencilSimple,
        TimelineEventType.acknowledged => Ph.check,
        TimelineEventType.dispatched => Ph.truck,
        TimelineEventType.delivered => PhFill.mapPin,
      };

  static String _time(DateTime at) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.day} ${months[at.month - 1]}, $hh:$mm';
  }
}
