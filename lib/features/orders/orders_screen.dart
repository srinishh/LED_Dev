import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/components/status.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../domain/status_projection.dart';
import '../../state/app_state.dart';
import '../alerts/alerts_screen.dart';
import 'order_detail_screen.dart';
import 'jobsheet_screen.dart';
import 'order_filter_sheet.dart';
import '../../state/async_view.dart';

/// The order book: search, filter, sort, open.
///
/// Rows rather than cards, separated by a hairline, because the job here is
/// scanning twenty orders quickly rather than admiring any one of them.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  var _scrolled = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(orderFilterProvider).query;
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 4;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Typing does not re-filter on every keystroke. A quarter of a second of
  /// stillness is enough to mean the user has finished a word.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(orderFilterProvider.notifier).setQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    final filter = ref.watch(orderFilterProvider);
    final unread = ref.watch(unreadAlertCountProvider);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: RootAppBar(
        title: 'Orders',
        scrolled: _scrolled,
        actions: [
          AppIconButton(
            icon: Ph.arrowsDownUp,
            semanticLabel: 'Sort orders',
            onPressed: () => _showSortSheet(context),
          ),
          AppIconButton(
            icon: Ph.bell,
            semanticLabel: 'Alerts',
            badgeCount: unread,
            onPressed: () => openAlertsFrom(context),
          ),
        ],
      ),
      floatingActionButton: ref.watch(currentUserProvider).isManager
          ? FloatingActionButton.extended(
              onPressed: () => openNewJobsheet(context),
              backgroundColor: context.colors.ink,
              foregroundColor: context.colors.onInk,
              icon: const Icon(Ph.plus,
                  size: Sizes.iconMd),
              label: Text('New jobsheet', style: AppType.button),
            )
          : null,
      body: Column(
        children: [
          _FilterBar(
            controller: _searchController,
            onQueryChanged: _onQueryChanged,
            filter: filter,
          ),
          Expanded(
            child: async.view(
              loading: () => const SkeletonList(count: 8),
              error: (message, canRetry) => AppErrorState(
                message: message,
                onRetry:
                    canRetry ? () => ref.invalidate(ordersProvider) : null,
              ),
              denied: (message) => AppPermissionState(message: message),
              data: (all) => _OrderList(
                all: all,
                filter: filter,
                scrollController: _scrollController,
                onClearFilters: () {
                  _searchController.clear();
                  ref.read(orderFilterProvider.notifier).clear();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    final current = ref.read(orderFilterProvider).sort;
    showAppSheet<void>(
      context,
      builder: (sheetContext) => AppBottomSheet(
        title: 'Sort by',
        child: Column(
          children: [
            for (final sort in OrderSort.values)
              _SortOption(
                sort: sort,
                selected: sort == current,
                onTap: () {
                  ref.read(orderFilterProvider.notifier).setSort(sort);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }

}

class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.sort,
    required this.selected,
    required this.onTap,
  });

  final OrderSort sort;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.rowComfortable),
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  sort.label,
                  style: AppType.rowPrimary.copyWith(color: c.ink),
                ),
              ),
              if (selected)
                Icon(
                  PhFill.checkCircle,
                  size: Sizes.iconMd,
                  color: c.accentText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search plus the active filters. The chips make a narrowed list obvious, so
/// nobody concludes the plant is empty when it is only filtered.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.controller,
    required this.onQueryChanged,
    required this.filter,
  });

  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final OrderFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final notifier = ref.read(orderFilterProvider.notifier);

    final chips = <Widget>[
      if (filter.onlyQualityFailures)
        AppChip(
          label: 'Quality failed',
          selected: true,
          onRemove: () => notifier
              .set(filter.copyWith(onlyQualityFailures: false)),
        ),
      if (filter.onlyOverdue)
        AppChip(
          label: 'Overdue',
          selected: true,
          onRemove: () => notifier.set(filter.copyWith(onlyOverdue: false)),
        ),
      if (filter.onlyNotDispatched)
        AppChip(
          label: 'Not dispatched',
          selected: true,
          onRemove: () =>
              notifier.set(filter.copyWith(onlyNotDispatched: false)),
        ),
      for (final family in filter.families)
        AppChip(
          label: family.label,
          selected: true,
          onRemove: () => notifier
              .set(filter.copyWith(families: {...filter.families}..remove(family))),
        ),
      for (final stage in filter.stages)
        AppChip(
          label: schemaFor(stage).name,
          selected: true,
          onRemove: () => notifier
              .set(filter.copyWith(stages: {...filter.stages}..remove(stage))),
        ),
      for (final customer in filter.customers)
        AppChip(
          label: customer,
          selected: true,
          onRemove: () => notifier.set(
              filter.copyWith(customers: {...filter.customers}..remove(customer))),
        ),
      for (final priority in filter.priorities)
        AppChip(
          label: priority.label,
          selected: true,
          onRemove: () => notifier.set(filter.copyWith(
              priorities: {...filter.priorities}..remove(priority))),
        ),
    ];

    return Container(
      color: c.surface,
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchField(
                    controller: controller,
                    hint: 'Order, customer or product',
                    onChanged: onQueryChanged,
                  ),
                ),
                const SizedBox(width: Space.sm),
                _FilterButton(count: filter.activeCount),
              ],
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            SizedBox(
              height: Sizes.chip,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: Space.gutter),
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      child: chip,
                    ),
                  AppChip(
                    label: 'Clear all',
                    onTap: () {
                      controller.clear();
                      notifier.clear();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = count > 0;

    return Semantics(
      button: true,
      label: active ? 'Filters, $count active' : 'Filters',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showOrderFilterSheet(context),
        borderRadius: Radii.controlAll,
        child: Container(
          height: Sizes.searchField,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: active ? c.accentWash : c.raised,
            borderRadius: Radii.controlAll,
            border: active ? Border.all(color: c.accent, width: 1.5) : null,
          ),
          child: Row(
            children: [
              Icon(
                Ph.funnelSimple,
                size: Sizes.iconMd,
                color: active ? c.ink : c.inkSecondary,
              ),
              if (active) ...[
                const SizedBox(width: Space.sm),
                Text(
                  '$count',
                  style: AppType.numeric(AppType.status).copyWith(color: c.ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  const _OrderList({
    required this.all,
    required this.filter,
    required this.scrollController,
    required this.onClearFilters,
  });

  final List<Order> all;
  final OrderFilter filter;
  final ScrollController scrollController;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(filteredOrdersProvider);

    // An empty plant and an over-narrowed filter are different problems and
    // get different screens.
    if (all.isEmpty) {
      return const AppEmptyState(
        icon: Ph.package,
        title: 'No orders yet',
        body: 'Orders appear here once planning releases them to the floor.',
      );
    }

    if (orders.isEmpty) {
      return AppEmptyState(
        icon: Ph.magnifyingGlass,
        title: 'No orders match',
        body: 'Nothing matches the filters you have applied.',
        actionLabel: 'Clear filters',
        onAction: onClearFilters,
      );
    }

    return RefreshIndicator(
      color: context.colors.accentText,
      onRefresh: () async => ref.invalidate(ordersProvider),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${orders.length} order${orders.length == 1 ? '' : 's'}',
                    style: AppType.rowSecondary
                        .copyWith(color: context.colors.inkMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    filter.sort.label,
                    style: AppType.helper
                        .copyWith(color: context.colors.inkFaint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: orders.length,
              separatorBuilder: (_, _) => const RowSeparator(),
              itemBuilder: (context, index) =>
                  OrderRow(order: orders[index]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One order in a list.
///
/// The trailing slot carries the due date, because that is what decides which
/// order to look at next. Nothing decorative competes with it.
class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order, this.showStage = true});

  final Order order;
  final bool showStage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final overdue = order.isOverdue(now);
    final days = order.daysUntilDue(now);
    final stage = order.currentStage;

    // Where the order is, and who it is for. The status word is spelled out
    // only when it signals a problem: on a normal row the stage name and the
    // glyph already say everything, and a badge on every row is what made
    // this list feel like a dump.
    final where = order.isFinished
        ? 'Delivered'
        : showStage
            ? stage.schema.shortName
            : stage.status;
    final needsWords = stage.needsAttention || order.hasQualityFailure;

    return AppListRow(
      primary: order.orderNo,
      secondary: '$where  ·  ${order.customer}',
      leading: StatusGlyph(family: stage.family, label: stage.status),
      emphasis: order.priority == Priority.urgent,
      statusRow: (needsWords || order.hasPendingSync)
          ? Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (needsWords)
                  StatusBadge(
                    family: order.hasQualityFailure
                        ? StatusFamily.failed
                        : stage.family,
                    label: order.hasQualityFailure
                        ? 'Quality failed'
                        : stage.status,
                  ),
                if (order.hasPendingSync) const PendingSyncMark(),
              ],
            )
          : null,
      trailingTop: order.isFinished
          ? Text(
              'Complete',
              style: AppType.helper.copyWith(color: c.completedText),
            )
          : _DueLabel(days: days, overdue: overdue),
      onTap: () => openOrder(context, order.id),
    );
  }
}

/// The due date, worded rather than formatted, so no arithmetic is needed.
class _DueLabel extends StatelessWidget {
  const _DueLabel({required this.days, required this.overdue});

  final int days;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = overdue
        ? days == -1
            ? 'Late 1 day'
            : 'Late ${days.abs()} days'
        : days == 0
            ? 'Due today'
            : days == 1
                ? 'Due tomorrow'
                : 'Due in $days days';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overdue) ...[
          Icon(
            PhFill.warning,
            size: Sizes.iconSm,
            color: c.failedText,
          ),
          const SizedBox(width: Space.xs),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: AppType.helper.copyWith(
              color: overdue ? c.failedText : c.inkMuted,
              fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
