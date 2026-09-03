import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/feedback.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/components/stage.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';
import '../orders/orders_screen.dart';
import '../../state/async_view.dart';

/// The orders sitting at one stage.
///
/// Reached from a pipeline tile or a bar on the manager dashboard. It reuses
/// the order row so the same information reads the same way everywhere.
class StageQueueScreen extends ConsumerWidget {
  const StageQueueScreen({super.key, required this.stage});

  final StageKey stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schema = schemaFor(stage);
    final async = ref.watch(ordersProvider);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: NestedAppBar(title: schema.name),
      body: async.view(
        loading: () => const SkeletonList(count: 6),
        error: (message, canRetry) => AppErrorState(
          message: message,
          onRetry: canRetry ? () => ref.invalidate(ordersProvider) : null,
        ),
        denied: (message) => AppPermissionState(message: message),
        data: (all) {
          final here = [
            for (final order in all)
              if (order.currentStageKey == stage && !order.isFinished) order,
          ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));

          if (here.isEmpty) {
            return AppEmptyState(
              icon: iconForStage(stage),
              title: 'Nothing at ${schema.name}',
              body: 'Orders appear here once the previous stage is finished.',
            );
          }

          final flagged = here.where((o) => o.needsAttention).length;

          return RefreshIndicator(
            color: context.colors.accentText,
            onRefresh: () async => ref.invalidate(ordersProvider),
            child: Column(
              children: [
                _QueueSummary(
                  count: here.length,
                  flagged: flagged,
                  oldest: _oldest(here, now),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: here.length,
                    separatorBuilder: (_, _) => const RowSeparator(),
                    itemBuilder: (context, index) => OrderRow(
                      order: here[index],
                      showStage: false,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Duration? _oldest(List<Order> orders, DateTime now) {
    Duration? oldest;
    for (final order in orders) {
      final age = order.stage(stage).elapsedAt(now);
      if (age != null && (oldest == null || age > oldest)) oldest = age;
    }
    return oldest;
  }
}

/// The three numbers that describe a queue: how much, how bad, how old.
class _QueueSummary extends StatelessWidget {
  const _QueueSummary({
    required this.count,
    required this.flagged,
    required this.oldest,
  });

  final int count;
  final int flagged;
  final Duration? oldest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$count',
            style: AppType.kpi.copyWith(color: c.ink),
          ),
          const SizedBox(width: Space.sm),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'order${count == 1 ? '' : 's'} waiting',
              style: AppType.kpiCaption.copyWith(color: c.inkMuted),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (flagged > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhFill.warning,
                      size: Sizes.iconSm,
                      color: c.failedText,
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      '$flagged need attention',
                      style: AppType.helper.copyWith(
                        color: c.failedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              if (oldest != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  'oldest ${formatDuration(oldest!)}',
                  style: AppType.helper.copyWith(color: c.inkMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
