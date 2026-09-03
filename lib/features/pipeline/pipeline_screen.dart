import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/components/stage.dart';
import '../../design/components/status.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';
import '../alerts/alerts_screen.dart';
import '../stages/stage_detail_screen.dart';
import 'stage_queue_screen.dart';
import '../../state/async_view.dart';

/// The whole plant at once, in two readings.
///
/// The board answers "where is work sitting". The matrix is the blueprint's
/// order and stage grid, which answers "where is this particular order".
class PipelineScreen extends ConsumerStatefulWidget {
  const PipelineScreen({super.key});

  @override
  ConsumerState<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends ConsumerState<PipelineScreen> {
  var _matrix = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersProvider);
    final unread = ref.watch(unreadAlertCountProvider);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: RootAppBar(
        title: 'Pipeline',
        actions: [
          AppIconButton(
            icon: Ph.bell,
            semanticLabel: 'Alerts',
            badgeCount: unread,
            onPressed: () => openAlertsFrom(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.lg,
            ),
            child: AppSegmentedControl<bool>(
              values: const [false, true],
              selected: _matrix,
              equalWidth: true,
              labelOf: (v) => v ? 'Matrix' : 'Board',
              onChanged: (v) => setState(() => _matrix = v),
            ),
          ),
          Expanded(
            child: async.view(
              loading: () => const SkeletonList(count: 6),
              error: (message, canRetry) => AppErrorState(
                message: message,
                onRetry:
                    canRetry ? () => ref.invalidate(ordersProvider) : null,
              ),
              denied: (message) => AppPermissionState(message: message),
              data: (orders) => orders.isEmpty
                  ? const AppEmptyState(
                      icon: Ph.flowArrow,
                      title: 'No active orders',
                      body: 'The pipeline fills as planning releases orders '
                          'to the floor.',
                    )
                  : _matrix
                      ? _Matrix(orders: orders)
                      : const _Board(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ten stage tiles. Tapping one opens the jobs sitting there.
class _Board extends ConsumerWidget {
  const _Board();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loads = ref.watch(stageLoadProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxxl),
      children: [
        const SectionHeader(title: 'Work at each stage'),
        SizedBox(
          height: stageTileHeightFor(context) + Space.sm,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: loads.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, index) {
              final load = loads[index];
              return StageTile(
                schema: schemaFor(load.stage),
                wip: load.wip,
                needingAttention: load.needingAttention,
                oldest: load.oldest,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StageQueueScreen(stage: load.stage),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.section),
        const SectionHeader(title: 'All stages'),
        for (final load in loads) ...[
          AppListRow(
            primary: schemaFor(load.stage).name,
            secondary: load.wip == 0
                ? 'Nothing waiting'
                : '${load.wip} order${load.wip == 1 ? '' : 's'}'
                    '${load.oldest == null ? '' : '. Oldest ${formatDuration(load.oldest!)}.'}',
            leading: Icon(
              iconForStage(load.stage),
              size: Sizes.iconMd,
              color: context.colors.inkMuted,
            ),
            trailingTop: Text(
              '${load.wip}',
              style: AppType.numeric(AppType.entityName)
                  .copyWith(color: context.colors.ink),
            ),
            trailingBottom: load.needingAttention > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhFill.warning,
                        size: 12,
                        color: context.colors.failedText,
                      ),
                      const SizedBox(width: Space.xs),
                      Text(
                        '${load.needingAttention}',
                        style: AppType.numeric(AppType.helper)
                            .copyWith(color: context.colors.failedText),
                      ),
                    ],
                  )
                : null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StageQueueScreen(stage: load.stage),
              ),
            ),
          ),
          const RowSeparator(),
        ],
      ],
    );
  }
}

/// The blueprint's order and stage grid.
///
/// The order column is frozen and the ten stage columns scroll beneath the
/// header, so the horizontal movement stays inside the table and the page
/// itself never slides sideways. Each cell carries a shape as well as a
/// colour, and the key sits directly under the table rather than below the
/// fold.
class _Matrix extends StatefulWidget {
  const _Matrix({required this.orders});

  final List<Order> orders;

  @override
  State<_Matrix> createState() => _MatrixState();
}

class _MatrixState extends State<_Matrix> {
  final _headerScroll = ScrollController();
  final _bodyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // The header follows the body so the columns never drift apart.
    _bodyScroll.addListener(() {
      if (_headerScroll.hasClients &&
          _headerScroll.offset != _bodyScroll.offset) {
        _headerScroll.jumpTo(_bodyScroll.offset);
      }
    });
  }

  @override
  void dispose() {
    _headerScroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  static const _orderColumnWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final orders = [...widget.orders]
      ..sort((a, b) => a.orderNo.compareTo(b.orderNo));

    return Column(
      children: [
        // Header.
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hairlineStrong)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _orderColumnWidth,
                height: Sizes.tableCell,
                child: Padding(
                  padding: const EdgeInsets.only(left: Space.gutter),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Order',
                      style: AppType.fieldLabel.copyWith(color: c.inkFaint),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _headerScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      for (final key in StageKey.ordered)
                        SizedBox(
                          width: Sizes.tableCell + Space.md,
                          height: Sizes.tableCell,
                          child: Center(
                            child: Text(
                              schemaFor(key).shortName.substring(
                                    0,
                                    schemaFor(key).shortName.length.clamp(0, 4),
                                  ),
                              style: AppType.fieldLabel
                                  .copyWith(color: c.inkFaint),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Body.
        Expanded(
          child: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return _MatrixRow(
                order: order,
                orderColumnWidth: _orderColumnWidth,
                controller: index == 0 ? _bodyScroll : null,
                onCellTap: (key) =>
                    openStageDetail(context, order.id, key),
              );
            },
          ),
        ),

        // The key belongs with the table it explains.
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          child: const SafeArea(top: false, child: StatusLegend()),
        ),
      ],
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({
    required this.order,
    required this.orderColumnWidth,
    required this.onCellTap,
    this.controller,
  });

  final Order order;
  final double orderColumnWidth;
  final ValueChanged<StageKey> onCellTap;

  /// Only the first row drives the shared horizontal offset.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: orderColumnWidth,
            height: Sizes.tableCell,
            child: Padding(
              padding: const EdgeInsets.only(left: Space.gutter),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  order.orderNo,
                  style: AppType.numeric(AppType.tableCell)
                      .copyWith(color: c.ink, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: controller == null
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: Row(
                children: [
                  for (final key in StageKey.ordered)
                    SizedBox(
                      width: Sizes.tableCell + Space.md,
                      child: InkWell(
                        onTap: () => onCellTap(key),
                        child: StatusCellMark(
                          family: order.stage(key).family,
                          semanticLabel:
                              '${order.orderNo}, ${schemaFor(key).name}, '
                              '${order.stage(key).status}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
