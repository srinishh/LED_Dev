import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/buttons.dart';
import '../../design/components/charts.dart';
import '../../design/components/feedback.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/components/stage.dart';
import '../../design/components/status.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../domain/status_projection.dart';
import '../../state/app_state.dart';
import '../orders/order_detail_screen.dart';
import '../orders/orders_screen.dart';
import '../pipeline/stage_queue_screen.dart';
import '../stages/stage_execution_screen.dart';
import '../alerts/alerts_screen.dart';
import '../../state/async_view.dart';

/// The screen opened first, every shift.
///
/// Its composition depends on the role, because an operator and a manager
/// have genuinely different first questions. An operator asks "what is
/// waiting for me"; a manager asks "what is going wrong".
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final orders = ref.watch(ordersProvider);

    return orders.view(
      loading: () => _TodayScaffold(
        title: 'Today',
        subtitle: session.plant,
        child: const _TodaySkeleton(),
      ),
      denied: (message) => _TodayScaffold(
        title: 'Today',
        subtitle: session.plant,
        child: AppPermissionState(message: message),
      ),
      error: (message, canRetry) => _TodayScaffold(
        title: 'Today',
        subtitle: session.plant,
        child: AppErrorState(
          message: message,
          onRetry: canRetry ? () => ref.invalidate(ordersProvider) : null,
        ),
      ),
      data: (_) => session.user.role == Role.manager
          ? const _ManagerToday()
          : const _OperatorToday(),
    );
  }
}

/// Marker so a permission failure can be told apart from a transport failure
/// when it surfaces through an async provider.
class PermissionDeniedMarker {
  const PermissionDeniedMarker(this.message);
  final String message;
}

class _TodayScaffold extends ConsumerWidget {
  const _TodayScaffold({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertCountProvider);
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: RootAppBar(
        title: title,
        subtitle: subtitle,
        actions: [
          AppIconButton(
            icon: Ph.bell,
            semanticLabel: 'Alerts',
            badgeCount: unread,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: context.colors.accentText,
        onRefresh: () async => ref.invalidate(ordersProvider),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manager
// ---------------------------------------------------------------------------

/// Exceptions lead, because they are the only thing that needs a decision.
/// Below them the pipeline shows where work is accumulating, then the three
/// figures that describe the week, then what has just changed.
class _ManagerToday extends ConsumerWidget {
  const _ManagerToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final exceptions = ref.watch(exceptionsProvider);
    final loads = ref.watch(stageLoadProvider);
    final orders = ref.watch(ordersProvider).value ?? const <Order>[];
    final now = DateTime.now();

    return _TodayScaffold(
      title: _greetingDate(now),
      subtitle: '${session.plant}. ${session.shift}.',
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          const SizedBox(height: Space.sm),
          if (exceptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.gutter),
              child: AppBanner(
                tone: BannerTone.positive,
                title: 'Nothing needs attention',
                detail: 'No failed checks, holds or overdue orders.',
              ),
            )
          else ...[
            SectionHeader(title: 'Needs attention', count: exceptions.total),
            _ExceptionList(exceptions: exceptions),
          ],
          const SizedBox(height: Space.section),
          const SectionHeader(title: 'Where the work is'),
          _WipChart(loads: loads, onOpenStage: (s) => _openStage(context, s)),
          const SizedBox(height: Space.section),
          _KpiRow(orders: orders, now: now),
          const SizedBox(height: Space.section),
          const SectionHeader(title: 'Recent changes'),
          _RecentChanges(orders: orders),
        ],
      ),
    );
  }

  void _openStage(BuildContext context, StageKey stage) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StageQueueScreen(stage: stage),
      ),
    );
  }

  static String _greetingDate(DateTime now) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
  }
}

/// The pipeline chart, opened on the stages that are actually holding work.
///
/// Ten bars is a wall when six of them are empty. The busiest stages lead and
/// the rest sit behind one tap, so the screen answers "where is it piling up"
/// without asking the reader to scan a list of zeroes.
class _WipChart extends StatefulWidget {
  const _WipChart({required this.loads, required this.onOpenStage});

  final List<StageLoad> loads;
  final ValueChanged<StageKey> onOpenStage;

  @override
  State<_WipChart> createState() => _WipChartState();
}

class _WipChartState extends State<_WipChart> {
  var _showAll = false;

  @override
  Widget build(BuildContext context) {
    // Busiest first, and anything needing attention is never hidden.
    final ranked = [...widget.loads]..sort((a, b) {
        final byAttention =
            b.needingAttention.compareTo(a.needingAttention);
        if (byAttention != 0) return byAttention;
        return b.wip.compareTo(a.wip);
      });

    final busy = ranked.where((l) => l.wip > 0).toList();
    final shown = _showAll ? ranked : busy.take(5).toList();
    final hidden = ranked.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HorizontalBarChart(
          data: [
            for (final load in shown)
              BarDatum(
                label: schemaFor(load.stage).shortName,
                value: load.wip,
                flagged: load.needingAttention > 0,
                semanticLabel:
                    '${schemaFor(load.stage).name}: ${load.wip} orders'
                    '${load.needingAttention > 0 ? ', ${load.needingAttention} needing attention' : ''}',
                onTap: () => widget.onOpenStage(load.stage),
              ),
          ],
        ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(left: Space.md),
            child: _TextAction(
              label: _showAll ? 'Show busiest only' : 'Show all 10 stages',
              onTap: () => setState(() => _showAll = !_showAll),
            ),
          ),
      ],
    );
  }
}

/// The exception groups, each opening the order list already narrowed to it.
class _ExceptionList extends ConsumerWidget {
  const _ExceptionList({required this.exceptions});

  final ExceptionSummary exceptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <(String, int, BannerTone, VoidCallback)>[
      if (exceptions.qualityFailed.isNotEmpty)
        (
          'Quality failed',
          exceptions.qualityFailed.length,
          BannerTone.critical,
          () => _open(context, ref, quality: true),
        ),
      if (exceptions.rework.isNotEmpty)
        (
          'Rework required',
          exceptions.rework.length,
          BannerTone.critical,
          () => _open(context, ref, families: {StatusFamily.failed}),
        ),
      if (exceptions.onHold.isNotEmpty)
        (
          'On hold',
          exceptions.onHold.length,
          BannerTone.warning,
          () => _open(context, ref, families: {StatusFamily.onHold}),
        ),
      if (exceptions.overdue.isNotEmpty)
        (
          'Overdue',
          exceptions.overdue.length,
          BannerTone.warning,
          () => _open(context, ref, overdue: true),
        ),
      if (exceptions.notDispatched.isNotEmpty)
        (
          'Not dispatched',
          exceptions.notDispatched.length,
          BannerTone.warning,
          () => _open(context, ref, notDispatched: true),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        children: [
          for (final (title, count, tone, onTap) in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: AppBanner(
                title: title,
                count: count,
                tone: tone,
                compact: true,
                onTap: onTap,
              ),
            ),
        ],
      ),
    );
  }

  void _open(
    BuildContext context,
    WidgetRef ref, {
    bool quality = false,
    bool overdue = false,
    bool notDispatched = false,
    Set<StatusFamily> families = const {},
  }) {
    ref.read(orderFilterProvider.notifier).showOnly(
          quality: quality,
          overdue: overdue,
          notDispatched: notDispatched,
          families: families,
        );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
    );
  }
}

/// Three figures that describe the week. Large bare numerals rather than
/// cards, so scale alone carries the hierarchy.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.orders, required this.now});

  final List<Order> orders;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final inProduction =
        orders.where((o) => !o.isFinished && !o.isCancelled).length;
    final dueThisWeek = orders
        .where((o) =>
            !o.isFinished &&
            o.daysUntilDue(now) >= 0 &&
            o.daysUntilDue(now) <= 7)
        .length;
    final delivered = orders.where((o) => o.isFinished).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: KpiBlock(
              value: '$inProduction',
              caption: 'In production',
              delta: const KpiDelta(amount: 3, period: 'last week'),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: KpiBlock(
              value: '$dueThisWeek',
              caption: 'Due in 7 days',
              delta: const KpiDelta(
                amount: -1,
                period: 'last week',
                higherIsBetter: false,
              ),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: KpiBlock(
              value: '$delivered',
              caption: 'Delivered',
            ),
          ),
        ],
      ),
    );
  }
}

/// The last few things that changed, so a manager returning after a break can
/// catch up without opening anything.
class _RecentChanges extends ConsumerWidget {
  const _RecentChanges({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = [...orders]
      ..sort((a, b) => (b.currentStage.updatedAt ?? b.receivedAt)
          .compareTo(a.currentStage.updatedAt ?? a.receivedAt));
    final shown = recent.take(4).toList();

    if (shown.isEmpty) {
      return const AppEmptyState(
        title: 'Nothing has changed yet',
        body: 'Updates from the floor will appear here as work progresses.',
      );
    }

    return Column(
      children: [
        for (final order in shown) ...[
          AppListRow(
            primary: order.orderNo,
            secondary: '${order.currentStage.schema.name}. '
                '${order.currentStage.updatedBy ?? 'System'}.',
            leading: StatusGlyph(
              family: order.currentStage.family,
              label: order.currentStage.status,
            ),
            trailingTop: Text(
              _ago(order.currentStage.updatedAt ?? order.receivedAt),
              style: AppType.numeric(AppType.rowSecondary)
                  .copyWith(color: context.colors.inkMuted),
            ),
            onTap: () => openOrder(context, order.id),
          ),
          const RowSeparator(),
        ],
      ],
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ---------------------------------------------------------------------------
// Operator
// ---------------------------------------------------------------------------

/// One station, one queue, one action per job.
///
/// Rows are taller here than elsewhere in the app: this screen is used with
/// gloves on, standing at a machine, often one handed.
class _OperatorToday extends ConsumerWidget {
  const _OperatorToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final queue = ref.watch(stationQueueProvider);
    final station = session.user.station;

    if (station == null) {
      return const _TodayScaffold(
        title: 'Today',
        child: AppEmptyState(
          title: 'No station selected',
          body: 'Choose the station you are working at to see its queue.',
        ),
      );
    }

    final schema = schemaFor(station);

    return _TodayScaffold(
      title: schema.name,
      subtitle: '${session.user.machine ?? session.plant}. '
          '${session.shiftHours}.',
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          _ShiftProgress(queue: queue),
          const SizedBox(height: Space.section),
          if (queue.isEmpty)
            const AppEmptyState(
              icon: Ph.checkCircle,
              title: 'Nothing waiting at your station',
              body: 'New jobs appear here as soon as the previous stage '
                  'is finished.',
            )
          else ...[
            if (queue.active.isNotEmpty) ...[
              SectionHeader(
                title: 'Needs you now',
                count: queue.active.length,
              ),
              for (final order in queue.active) ...[
                _JobRow(order: order, station: station),
                const RowSeparator(),
              ],
            ],
            if (queue.onHold.isNotEmpty) ...[
              const SizedBox(height: Space.section),
              SectionHeader(title: 'On hold', count: queue.onHold.length),
              for (final order in queue.onHold) ...[
                _JobRow(order: order, station: station),
                const RowSeparator(),
              ],
            ],
            if (queue.rework.isNotEmpty) ...[
              const SizedBox(height: Space.section),
              SectionHeader(title: 'Rework', count: queue.rework.length),
              for (final order in queue.rework) ...[
                _JobRow(order: order, station: station),
                const RowSeparator(),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// How the shift is going. One figure, one bar, no decoration.
class _ShiftProgress extends StatelessWidget {
  const _ShiftProgress({required this.queue});

  final StationQueue queue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = queue.target == 0 ? 1 : queue.target;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${queue.completed}',
                style: AppType.kpi.copyWith(color: c.ink),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'of $total jobs done this shift',
                  style: AppType.kpiCaption.copyWith(color: c.inkMuted),
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          StageProgressBar(
            completed: queue.completed,
            total: total,
            showLabel: false,
          ),
        ],
      ),
    );
  }
}

/// A job at this station. The row shows only what decides which job to pick
/// up next: what it is, how long it has been sitting, and its state.
class _JobRow extends ConsumerWidget {
  const _JobRow({required this.order, required this.station});

  final Order order;
  final StageKey station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final record = order.stage(station);
    final elapsed = record.elapsedAt(DateTime.now());
    // Anything sitting longer than a shift is worth flagging.
    final isSlow = elapsed != null && elapsed.inHours >= 8;

    return AppListRow(
      density: Density.operational,
      primary: order.orderNo,
      secondary: '${order.product}. ${order.quantity} pcs.',
      leading: StatusGlyph(family: record.family, label: record.status),
      emphasis: order.priority == Priority.urgent,
      statusRow: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(family: record.family, label: record.status),
          if (elapsed != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Ph.clock,
                  size: Sizes.iconSm,
                  color: isSlow ? c.onHoldText : c.inkFaint,
                ),
                const SizedBox(width: Space.xs),
                Text(
                  formatDuration(elapsed),
                  style: AppType.numeric(AppType.helper).copyWith(
                    color: isSlow ? c.onHoldText : c.inkMuted,
                    fontWeight: isSlow ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          if (order.hasPendingSync) const PendingSyncMark(),
        ],
      ),
      trailingTop: _TextAction(
        label: 'Update',
        onTap: () => openStageExecution(context, order.id, station),
      ),
      showChevron: false,
      onTap: () => openOrder(context, order.id),
      onLongPress: () => _showJobActions(context, order, station),
    );
  }

  void _showJobActions(BuildContext context, Order order, StageKey station) {
    showAppSheet<void>(
      context,
      builder: (sheetContext) => AppBottomSheet(
        title: order.orderNo,
        subtitle: order.product,
        child: Column(
          children: [
            _SheetAction(
              icon: Ph.pencilSimple,
              label: 'Update ${schemaFor(station).name}',
              onTap: () {
                Navigator.of(sheetContext).pop();
                openStageExecution(context, order.id, station);
              },
            ),
            _SheetAction(
              icon: Ph.fileText,
              label: 'Open order',
              onTap: () {
                Navigator.of(sheetContext).pop();
                openOrder(context, order.id);
              },
            ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.rowComfortable),
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Row(
          children: [
            Icon(icon, size: Sizes.iconMd, color: c.inkSecondary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                label,
                style: AppType.rowPrimary.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A low-emphasis inline action, used where a full button would shout.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.controlAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppType.status.copyWith(color: context.colors.accentText),
          ),
        ),
      ),
    );
  }
}

class _TodaySkeleton extends StatelessWidget {
  const _TodaySkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 140, height: 34),
                SizedBox(height: Space.md),
                Skeleton(width: double.infinity, height: 4),
              ],
            ),
          ),
          SizedBox(height: Space.section),
          SkeletonList(count: 5),
        ],
      );
}
