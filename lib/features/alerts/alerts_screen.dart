import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../state/app_state.dart';
import '../orders/order_detail_screen.dart';
import '../../state/async_view.dart';

/// Opens alerts from any top-level screen.
void openAlertsFrom(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
  );
}

/// Everything demanding a decision, most serious first.
///
/// This is the one place in the app with a swipe gesture. It is used only
/// because acknowledging is reversible, the undo is offered immediately, and
/// tapping through to the order does the same job for anyone who does not
/// discover it.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  var _showAcknowledged = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(alertsProvider);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: const NestedAppBar(title: 'Alerts'),
      body: async.view(
        loading: () => const SkeletonList(count: 6),
        error: (message, canRetry) => AppErrorState(
          message: message,
          onRetry: canRetry ? () => ref.invalidate(alertsProvider) : null,
        ),
        denied: (message) => AppPermissionState(message: message),
        data: (all) {
          final open = all.where((a) => !a.acknowledged).toList();
          final done = all.where((a) => a.acknowledged).toList();
          final shown = _showAcknowledged ? done : open;

          if (all.isEmpty) {
            return const AppEmptyState(
              icon: PhFill.checkCircle,
              title: 'All clear',
              body: 'No failed checks, holds or overdue orders right now.',
            );
          }

          return Column(
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
                    AppChip(
                      label: 'Open',
                      count: open.length,
                      selected: !_showAcknowledged,
                      onTap: () => setState(() => _showAcknowledged = false),
                    ),
                    const SizedBox(width: Space.sm),
                    AppChip(
                      label: 'Acknowledged',
                      count: done.length,
                      selected: _showAcknowledged,
                      onTap: () => setState(() => _showAcknowledged = true),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? AppEmptyState(
                        icon: _showAcknowledged
                            ? Ph.tray
                            : PhFill.checkCircle,
                        title: _showAcknowledged
                            ? 'Nothing acknowledged yet'
                            : 'All clear',
                        body: _showAcknowledged
                            ? 'Alerts you acknowledge are kept here.'
                            : 'Everything raised has been dealt with.',
                      )
                    : ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const RowSeparator(),
                        itemBuilder: (context, index) =>
                            _AlertRow(alert: shown[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.alert});

  final Alert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final tone = switch (alert.severity) {
      EventSeverity.critical => (c.failedText, PhFill.warning),
      EventSeverity.warning => (c.onHoldText, PhFill.pause),
      EventSeverity.normal => (c.inkMuted, Ph.info),
    };

    final row = AppListRow(
      primary: alert.title,
      secondary: '${alert.orderNo}. ${alert.detail}',
      leading: Icon(tone.$2, size: Sizes.iconMd, color: tone.$1),
      trailingTop: Text(
        _ago(alert.raisedAt),
        style: AppType.helper.copyWith(color: c.inkFaint),
      ),
      emphasis: alert.severity == EventSeverity.critical,
      onTap: () => openOrder(context, alert.orderId),
    );

    if (alert.acknowledged) return row;

    return Dismissible(
      key: ValueKey(alert.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: c.raised,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.gutter),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(
              Ph.check,
              size: Sizes.iconMd,
              color: c.inkSecondary,
            ),
            const SizedBox(width: Space.sm),
            Text(
              'Acknowledge',
              style: AppType.status.copyWith(color: c.inkSecondary),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        await ref.read(orderActionsProvider).acknowledgeAlert(alert.id);
        if (!context.mounted) return;
        // Acknowledging by accident should cost nothing.
        showAppToast(
          context,
          message: '${alert.title} acknowledged.',
          undoLabel: 'Undo',
          onUndo: () =>
              ref.read(orderActionsProvider).undoAcknowledge(alert.id),
        );
      },
      child: row,
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.isNegative) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
