import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/rules.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';

void openDispatch(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DispatchScreen(orderId: orderId),
    ),
  );
}

/// The dispatch record.
///
/// The blueprint requires a reason whenever an order is recorded as not
/// dispatched, and that reason must come from a fixed list. The screen
/// enforces it rather than asking politely: the save control is disabled and
/// says what is missing until a reason is chosen.
class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends ConsumerState<DispatchScreen> {
  final _schema = schemaFor(StageKey.dispatch);
  final Map<String, Object?> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _errors = {};

  String _status = '';
  NotDispatchedReason? _reason;
  final _reasonDetail = TextEditingController();
  var _dirty = false;
  var _busy = false;
  var _submitted = false;

  /// Seeded on the first build that has an order, for the same reason as the
  /// stage form: the order is not there yet when the screen is created.
  var _seeded = false;

  void _seedFrom(Order order) {
    if (_seeded) return;
    _seeded = true;

    final record = order.stage(StageKey.dispatch);
    _status = record.status;
    _values.addAll(record.values);
    _reason = order.dispatch.notDispatchedReason;
    _reasonDetail.text = order.dispatch.notDispatchedDetail ?? '';
    _applyDefaults(order);
  }

  void _applyDefaults(Order order) {
    final now = DateTime.now();
    final packing = order.stage(StageKey.packingLabelling).values;

    _values.putIfAbsent('customerName', () => order.customer);
    _values.putIfAbsent('quantityDispatched', () => order.quantity);
    _values.putIfAbsent('invoiceDate', () => DateTime(now.year, now.month, now.day));
    _values.putIfAbsent('dispatchDate', () => DateTime(now.year, now.month, now.day));
    // The carton count comes straight from packing, so it is never recounted.
    _values.putIfAbsent(
      'numberOfPackages',
      () => packing['numberOfBoxes'] ?? 0,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _reasonDetail.dispose();
    super.dispose();
  }

  bool get _notDispatched => _status == 'Not Dispatched';

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    final user = ref.watch(currentUserProvider);

    if (order == null) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: const NestedAppBar(title: 'Dispatch'),
        body: const AppErrorState(
          message: 'This order is no longer available.',
        ),
      );
    }

    _seedFrom(order);

    final permission =
        Rules.canExecuteStage(user, order, StageKey.dispatch);
    if (permission.blocked) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: NestedAppBar(title: 'Dispatch', subtitle: order.orderNo),
        body: AppPermissionState(message: permission.reason!),
      );
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.surface,
        appBar: NestedAppBar(title: 'Dispatch', subtitle: order.orderNo),
        body: ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Dispatch status',
                    padding: const EdgeInsets.only(bottom: Space.md),
                  ),
                  AppSegmentedControl<String>(
                    values: _schema.statusValues,
                    selected: _status,
                    labelOf: (v) => v,
                    onChanged: (value) => setState(() {
                      _status = value;
                      _dirty = true;
                      if (value != 'Not Dispatched') _reason = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.xl),

            // The reason block appears only when it is needed, and when it
            // appears it is unavoidable.
            if (_notDispatched) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: _ReasonBlock(
                  reason: _reason,
                  detailController: _reasonDetail,
                  error: _submitted ? _errors['notDispatchedReason'] : null,
                  detailError:
                      _submitted ? _errors['notDispatchedDetail'] : null,
                  onPick: () async {
                    final picked = await _pickReason(context, _reason);
                    if (picked != null) {
                      setState(() {
                        _reason = picked;
                        _dirty = true;
                        _errors.remove('notDispatchedReason');
                      });
                    }
                  },
                  onDetailChanged: (_) =>
                      setState(() => _errors.remove('notDispatchedDetail')),
                ),
              ),
              const SizedBox(height: Space.xl),
            ],

            ..._fieldsets(order),
          ],
        ),
        bottomNavigationBar: StickyActionBar(
          primary: AppButton(
            label: _saveLabel,
            busy: _busy,
            onPressed: _canSave ? () => _save(order) : null,
            disabledReason: _blockReason,
          ),
        ),
      ),
    );
  }

  String get _saveLabel => switch (_status) {
        'Dispatched' => 'Record dispatch',
        'Not Dispatched' => 'Record as not dispatched',
        'Delivered' => 'Record delivery',
        _ => 'Save',
      };

  RuleResult get _violations => Rules.canSaveDispatch(
        status: _status,
        reason: _reason,
        detail: _reasonDetail.text,
      );

  bool get _canSave => _violations.allowed;

  String? get _blockReason => _violations.reason;

  List<Widget> _fieldsets(Order order) {
    final groups = <String>[];
    for (final field in _schema.fields) {
      final g = field.group ?? 'Details';
      if (!groups.contains(g)) groups.add(g);
    }

    return [
      for (final group in groups)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Fieldset(
            title: group,
            children: [
              for (final field in _schema.fields)
                if ((field.group ?? 'Details') == group) _field(field),
            ],
          ),
        ),
    ];
  }

  Widget _field(FieldSchema field) {
    final value = _values[field.key];
    final error = _submitted ? _errors[field.key] : null;

    if (field.type == FieldType.select) {
      final selected = value is String ? value : null;
      return AppSelectField(
        label: field.label,
        value: selected,
        required: true,
        error: error,
        onTap: () async {
          final options = ref
              .read(repositoryProvider)
              .masters
              .optionsFor(field.optionsKey ?? '');
          final picked = await showOptionPicker(
            context,
            title: field.label,
            options: options,
            selected: selected,
          );
          if (picked != null) {
            setState(() {
              _values[field.key] = picked;
              _dirty = true;
            });
          }
        },
      );
    }

    if (field.type == FieldType.date) {
      final asDate = value is DateTime ? value : null;
      return AppSelectField(
        label: field.label,
        value: asDate == null ? null : _formatDate(asDate),
        placeholder: 'Choose a date',
        required: true,
        error: error,
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: asDate ?? now,
            firstDate: now.subtract(const Duration(days: 365)),
            lastDate: now.add(const Duration(days: 30)),
          );
          if (picked != null) {
            setState(() {
              _values[field.key] = picked;
              _dirty = true;
            });
          }
        },
      );
    }

    return AppTextField(
      label: field.label,
      controller: _controllers.putIfAbsent(
        field.key,
        () => TextEditingController(text: value?.toString() ?? ''),
      ),
      required: true,
      readOnly: field.readOnly,
      helper: field.helper,
      error: error,
      unit: field.unit,
      maxLines: field.type == FieldType.multiline ? 3 : 1,
      keyboardType: switch (field.type) {
        FieldType.integer => TextInputType.number,
        FieldType.phone => TextInputType.phone,
        FieldType.multiline => TextInputType.multiline,
        _ => TextInputType.text,
      },
      onChanged: (raw) {
        _values[field.key] =
            field.type == FieldType.integer ? int.tryParse(raw) : raw;
        _dirty = true;
        _errors.remove(field.key);
      },
    );
  }

  Future<void> _save(Order order) async {
    setState(() {
      _submitted = true;
      _busy = true;
      _errors.clear();
    });

    final violations = _violations;
    if (violations.blocked) {
      setState(() {
        _busy = false;
        for (final v in violations) {
          if (v.field != null) _errors[v.field!] = v.message;
        }
      });
      return;
    }

    try {
      await ref.read(orderActionsProvider).saveDispatch(
            orderId: order.id,
            status: _status,
            values: _values,
            reason: _reason,
            reasonDetail: _reasonDetail.text.trim(),
          );
      if (!mounted) return;
      setState(() => _dirty = false);
      showAppToast(
        context,
        message: _notDispatched
            ? 'Recorded as not dispatched, with the reason.'
            : 'Dispatch recorded.',
        tone: _notDispatched ? BannerTone.warning : BannerTone.positive,
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

/// The nine reasons the blueprint allows, and nothing else. Choosing "Other"
/// requires the clerk to say what actually happened.
class _ReasonBlock extends StatelessWidget {
  const _ReasonBlock({
    required this.reason,
    required this.detailController,
    required this.onPick,
    required this.onDetailChanged,
    this.error,
    this.detailError,
  });

  final NotDispatchedReason? reason;
  final TextEditingController detailController;
  final VoidCallback onPick;
  final ValueChanged<String> onDetailChanged;
  final String? error;
  final String? detailError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppBanner(
          tone: BannerTone.warning,
          title: 'A reason is required',
          detail: 'An order recorded as not dispatched must say why, so the '
              'delay can be chased.',
        ),
        const SizedBox(height: Space.lg),
        AppSelectField(
          label: 'Reason',
          value: reason?.label,
          placeholder: 'Choose a reason',
          required: true,
          error: error,
          onTap: onPick,
        ),
        if (reason?.requiresDetail ?? false)
          AppTextField(
            label: 'What happened',
            controller: detailController,
            required: true,
            maxLines: 3,
            error: detailError,
            helper: 'Describe the reason in a sentence.',
            onChanged: onDetailChanged,
          ),
      ],
    );
  }
}

Future<NotDispatchedReason?> _pickReason(
  BuildContext context,
  NotDispatchedReason? selected,
) {
  return showAppSheet<NotDispatchedReason>(
    context,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return AppBottomSheet(
        title: 'Why was it not dispatched',
        child: Column(
          children: [
            for (final reason in NotDispatchedReason.values)
              InkWell(
                onTap: () => Navigator.of(sheetContext).pop(reason),
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: Sizes.rowComfortable),
                  padding:
                      const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          reason.label,
                          style: AppType.rowPrimary.copyWith(color: c.ink),
                        ),
                      ),
                      if (reason == selected)
                        Icon(
                          PhFill.checkCircle,
                          size: Sizes.iconMd,
                          color: c.accentText,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Space.lg),
          ],
        ),
      );
    },
  );
}

String _formatDate(DateTime d) {
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
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
