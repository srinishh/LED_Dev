import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../data/order_repository.dart';
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
import 'quality_screen.dart';

void openStageExecution(
  BuildContext context,
  String orderId,
  StageKey stage,
) {
  // Quality is a checklist rather than a form, so it has its own screen.
  if (stage == StageKey.qualityTesting) {
    openQuality(context, orderId);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StageExecutionScreen(orderId: orderId, stage: stage),
    ),
  );
}

/// The form used to record work at any stage.
///
/// It renders from the stage schema rather than being written ten times, so
/// every stage validates, defaults and saves the same way, and a change to a
/// captured field is a change to data rather than to a screen.
class StageExecutionScreen extends ConsumerStatefulWidget {
  const StageExecutionScreen({
    super.key,
    required this.orderId,
    required this.stage,
  });

  final String orderId;
  final StageKey stage;

  @override
  ConsumerState<StageExecutionScreen> createState() =>
      _StageExecutionScreenState();
}

class _StageExecutionScreenState extends ConsumerState<StageExecutionScreen> {
  late final StageSchema _schema = schemaFor(widget.stage);

  /// The working copy. Nothing is written until the user saves, and nothing
  /// is lost if they leave the screen and come back.
  final Map<String, Object?> _values = {};
  final Map<String, SubRecordState> _subRecords = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _errors = {};

  String _status = '';
  var _subIndex = 0;
  var _dirty = false;
  var _busy = false;
  var _submitted = false;

  /// The order may not have loaded when this screen is first built, so the
  /// form seeds itself the first time it actually has one. Seeding in
  /// initState alone would leave every field blank whenever the screen is
  /// opened from a cold start or a deep link.
  var _seeded = false;

  void _seedFrom(Order order) {
    if (_seeded) return;
    _seeded = true;

    final record = order.stage(widget.stage);
    _status = record.status;
    _values.addAll(record.values);
    _subRecords.addAll(record.subRecords);

    // Anything the app can fill in, it fills in, so the operator types as
    // little as possible.
    _applyDefaults(order);

    for (final sub in _schema.subRecords) {
      _subRecords.putIfAbsent(
        sub.key,
        () => SubRecordState(key: sub.key, status: sub.initialStatus),
      );
    }
  }

  void _applyDefaults(Order order) {
    final user = ref.read(currentUserProvider);
    final now = DateTime.now();

    for (final field in _allFields) {
      if (_values[field.key] != null) continue;
      final value = switch (field.defaultSource) {
        DefaultSource.orderNumber => order.orderNo,
        DefaultSource.orderCustomer => order.customer,
        DefaultSource.orderProduct => order.product,
        DefaultSource.orderQuantity => order.quantity,
        DefaultSource.sessionUser => user.name,
        DefaultSource.sessionMachine => user.machine,
        DefaultSource.today => DateTime(now.year, now.month, now.day),
        DefaultSource.now => now,
        DefaultSource.lastUsed => null,
        DefaultSource.carriedForward => _carriedValue(order, field),
        DefaultSource.none => null,
      };
      if (value != null) _values[field.key] = value;
    }
  }

  /// Pulls a value forward from an earlier stage, so the same number is never
  /// entered twice.
  Object? _carriedValue(Order order, FieldSchema field) {
    final from = field.carriedFrom;
    if (from == null) return null;

    // Grinding starts from what welding finished.
    if (widget.stage == StageKey.weldingGrinding &&
        field.key == 'quantityReceived') {
      return _subRecords['welding']?.values['quantity'] ?? order.quantity;
    }
    return order.stage(from).values[field.key];
  }

  List<FieldSchema> get _allFields => _schema.subRecords.isEmpty
      ? _schema.fields
      : [for (final sub in _schema.subRecords) ...sub.fields];

  bool get _hasSubRecords => _schema.subRecords.isNotEmpty;

  StageSubRecord? get _activeSub =>
      _hasSubRecords ? _schema.subRecords[_subIndex] : null;

  TextEditingController _controllerFor(FieldSchema field, Object? value) {
    return _controllers.putIfAbsent(
      field.key,
      () => TextEditingController(text: _display(value, field)),
    );
  }

  Map<String, Object?> get _activeValues {
    final sub = _activeSub;
    if (sub == null) return _values;
    return _subRecords[sub.key]?.values ?? const {};
  }

  void _setValue(FieldSchema field, Object? value) {
    setState(() {
      _dirty = true;
      final sub = _activeSub;
      if (sub == null) {
        _values[field.key] = value;
      } else {
        final current = _subRecords[sub.key] ??
            SubRecordState(key: sub.key, status: sub.initialStatus);
        _subRecords[sub.key] = current.copyWith(
          values: {...current.values, field.key: value},
        );
      }
      _errors.remove(field.key);
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    final user = ref.watch(currentUserProvider);

    if (order == null) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: NestedAppBar(title: _schema.name),
        body: const AppErrorState(
          message: 'This order is no longer available.',
        ),
      );
    }

    _seedFrom(order);

    final permission = Rules.canExecuteStage(user, order, widget.stage);
    if (permission.blocked) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: NestedAppBar(title: _schema.name, subtitle: order.orderNo),
        body: AppPermissionState(message: permission.reason!),
      );
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        // Work in progress is never discarded silently.
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.surface,
        appBar: NestedAppBar(
          title: _schema.name,
          subtitle: order.orderNo,
        ),
        body: Column(
          children: [
            if (_dirty) const _DraftIndicator(),
            Expanded(child: _buildForm(order)),
          ],
        ),
        bottomNavigationBar: _buildActions(order),
      ),
    );
  }

  Widget _buildForm(Order order) {
    final sub = _activeSub;

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        if (_schema.note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.lg,
            ),
            child: AppBanner(title: 'How this stage works', detail: _schema.note),
          ),

        // Two-part stages get tabs inside one shell rather than two screens,
        // because they are one stage to the person doing the work.
        if (_hasSubRecords) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: AppSegmentedControl<int>(
              values: [
                for (var i = 0; i < _schema.subRecords.length; i++) i,
              ],
              selected: _subIndex,
              labelOf: (i) => _schema.subRecords[i].name,
              onChanged: (i) => setState(() => _subIndex = i),
            ),
          ),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: AppBanner(
              title: 'Overall stage: '
                  '${Rules.deriveWeldingGrindingStatus(_subRecords)}',
              detail: 'This follows welding and grinding together and cannot '
                  'be set directly.',
            ),
          ),
          const SizedBox(height: Space.xl),
        ],

        // Status uses the stage's own vocabulary, shown in full so the
        // operator sees every state the stage can be in.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: sub == null ? 'Status' : '${sub.name} status',
                padding: const EdgeInsets.only(bottom: Space.md),
              ),
              AppSegmentedControl<String>(
                values: (sub ?? _schema).let(
                  (s) => s is StageSubRecord
                      ? s.statusValues
                      : _schema.statusValues,
                ),
                selected: sub == null
                    ? _status
                    : _subRecords[sub.key]?.status ?? sub.initialStatus,
                labelOf: (v) => v,
                onChanged: (value) => setState(() {
                  _dirty = true;
                  if (sub == null) {
                    _status = value;
                  } else {
                    final current = _subRecords[sub.key] ??
                        SubRecordState(key: sub.key, status: sub.initialStatus);
                    _subRecords[sub.key] = current.copyWith(status: value);
                  }
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),

        ..._buildFieldsets(order, sub),
      ],
    );
  }

  List<Widget> _buildFieldsets(Order order, StageSubRecord? sub) {
    final fields = sub?.fields ?? _schema.fields;
    final groups = <String>[];
    for (final field in fields) {
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
              for (final field in fields)
                if ((field.group ?? 'Details') == group)
                  _buildField(order, field),
            ],
          ),
        ),
    ];
  }

  Widget _buildField(Order order, FieldSchema field) {
    final value = _activeValues[field.key];
    final error = _submitted ? _errors[field.key] : null;
    final source = field.carriedFrom == null
        ? null
        : schemaFor(field.carriedFrom!).name;

    switch (field.type) {
      case FieldType.select:
        final selected = value is String ? value : null;
        return AppSelectField(
          label: field.label,
          value: selected,
          required: _isRequired(field),
          readOnly: field.readOnly,
          source: source,
          helper: field.helper,
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
              _setValue(field, picked);
              _autoFillPaintCode(field, picked);
            }
          },
        );

      case FieldType.date:
      case FieldType.dateTime:
        final asDate = value is DateTime ? value : null;
        return AppSelectField(
          label: field.label,
          value: value == null ? null : _display(value, field),
          placeholder: 'Choose a date',
          required: _isRequired(field),
          readOnly: field.readOnly,
          source: source,
          helper: field.helper,
          error: error,
          onTap: () => _pickDateTime(field, asDate),
        );

      case FieldType.boolean:
        return _VerificationField(
          field: field,
          verified: value == true,
          expected: _values['labelNumber'] as String?,
          onVerified: () => _setValue(field, true),
          error: error,
        );

      case FieldType.componentList:
        return _ComponentListField(
          field: field,
          values: (value as List?)?.cast<String>() ?? const [],
          error: error,
          onChanged: (list) => _setValue(field, list),
        );

      case FieldType.attachment:
        return _AttachmentField(
          field: field,
          value: value as String?,
          error: error,
          onChanged: (v) => _setValue(field, v),
        );

      case FieldType.integer:
      case FieldType.phone:
      case FieldType.text:
      case FieldType.multiline:
        return AppTextField(
          label: field.label,
          controller: _controllerFor(field, value),
          required: _isRequired(field),
          readOnly: field.readOnly,
          source: source,
          helper: field.helper,
          error: error,
          warning: _warningFor(field),
          unit: field.unit,
          maxLines: field.type == FieldType.multiline ? 4 : 1,
          keyboardType: switch (field.type) {
            FieldType.integer => TextInputType.number,
            FieldType.phone => TextInputType.phone,
            FieldType.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
          onChanged: (raw) {
            final parsed = field.type == FieldType.integer
                ? int.tryParse(raw)
                : raw;
            _setValue(field, parsed);
          },
          // Validation waits for the user to finish the field rather than
          // correcting them mid-word.
          onEditingComplete: () => setState(() {}),
        );
    }
  }

  /// Choosing a colour fills in its code, which the operator can still change
  /// if the batch differs.
  void _autoFillPaintCode(FieldSchema field, String picked) {
    if (field.key != 'paintColour') return;
    final code = ref.read(repositoryProvider).masters.paintCodes[picked];
    if (code == null) return;
    _values['paintCode'] = code;
    _controllers['paintCode']?.text = code;
  }

  /// A non-blocking note, shown while the value is still acceptable but worth
  /// a second look.
  String? _warningFor(FieldSchema field) {
    if (field.key != 'actualQuantityCut') return null;
    final actual = _values['actualQuantityCut'];
    final required = _values['requiredCuttingQuantity'];
    if (actual is! int || required is! int || actual <= required) return null;
    return 'Exceeds the required quantity by ${actual - required}. Add a '
        'remark to record why.';
  }

  bool _isRequired(FieldSchema field) =>
      field.requirement == Requirement.required ||
      field.requirement == Requirement.requiredToComplete;

  Future<void> _pickDateTime(FieldSchema field, DateTime? current) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (date == null || !mounted) return;

    if (field.type == FieldType.date) {
      _setValue(field, date);
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (!mounted) return;
    _setValue(
      field,
      DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 0,
        time?.minute ?? 0,
      ),
    );
  }

  Widget _buildActions(Order order) {
    final blockers = Rules.canCompleteStage(
      order,
      widget.stage,
      values: _values,
      subRecords: _subRecords,
    );
    final wantsCompletion = _status == _schema.terminalStatus;

    return StickyActionBar(
      primary: AppButton(
        label: wantsCompletion ? 'Mark completed' : 'Save',
        busy: _busy,
        // Saving progress is always allowed; only completion is gated.
        onPressed:
            (wantsCompletion && blockers.blocked) ? null : () => _save(order),
        disabledReason: wantsCompletion ? blockers.reason : null,
      ),
      secondary: _dirty
          ? AppButton(
              label: 'Discard changes',
              kind: ButtonKind.tertiary,
              onPressed: () async {
                if (await confirmDiscardChanges(context) && mounted) {
                  Navigator.of(context).pop();
                }
              },
            )
          : null,
    );
  }

  Future<void> _save(Order order) async {
    setState(() {
      _submitted = true;
      _busy = true;
      _errors.clear();
    });

    final blockers = Rules.canCompleteStage(
      order,
      widget.stage,
      values: _values,
      subRecords: _subRecords,
    );
    if (_status == _schema.terminalStatus && blockers.blocked) {
      setState(() {
        _busy = false;
        for (final violation in blockers) {
          if (violation.field != null) {
            _errors[violation.field!] = violation.message;
          }
        }
      });
      return;
    }

    try {
      await ref.read(orderActionsProvider).saveStage(
            order.id,
            StageRecord(
              stageKey: widget.stage,
              status: _status,
              values: _values,
              subRecords: _subRecords,
              startedAt: order.stage(widget.stage).startedAt ?? DateTime.now(),
              completedAt: _status == _schema.terminalStatus
                  ? DateTime.now()
                  : null,
            ),
          );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _dirty = false);
      showAppToast(context, message: '${_schema.name} saved.');
      Navigator.of(context).pop();
    } on PermissionFailure catch (e) {
      if (mounted) {
        showAppToast(context, message: e.message, tone: BannerTone.critical);
      }
    } on RepositoryFailure catch (e) {
      // The entry stays on screen so nothing the operator typed is lost.
      if (mounted) {
        showAppToast(context, message: e.message, tone: BannerTone.critical);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _display(Object? value, FieldSchema field) {
    if (value == null) return '';
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
      final date = '${value.day} ${months[value.month - 1]}';
      if (field.type == FieldType.date) return date;
      final hh = value.hour.toString().padLeft(2, '0');
      final mm = value.minute.toString().padLeft(2, '0');
      return '$date, $hh:$mm';
    }
    if (value is List) return value.join(', ');
    return '$value';
  }
}

/// Small helper so a nullable schema can be branched on inline.
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

/// Confirms the draft is being kept, so leaving the screen does not feel
/// risky.
class _DraftIndicator extends StatelessWidget {
  const _DraftIndicator();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.accentWash,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Icon(
            Ph.floppyDisk,
            size: Sizes.iconSm,
            color: c.accentText,
          ),
          const SizedBox(width: Space.sm),
          Text(
            'Draft kept on this device.',
            style: AppType.helper.copyWith(color: c.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// The label verification step. The number must be scanned or typed to match,
/// so confirming is a deliberate act rather than a tick box.
class _VerificationField extends StatefulWidget {
  const _VerificationField({
    required this.field,
    required this.verified,
    required this.onVerified,
    this.expected,
    this.error,
  });

  final FieldSchema field;
  final bool verified;
  final String? expected;
  final VoidCallback onVerified;
  final String? error;

  @override
  State<_VerificationField> createState() => _VerificationFieldState();
}

class _VerificationFieldState extends State<_VerificationField> {
  final _controller = TextEditingController();
  String? _mismatch;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    final entered = _controller.text.trim();
    final expected = widget.expected?.trim();
    if (expected == null || expected.isEmpty) {
      setState(() => _mismatch = 'Enter the label number above first.');
      return;
    }
    if (entered.toUpperCase() == expected.toUpperCase()) {
      setState(() => _mismatch = null);
      widget.onVerified();
    } else {
      setState(() => _mismatch =
          'That does not match the label number on this order ($expected).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (widget.verified) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: AppBanner(
          tone: BannerTone.positive,
          title: 'Label verified',
          detail: 'The printed label matches this order.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: widget.field.label,
            controller: _controller,
            required: true,
            helper: widget.field.helper,
            error: _mismatch ?? widget.error,
          ),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Scan label',
                  kind: ButtonKind.secondary,
                  icon: Ph.barcode,
                  onPressed: () => showAppToast(
                    context,
                    message: 'Scanner not connected. Type the number instead.',
                    tone: BannerTone.info,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: AppButton(
                  label: 'Confirm',
                  kind: ButtonKind.secondary,
                  onPressed: _check,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Verification is required before the order can be marked ready '
            'for dispatch.',
            style: AppType.helper.copyWith(color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// A repeatable list, used for the components consumed during assembly.
class _ComponentListField extends ConsumerWidget {
  const _ComponentListField({
    required this.field,
    required this.values,
    required this.onChanged,
    this.error,
  });

  final FieldSchema field;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                field.label.toUpperCase(),
                style: AppType.fieldLabel.copyWith(color: c.inkFaint),
              ),
              Text(
                ' *',
                style: AppType.fieldLabel.copyWith(color: c.failedText),
                semanticsLabel: ' required',
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final entry in values)
            Container(
              constraints: const BoxConstraints(minHeight: Sizes.touchMin),
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry,
                      style: AppType.fieldValue.copyWith(color: c.ink),
                    ),
                  ),
                  AppIconButton(
                    icon: Ph.x,
                    semanticLabel: 'Remove $entry',
                    onPressed: () =>
                        onChanged([...values]..remove(entry)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.sm),
          AppButton(
            label: 'Add component',
            kind: ButtonKind.secondary,
            icon: Ph.plus,
            onPressed: () async {
              final options =
                  ref.read(repositoryProvider).masters.components;
              final picked = await showOptionPicker(
                context,
                title: 'Component used',
                options: options,
              );
              if (picked != null) onChanged([...values, picked]);
            },
          ),
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              error!,
              style: AppType.helper.copyWith(color: c.failedText),
            ),
          ],
        ],
      ),
    );
  }
}

/// Proof of delivery. A photograph or a signature, captured at the door.
class _AttachmentField extends StatelessWidget {
  const _AttachmentField({
    required this.field,
    required this.onChanged,
    this.value,
    this.error,
  });

  final FieldSchema field;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                field.label.toUpperCase(),
                style: AppType.fieldLabel.copyWith(color: c.inkFaint),
              ),
              Text(
                ' *',
                style: AppType.fieldLabel.copyWith(color: c.failedText),
                semanticsLabel: ' required',
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (value != null)
            AppBanner(
              tone: BannerTone.positive,
              title: value!,
              detail: 'Attached to this delivery.',
              icon: Ph.paperclip,
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Photograph',
                    kind: ButtonKind.secondary,
                    icon: Ph.camera,
                    onPressed: () => onChanged('Signed challan photo'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: AppButton(
                    label: 'Signature',
                    kind: ButtonKind.secondary,
                    icon: Ph.signature,
                    onPressed: () => onChanged('Recipient signature'),
                  ),
                ),
              ],
            ),
          if (field.helper != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              field.helper!,
              style: AppType.helper.copyWith(color: c.inkMuted),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              error!,
              style: AppType.helper.copyWith(color: c.failedText),
            ),
          ],
        ],
      ),
    );
  }
}
