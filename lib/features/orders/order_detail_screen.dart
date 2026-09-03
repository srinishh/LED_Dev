import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/buttons.dart';
import '../../design/components/charts.dart';
import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/components/stage.dart';
import '../../design/components/status.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/rules.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';
import '../stages/quality_screen.dart';
import '../stages/stage_detail_screen.dart';
import '../stages/stage_execution_screen.dart';
import 'jobsheet_screen.dart';
import 'timeline_screen.dart';
import '../../state/async_view.dart';

/// Opens an order, building a real back stack so a deep link or a
/// notification never strands the user.
void openOrder(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OrderDetailScreen(orderId: orderId),
    ),
  );
}

/// Everything known about one order, ordered by what the reader needs first.
///
/// The opening viewport carries identity, current status, anything blocking
/// it, and the one action worth taking. Metrics, history and reference data
/// sit below, collapsed, because they answer later questions.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    final async = ref.watch(ordersProvider);

    if (order == null) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: const NestedAppBar(title: 'Order'),
        body: async.isLoading
            ? const _DetailSkeleton()
            : AppErrorState(
                message: 'This order could not be found. It may have been '
                    'cancelled.',
                onRetry: () => ref.invalidate(ordersProvider),
              ),
      );
    }

    return _OrderDetailBody(order: order);
  }
}

class _OrderDetailBody extends ConsumerWidget {
  const _OrderDetailBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final blockers = ref.watch(advanceBlockersProvider(order.id));
    final stage = order.currentStage;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: c.surface,
      appBar: NestedAppBar(
        title: order.orderNo,
        actions: [
          AppIconButton(
            icon: Ph.dotsThreeVertical,
            semanticLabel: 'More actions',
            onPressed: () => _showActions(context, ref, order, user),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          // 1. Identity.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.product,
                  style: AppType.screenTitle.copyWith(color: c.ink),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '${order.customer}. ${order.quantity} pcs. '
                  '${order.priority.label} priority.',
                  style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),

          // 2. Current status, and 3. what is critical about it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(
                  family: stage.family,
                  label: order.isFinished
                      ? 'Order complete'
                      : '${stage.schema.name}. ${stage.status}',
                  emphasis: stage.needsAttention
                      ? StatusEmphasis.strong
                      : StatusEmphasis.normal,
                ),
                const SizedBox(height: Space.lg),
                StageProgressBar(
                  completed: order.completedStageCount,
                  total: StageKey.ordered.length,
                ),
                const SizedBox(height: Space.md),
                _DueLine(order: order, now: now),
                if (Rules.isBlockedByQuality(order)) ...[
                  const SizedBox(height: Space.lg),
                  BlockerBanner(
                    reason: Rules.qualityGate(order).reason ??
                        'A quality check has not passed.',
                    onTap: () => openQuality(context, order.id),
                  ),
                ] else if (order.notes != null && stage.needsAttention) ...[
                  const SizedBox(height: Space.lg),
                  AppBanner(
                    tone: BannerTone.warning,
                    title: stage.status,
                    detail: order.notes,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.xl),

          // 4. The action worth taking, and only that one.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: _PrimaryActions(
              order: order,
              user: user,
              blockers: blockers,
            ),
          ),
          const SizedBox(height: Space.section),

          // 5. Where the order is in the run.
          const SectionHeader(title: 'Stages'),
          StageRail(
            order: order,
            onSelect: (key) => openStageDetail(context, order.id, key),
          ),
          const SizedBox(height: Space.section),

          // 6. What has just happened.
          SectionHeader(
            title: 'Recent activity',
            trailing: _LinkAction(
              label: 'Full timeline',
              onTap: () => openTimeline(context, order.id),
            ),
          ),
          _RecentActivity(orderId: order.id),
          const SizedBox(height: Space.section),

          // 7 and 8. Everything that answers a later question.
          ExpandableSection(
            title: 'Time in each stage',
            subtitle: 'vs plan',
            child: DurationComparison(rows: _durations(order, now)),
          ),
          ExpandableSection(
            title: 'Order information',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldReadout(
                    label: 'Order number',
                    value: order.orderNo,
                    numeric: true,
                  ),
                  FieldReadout(label: 'Customer', value: order.customer),
                  FieldReadout(label: 'Product', value: order.product),
                  FieldReadout(
                    label: 'Quantity',
                    value: '${order.quantity} pcs',
                    numeric: true,
                  ),
                  FieldReadout(
                    label: 'Received',
                    value: _date(order.receivedAt),
                  ),
                  FieldReadout(label: 'Due', value: _date(order.dueAt)),
                  FieldReadout(
                    label: 'Purchase order',
                    value: order
                            .stage(StageKey.rawMaterial)
                            .values['purchaseOrderNumber'] as String? ??
                        'Not recorded',
                  ),
                  FieldReadout(
                    label: 'Supplier',
                    value: order.stage(StageKey.rawMaterial).values['supplier']
                            as String? ??
                        'Not recorded',
                  ),
                  if (order.notes != null)
                    FieldReadout(label: 'Remarks', value: order.notes!),
                ],
              ),
            ),
          ),
          ExpandableSection(
            title: 'Quality checklist',
            subtitle: '${order.qualityTests.length - order.blockingTests.length}'
                ' of ${order.qualityTests.length} passed',
            child: Column(
              children: [
                for (final test in order.qualityTests)
                  AppListRow(
                    primary: test.name,
                    secondary: test.testedBy == null
                        ? 'Not recorded'
                        : '${test.testedBy}. ${_date(test.testedAt!)}.',
                    leading: StatusGlyph(
                      family: test.family,
                      label: test.status.label,
                    ),
                    trailingTop: StatusBadge(
                      family: test.family,
                      label: test.status.label,
                    ),
                    showChevron: false,
                    onTap: () => openQuality(context, order.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<DurationRow> _durations(Order order, DateTime now) {
    // A rough plan of one working day per stage, so the comparison shows
    // where an order actually lost time.
    const plannedHours = 8.0;
    return [
      for (final key in StageKey.ordered)
        if (order.stage(key).elapsedAt(now) case final elapsed?)
          DurationRow(
            label: schemaFor(key).name,
            actualHours: elapsed.inMinutes / 60,
            planHours: plannedHours,
          ),
    ];
  }

  void _showActions(
    BuildContext context,
    WidgetRef ref,
    Order order,
    User user,
  ) {
    final canOverride = Rules.canOverrideQualityGate(user).allowed &&
        Rules.isBlockedByQuality(order);

    showAppSheet<void>(
      context,
      builder: (sheetContext) => AppBottomSheet(
        title: order.orderNo,
        subtitle: order.product,
        child: Column(
          children: [
            if (user.isManager)
              _ActionRow(
                icon: Ph.pencilSimple,
                label: 'Edit jobsheet',
                detail: 'Customer, product, quantity, due date, priority.',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openEditJobsheet(context, order.id);
                },
              ),
            _ActionRow(
              icon: Ph.clockCounterClockwise,
              label: 'Production timeline',
              onTap: () {
                Navigator.of(sheetContext).pop();
                openTimeline(context, order.id);
              },
            ),
            _ActionRow(
              icon: Ph.shieldCheck,
              label: 'Quality checklist',
              onTap: () {
                Navigator.of(sheetContext).pop();
                openQuality(context, order.id);
              },
            ),
            if (canOverride)
              _ActionRow(
                icon: Ph.lockOpen,
                label: 'Release past the quality gate',
                detail: 'Manager only. Requires a reason and is recorded.',
                destructive: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmOverride(context, ref, order);
                },
              ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmOverride(
    BuildContext context,
    WidgetRef ref,
    Order order,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Release past the quality gate',
        subtitle: 'This is recorded against your name on the timeline.',
        action: AppButton(
          label: 'Release the order',
          kind: ButtonKind.destructive,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: AppTextField(
            label: 'Reason',
            controller: controller,
            required: true,
            maxLines: 3,
            helper: 'Say why the order may proceed despite the failed check.',
          ),
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final reason = controller.text.trim();
    if (reason.isEmpty) return;

    try {
      await ref
          .read(orderActionsProvider)
          .advance(order.id, overrideReason: reason);
      if (context.mounted) {
        showAppToast(context, message: 'Order released and recorded.');
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          message: '$e',
          tone: BannerTone.critical,
        );
      }
    }
  }
}

/// The single primary action, plus advancement when it is available.
class _PrimaryActions extends ConsumerStatefulWidget {
  const _PrimaryActions({
    required this.order,
    required this.user,
    required this.blockers,
  });

  final Order order;
  final User user;
  final RuleResult blockers;

  @override
  ConsumerState<_PrimaryActions> createState() => _PrimaryActionsState();
}

class _PrimaryActionsState extends ConsumerState<_PrimaryActions> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final stage = order.currentStage;

    if (order.isFinished) {
      return const AppBanner(
        tone: BannerTone.positive,
        title: 'Order complete',
        detail: 'Delivered and closed. Nothing further is needed.',
      );
    }

    final isQuality = order.currentStageKey == StageKey.qualityTesting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: isQuality
              ? 'Open quality checklist'
              : 'Open ${stage.schema.name}',
          icon: iconForStage(order.currentStageKey),
          onPressed: () => isQuality
              ? openQuality(context, order.id)
              : openStageExecution(context, order.id, order.currentStageKey),
        ),
        const SizedBox(height: Space.sm),
        AppButton(
          label: 'Advance to ${_nextName(order)}',
          kind: ButtonKind.tertiary,
          busy: _busy,
          onPressed: widget.blockers.allowed ? _advance : null,
          disabledReason: widget.blockers.reason,
        ),
      ],
    );
  }

  String _nextName(Order order) {
    final next = order.currentStageKey.next;
    return next == null ? 'completion' : schemaFor(next).name;
  }

  Future<void> _advance() async {
    setState(() => _busy = true);
    try {
      await ref.read(orderActionsProvider).advance(widget.order.id);
      if (mounted) {
        showAppToast(
          context,
          message: '${widget.order.currentStage.schema.name} completed.',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: '$e', tone: BannerTone.critical);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DueLine extends StatelessWidget {
  const _DueLine({required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (order.isFinished) {
      return Text(
        'Delivered on ${_date(order.dueAt)}',
        style: AppType.rowSecondary.copyWith(color: c.inkMuted),
      );
    }

    final days = order.daysUntilDue(now);
    final overdue = order.isOverdue(now);

    return Row(
      children: [
        Icon(
          overdue ? PhFill.warning : Ph.calendarBlank,
          size: Sizes.iconSm,
          color: overdue ? c.failedText : c.inkMuted,
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            overdue
                ? 'Due ${_date(order.dueAt)}. Late by ${days.abs()} '
                    'day${days.abs() == 1 ? '' : 's'}.'
                : 'Due ${_date(order.dueAt)}. '
                    '${days == 0 ? 'Today' : '$days day${days == 1 ? '' : 's'} left'}.',
            style: AppType.rowSecondary.copyWith(
              color: overdue ? c.failedText : c.inkSecondary,
              fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(timelineProvider(orderId));

    return events.view(
      loading: () => const SkeletonList(count: 3),
      error: (message, canRetry) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Text(
          'Activity could not be loaded.',
          style: AppType.rowSecondary
              .copyWith(color: context.colors.inkMuted),
        ),
      ),
      data: (all) {
        if (all.isEmpty) {
          return const AppEmptyState(
            title: 'No activity yet',
            body: 'Updates appear here as the order moves through the plant.',
          );
        }
        final recent = all.reversed.take(3).toList();
        return Column(
          children: [
            for (final event in recent) ...[
              TimelineRow(event: event, compact: true),
              const RowSeparator(),
            ],
          ],
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colour = destructive ? c.failedText : c.ink;

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.rowComfortable),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: Sizes.iconMd, color: colour),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: AppType.rowPrimary.copyWith(color: colour),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: AppType.helper.copyWith(color: c.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkAction extends StatelessWidget {
  const _LinkAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.controlAll,
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.touchMin),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Text(
              label,
              style: AppType.status.copyWith(color: context.colors.accentText),
            ),
          ),
        ),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: const [
          Skeleton(width: 220, height: 26),
          SizedBox(height: Space.md),
          Skeleton.text(width: 180),
          SizedBox(height: Space.xl),
          Skeleton(width: 140, height: 24),
          SizedBox(height: Space.lg),
          Skeleton(width: double.infinity, height: 4),
          SizedBox(height: Space.xl),
          Skeleton(width: double.infinity, height: Sizes.control),
        ],
      );
}

String _date(DateTime d) {
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
  return '${d.day} ${months[d.month - 1]}';
}
