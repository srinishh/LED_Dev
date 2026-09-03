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
import '../../domain/rules.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';

void openQuality(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => QualityScreen(orderId: orderId),
    ),
  );
}

/// The mandatory quality checklist.
///
/// The blueprint is explicit that an order must not move on while a mandatory
/// check has failed. That rule is the loudest thing on this screen: the gate
/// is stated at the top, and the control that would advance the order is
/// visibly disabled with the same sentence underneath it.
class QualityScreen extends ConsumerWidget {
  const QualityScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    final user = ref.watch(currentUserProvider);

    if (order == null) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: const NestedAppBar(title: 'Quality Testing'),
        body: const AppErrorState(
          message: 'This order is no longer available.',
        ),
      );
    }

    final gate = Rules.qualityGate(order);
    final passed =
        order.qualityTests.where((t) => t.status == TestStatus.passed).length;
    final canRecord =
        Rules.canExecuteStage(user, order, StageKey.qualityTesting);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: NestedAppBar(
        title: 'Quality Testing',
        subtitle: order.orderNo,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: gate.blocked
                ? BlockerBanner(
                    title: 'Held at quality',
                    reason: gate.reason!,
                  )
                : const AppBanner(
                    tone: BannerTone.positive,
                    title: 'All checks passed',
                    detail: 'The order can move to Wiring and Assembly.',
                  ),
          ),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text(
              '$passed of ${order.qualityTests.length} checks passed',
              style: AppType.rowSecondary
                  .copyWith(color: context.colors.inkMuted),
            ),
          ),
          const SizedBox(height: Space.lg),
          for (final test in order.qualityTests) ...[
            _TestRow(
              order: order,
              test: test,
              canRecord: canRecord.allowed,
              deniedReason: canRecord.reason,
            ),
            const RowSeparator(),
          ],
          if (canRecord.blocked)
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: AppBanner(
                title: 'You can view but not record',
                detail: canRecord.reason,
                icon: Ph.lock,
              ),
            ),
        ],
      ),
      bottomNavigationBar: _QualityActions(order: order, gate: gate),
    );
  }
}

/// One check. The failure note is shown inline rather than hidden behind a
/// tap, because the reason for a failure is what the next person needs.
class _TestRow extends ConsumerWidget {
  const _TestRow({
    required this.order,
    required this.test,
    required this.canRecord,
    this.deniedReason,
  });

  final Order order;
  final QualityTestRecord test;
  final bool canRecord;
  final String? deniedReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    return AppListRow(
      primary: test.name,
      secondary: test.testedBy == null
          ? 'Not recorded yet'
          : '${test.testedBy}. ${_date(test.testedAt!)}.',
      leading: StatusGlyph(family: test.family, label: test.status.label),
      statusRow: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                family: test.family,
                label: test.status.label,
                emphasis: test.status == TestStatus.failed
                    ? StatusEmphasis.strong
                    : StatusEmphasis.normal,
              ),
              if (test.history.isNotEmpty)
                Text(
                  '${test.history.length} earlier '
                  'attempt${test.history.length == 1 ? '' : 's'}',
                  style: AppType.helper.copyWith(color: c.inkFaint),
                ),
            ],
          ),
          if (test.notes != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              test.notes!,
              style: AppType.helper.copyWith(color: c.failedText),
            ),
          ],
        ],
      ),
      onTap: canRecord
          ? () => _showTestEntry(context, ref, order, test)
          : null,
      showChevron: canRecord,
    );
  }
}

/// Records one result. A failure must say why, because that note is the only
/// thing that tells the floor what to fix.
Future<void> _showTestEntry(
  BuildContext context,
  WidgetRef ref,
  Order order,
  QualityTestRecord test,
) async {
  await showAppSheet<void>(
    context,
    builder: (_) => _TestEntrySheet(order: order, test: test),
  );
}

class _TestEntrySheet extends ConsumerStatefulWidget {
  const _TestEntrySheet({required this.order, required this.test});

  final Order order;
  final QualityTestRecord test;

  @override
  ConsumerState<_TestEntrySheet> createState() => _TestEntrySheetState();
}

class _TestEntrySheetState extends ConsumerState<_TestEntrySheet> {
  late TestResult _result = widget.test.result;
  final _notes = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notes.text = widget.test.notes ?? '';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isRetest = widget.test.testedBy != null;

    return AppBottomSheet(
      title: widget.test.name,
      subtitle: isRetest
          ? 'Recording a re-test. The earlier result is kept.'
          : 'Recorded against ${user.name}.',
      action: AppButton(
        label: isRetest ? 'Save re-test' : 'Save result',
        busy: _busy,
        onPressed: _result == TestResult.pending ? null : _save,
        disabledReason: _result == TestResult.pending
            ? 'Choose whether the check passed or failed.'
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Result',
              padding: const EdgeInsets.only(bottom: Space.md),
            ),
            AppSegmentedControl<TestResult>(
              values: const [
                TestResult.pass,
                TestResult.fail,
                TestResult.pending,
              ],
              selected: _result,
              labelOf: (r) => switch (r) {
                TestResult.pass => 'Pass',
                TestResult.fail => 'Fail',
                TestResult.pending => 'Still testing',
              },
              onChanged: (r) => setState(() {
                _result = r;
                _error = null;
              }),
            ),
            const SizedBox(height: Space.xl),
            AppTextField(
              label: 'Notes',
              controller: _notes,
              maxLines: 4,
              required: _result == TestResult.fail,
              error: _error,
              helper: _result == TestResult.fail
                  ? 'Say what failed and by how much, so the floor knows what '
                      'to correct.'
                  : 'Optional. Anything worth recording about this check.',
            ),
            if (widget.test.history.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              SectionHeader(
                title: 'Earlier attempts',
                padding: const EdgeInsets.only(bottom: Space.md),
              ),
              for (final attempt in widget.test.history.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Text(
                    '${attempt.result == TestResult.pass ? 'Passed' : 'Failed'}'
                    '. ${attempt.testedBy}. ${_date(attempt.testedAt)}.'
                    '${attempt.notes == null ? '' : ' ${attempt.notes}'}',
                    style: AppType.helper
                        .copyWith(color: context.colors.inkMuted),
                  ),
                ),
            ],
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_result == TestResult.fail && _notes.text.trim().isEmpty) {
      setState(() => _error =
          'Describe the failure so the floor knows what to correct.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(orderActionsProvider).recordQualityTest(
            orderId: widget.order.id,
            testKey: widget.test.definition.key,
            result: _result,
            status: switch (_result) {
              TestResult.pass => TestStatus.passed,
              TestResult.fail => TestStatus.failed,
              TestResult.pending => TestStatus.inTesting,
            },
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppToast(
        context,
        message: '${widget.test.name} recorded as '
            '${_result == TestResult.pass ? 'passed' : _result == TestResult.fail ? 'failed' : 'still testing'}.',
        tone: _result == TestResult.fail
            ? BannerTone.critical
            : BannerTone.positive,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }
}

/// The gate, made operable.
///
/// Advancing is offered here rather than only on the order screen, because
/// this is where the inspector finishes the job. It is disabled while the
/// gate is closed, and it says exactly why.
class _QualityActions extends ConsumerStatefulWidget {
  const _QualityActions({required this.order, required this.gate});

  final Order order;
  final RuleResult gate;

  @override
  ConsumerState<_QualityActions> createState() => _QualityActionsState();
}

class _QualityActionsState extends ConsumerState<_QualityActions> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final atQuality = order.currentStageKey == StageKey.qualityTesting;

    if (!atQuality) {
      return StickyActionBar(
        primary: AppButton(
          label: 'Back to order',
          kind: ButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      );
    }

    return StickyActionBar(
      primary: AppButton(
        label: 'Advance to ${schemaFor(StageKey.wiringAssembly).name}',
        busy: _busy,
        onPressed: widget.gate.allowed ? _advance : null,
        disabledReason: widget.gate.reason,
      ),
    );
  }

  Future<void> _advance() async {
    setState(() => _busy = true);
    try {
      await ref.read(orderActionsProvider).advance(widget.order.id);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Quality passed. Order moved to '
            '${schemaFor(StageKey.wiringAssembly).name}.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: '$e', tone: BannerTone.critical);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
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
