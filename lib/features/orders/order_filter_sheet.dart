import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/buttons.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../domain/status_projection.dart';
import '../../state/app_state.dart';

/// Opens the filter sheet. Filtering is a sheet rather than a screen so the
/// list stays visible behind it and the controls sit in thumb reach.
Future<void> showOrderFilterSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _OrderFilterSheet());

class _OrderFilterSheet extends ConsumerStatefulWidget {
  const _OrderFilterSheet();

  @override
  ConsumerState<_OrderFilterSheet> createState() => _OrderFilterSheetState();
}

class _OrderFilterSheetState extends ConsumerState<_OrderFilterSheet> {
  late OrderFilter _draft = ref.read(orderFilterProvider);

  /// The sheet edits a copy, so backing out leaves the list untouched.
  void _update(OrderFilter next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ordersProvider).value ?? const <Order>[];
    // The count on the button comes from the same function that filters the
    // list, so the preview can never disagree with the result.
    final matches = applyFilter(all, _draft).length;

    final customers = <String>{for (final o in all) o.customer}.toList()
      ..sort();

    return AppBottomSheet(
      title: 'Filters',
      trailing: _draft.isEmpty
          ? null
          : AppButton(
              label: 'Reset',
              kind: ButtonKind.tertiary,
              expand: false,
              onPressed: () => _update(_draft.cleared()),
            ),
      action: AppButton(
        label: matches == 0
            ? 'No orders match'
            : 'Show $matches order${matches == 1 ? '' : 's'}',
        onPressed: matches == 0
            ? null
            : () {
                ref.read(orderFilterProvider.notifier).set(_draft);
                Navigator.of(context).pop();
              },
        disabledReason: matches == 0
            ? 'Remove a filter to see results.'
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Group(
              title: 'Needs attention',
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  AppChip(
                    label: 'Quality failed',
                    selected: _draft.onlyQualityFailures,
                    onTap: () => _update(_draft.copyWith(
                      onlyQualityFailures: !_draft.onlyQualityFailures,
                    )),
                  ),
                  AppChip(
                    label: 'Overdue',
                    selected: _draft.onlyOverdue,
                    onTap: () => _update(
                        _draft.copyWith(onlyOverdue: !_draft.onlyOverdue)),
                  ),
                  AppChip(
                    label: 'Not dispatched',
                    selected: _draft.onlyNotDispatched,
                    onTap: () => _update(_draft.copyWith(
                        onlyNotDispatched: !_draft.onlyNotDispatched)),
                  ),
                ],
              ),
            ),
            _Group(
              title: 'Status',
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final family in StatusFamily.values)
                    AppChip(
                      label: family.label,
                      selected: _draft.families.contains(family),
                      onTap: () => _update(_draft.copyWith(
                        families: _toggle(_draft.families, family),
                      )),
                    ),
                ],
              ),
            ),
            _Group(
              title: 'Stage',
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final stage in StageKey.ordered)
                    AppChip(
                      label: schemaFor(stage).name,
                      selected: _draft.stages.contains(stage),
                      onTap: () => _update(_draft.copyWith(
                        stages: _toggle(_draft.stages, stage),
                      )),
                    ),
                ],
              ),
            ),
            _Group(
              title: 'Priority',
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final priority in Priority.values)
                    AppChip(
                      label: priority.label,
                      selected: _draft.priorities.contains(priority),
                      onTap: () => _update(_draft.copyWith(
                        priorities: _toggle(_draft.priorities, priority),
                      )),
                    ),
                ],
              ),
            ),
            _Group(
              title: 'Customer',
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final customer in customers)
                    AppChip(
                      label: customer,
                      selected: _draft.customers.contains(customer),
                      onTap: () => _update(_draft.copyWith(
                        customers: _toggle(_draft.customers, customer),
                      )),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }

  Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: title,
              padding: const EdgeInsets.only(bottom: Space.md),
            ),
            child,
          ],
        ),
      );
}
