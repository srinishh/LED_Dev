import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
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
import 'dispatch_screen.dart';
import 'quality_screen.dart';
import 'stage_execution_screen.dart';

void openStageDetail(BuildContext context, String orderId, StageKey stage) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StageDetailScreen(orderId: orderId, stage: stage),
    ),
  );
}

/// What was recorded at one stage, read only.
///
/// Reached by tapping a node on the stage rail or a cell in the matrix. It
/// answers "what happened here" without putting the reader into a form.
class StageDetailScreen extends ConsumerWidget {
  const StageDetailScreen({
    super.key,
    required this.orderId,
    required this.stage,
  });

  final String orderId;
  final StageKey stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final order = ref.watch(orderProvider(orderId));
    final user = ref.watch(currentUserProvider);
    final schema = schemaFor(stage);

    if (order == null) {
      return Scaffold(
        backgroundColor: c.surface,
        appBar: NestedAppBar(title: schema.name),
        body: const AppErrorState(
          message: 'This order is no longer available.',
        ),
      );
    }

    final record = order.stage(stage);
    final canEdit = record.isComplete
        ? Rules.canEditCompletedStage(user)
        : Rules.canExecuteStage(user, order, stage);
    final start = Rules.canStartStage(order, stage);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: NestedAppBar(title: schema.name, subtitle: order.orderNo),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(
                  family: record.family,
                  label: record.status,
                  emphasis: record.needsAttention
                      ? StatusEmphasis.strong
                      : StatusEmphasis.normal,
                ),
                // The blueprint asks for material to be shown as in process or
                // not, rather than inferred from the status wording.
                if (stage == StageKey.rawMaterial) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    Rules.materialIsInProcess(record.status)
                        ? 'Material is in process.'
                        : 'Material is not in process.',
                    style: AppType.rowSecondary.copyWith(color: c.inkSecondary),
                  ),
                ],
                if (record.startedAt != null) ...[
                  const SizedBox(height: Space.md),
                  Text(
                    record.completedAt != null
                        ? 'Took ${formatDuration(record.completedAt!.difference(record.startedAt!))}.'
                        : 'Running for ${formatDuration(record.elapsedAt(DateTime.now())!)}.',
                    style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                  ),
                ],
                if (record.updatedBy != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    'Last updated by ${record.updatedBy}.',
                    style: AppType.helper.copyWith(color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.section),

          if (stage == StageKey.qualityTesting)
            _QualitySummary(order: order)
          else if (record.isNotStarted && record.values.isEmpty)
            AppEmptyState(
              title: 'Nothing recorded yet',
              body: start.blocked
                  ? start.reason!
                  : 'This stage has not been started.',
            )
          else
            ..._readouts(order, record, schema),
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        primary: AppButton(
          label: record.isComplete
              ? 'Edit ${schema.name}'
              : 'Update ${schema.name}',
          onPressed: canEdit.allowed && start.allowed
              ? () => _open(context, order.id)
              : null,
          disabledReason: canEdit.reason ?? start.reason,
        ),
      ),
    );
  }

  void _open(BuildContext context, String orderId) {
    if (stage == StageKey.qualityTesting) {
      openQuality(context, orderId);
    } else if (stage == StageKey.dispatch) {
      openDispatch(context, orderId);
    } else {
      openStageExecution(context, orderId, stage);
    }
  }

  List<Widget> _readouts(
    Order order,
    StageRecord record,
    StageSchema schema,
  ) {
    if (schema.subRecords.isNotEmpty) {
      return [
        for (final sub in schema.subRecords) ...[
          SectionHeader(title: sub.name),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldReadout(
                  label: 'Status',
                  value: record.subRecords[sub.key]?.status ??
                      sub.initialStatus,
                ),
                for (final field in sub.fields)
                  FieldReadout(
                    label: field.label,
                    value: _format(
                      record.subRecords[sub.key]?.values[field.key],
                      field,
                    ),
                    numeric: field.type == FieldType.integer,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
        ],
      ];
    }

    final groups = <String>[];
    for (final field in schema.fields) {
      final g = field.group ?? 'Details';
      if (!groups.contains(g)) groups.add(g);
    }

    return [
      for (final group in groups) ...[
        SectionHeader(title: group),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final field in schema.fields)
                if ((field.group ?? 'Details') == group)
                  FieldReadout(
                    label: field.label,
                    value: _format(record.values[field.key], field),
                    source: field.carriedFrom == null
                        ? null
                        : schemaFor(field.carriedFrom!).name,
                    numeric: field.type == FieldType.integer,
                  ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
      ],
    ];
  }

  String _format(Object? value, FieldSchema field) {
    if (value == null) return 'Not recorded';
    if (value is bool) return value ? 'Verified' : 'Not verified';
    if (value is List) {
      return value.isEmpty ? 'None recorded' : value.join('\n');
    }
    if (value is DateTime) {
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
      final date = '${value.day} ${months[value.month - 1]} ${value.year}';
      if (field.type == FieldType.date) return date;
      final hh = value.hour.toString().padLeft(2, '0');
      final mm = value.minute.toString().padLeft(2, '0');
      return '$date, $hh:$mm';
    }
    if (value is int && field.unit != null) return '$value ${field.unit}';
    return '$value';
  }
}

class _QualitySummary extends StatelessWidget {
  const _QualitySummary({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final gate = Rules.qualityGate(order);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: gate.blocked
              ? BlockerBanner(title: 'Held at quality', reason: gate.reason!)
              : const AppBanner(
                  tone: BannerTone.positive,
                  title: 'All checks passed',
                  detail: 'The order can move to Wiring and Assembly.',
                ),
        ),
        const SizedBox(height: Space.lg),
        for (final test in order.qualityTests) ...[
          AppListRow(
            primary: test.name,
            secondary: test.testedBy == null
                ? 'Not recorded'
                : '${test.testedBy}.',
            leading: StatusGlyph(
              family: test.family,
              label: test.status.label,
            ),
            trailingTop:
                StatusBadge(family: test.family, label: test.status.label),
            showChevron: false,
          ),
          const RowSeparator(),
        ],
      ],
    );
  }
}
