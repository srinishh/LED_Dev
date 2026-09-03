import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/order_repository.dart';
import '../../data/seed_data.dart';
import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/inputs.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';
import 'order_detail_screen.dart';

/// Raises a new jobsheet.
void openNewJobsheet(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const JobsheetScreen()),
  );
}

/// Corrects an existing one.
void openEditJobsheet(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JobsheetScreen(orderId: orderId),
    ),
  );
}

/// The jobsheet: what is being made, for whom, by when, from what.
///
/// Deliberately short. It asks only what the planner knows when the order is
/// raised; everything else is recorded by the floor as the work happens, so
/// this screen never becomes the place where the whole order is typed in.
///
/// Choosing a product fills in the material and the order number fills in
/// itself, so a complete jobsheet is four decisions rather than eleven fields.
class JobsheetScreen extends ConsumerStatefulWidget {
  const JobsheetScreen({super.key, this.orderId});

  /// Null when raising a new jobsheet.
  final String? orderId;

  @override
  ConsumerState<JobsheetScreen> createState() => _JobsheetScreenState();
}

class _JobsheetScreenState extends ConsumerState<JobsheetScreen> {
  NewOrderDraft _draft = const NewOrderDraft();
  final _quantity = TextEditingController();
  final _poNumber = TextEditingController();
  final _notes = TextEditingController();

  var _seeded = false;
  var _dirty = false;
  var _busy = false;
  var _submitted = false;
  String? _failure;

  bool get _isEdit => widget.orderId != null;

  void _seedFrom(Order order) {
    if (_seeded) return;
    _seeded = true;
    final material = order.stage(StageKey.rawMaterial).values;
    _draft = NewOrderDraft(
      orderNo: order.orderNo,
      customer: order.customer,
      product: order.product,
      quantity: order.quantity,
      priority: order.priority,
      dueAt: order.dueAt,
      materialName: material['materialName'] as String?,
      materialCode: material['materialCode'] as String?,
      supplier: material['supplier'] as String?,
      purchaseOrderNumber: material['purchaseOrderNumber'] as String?,
      notes: order.notes,
    );
    _quantity.text = '${order.quantity}';
    _poNumber.text = _draft.purchaseOrderNumber ?? '';
    _notes.text = order.notes ?? '';
  }

  @override
  void dispose() {
    _quantity.dispose();
    _poNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _update(NewOrderDraft next) => setState(() {
        _draft = next;
        _dirty = true;
        _failure = null;
      });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final order =
        widget.orderId == null ? null : ref.watch(orderProvider(widget.orderId!));

    if (_isEdit && order == null) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: const NestedAppBar(title: 'Jobsheet'),
        body: const AppErrorState(
          message: 'This order is no longer available.',
        ),
      );
    }
    if (order != null) _seedFrom(order);

    if (!user.isManager) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        appBar: NestedAppBar(title: _isEdit ? 'Edit jobsheet' : 'New jobsheet'),
        body: const AppPermissionState(
          message: 'Jobsheets are raised and revised by a manager. Ask a '
              'supervisor to make the change.',
        ),
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
        appBar: NestedAppBar(
          title: _isEdit ? 'Edit jobsheet' : 'New jobsheet',
          subtitle: _isEdit ? order!.orderNo : null,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: Space.xl),
          children: [
            if (_isEdit && order!.completedStageCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.lg,
                ),
                child: AppBanner(
                  tone: BannerTone.warning,
                  title: 'Work has already started',
                  detail: '${order.completedStageCount} of 10 stages are '
                      'done. Changes are recorded on the timeline so the '
                      'floor can see what moved.',
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Fieldset(
                title: 'The order',
                children: [
                  AppSelectField(
                    label: 'Customer',
                    value: _draft.customer,
                    placeholder: 'Choose a customer',
                    required: true,
                    error: _errorFor('customer'),
                    onTap: () => _pick(
                      'Customer',
                      ref.read(repositoryProvider).masters.customers,
                      _draft.customer,
                      (v) => _update(_draft.copyWith(customer: v)),
                    ),
                  ),
                  AppSelectField(
                    label: 'Product',
                    value: _draft.product,
                    placeholder: 'Choose a product',
                    required: true,
                    error: _errorFor('product'),
                    helper: 'Choosing a product fills in the material it is '
                        'made from.',
                    onTap: () => _pick(
                      'Product',
                      ref.read(repositoryProvider).masters.products,
                      _draft.product,
                      _onProductChosen,
                    ),
                  ),
                  AppTextField(
                    label: 'Quantity',
                    controller: _quantity,
                    required: true,
                    unit: 'pcs',
                    keyboardType: TextInputType.number,
                    error: _errorFor('quantity'),
                    onChanged: (raw) =>
                        _update(_draft.copyWith(quantity: int.tryParse(raw))),
                  ),
                  AppSelectField(
                    label: 'Due date',
                    value: _draft.dueAt == null
                        ? null
                        : _formatDate(_draft.dueAt!),
                    placeholder: 'Choose a date',
                    required: true,
                    error: _errorFor('due'),
                    onTap: _pickDueDate,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRIORITY',
                          style: AppType.fieldLabel
                              .copyWith(color: context.colors.inkFaint),
                        ),
                        const SizedBox(height: Space.sm),
                        AppSegmentedControl<Priority>(
                          values: Priority.values,
                          selected: _draft.priority,
                          equalWidth: true,
                          labelOf: (p) => p.label,
                          onChanged: (p) =>
                              _update(_draft.copyWith(priority: p)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Everything below is optional, and says so, because a jobsheet
            // should be raiseable the moment the order comes in.
            ExpandableSection(
              title: 'Material and procurement',
              subtitle: 'optional',
              initiallyExpanded: _isEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Column(
                  children: [
                    AppTextField(
                      label: 'Material',
                      initialValue: _draft.materialName,
                      key: ValueKey('material-${_draft.materialName}'),
                      helper: 'Filled from the product. Change it if this '
                          'job differs.',
                      onChanged: (v) =>
                          _update(_draft.copyWith(materialName: v)),
                    ),
                    AppSelectField(
                      label: 'Supplier',
                      value: _draft.supplier,
                      placeholder: 'Choose a supplier',
                      onTap: () => _pick(
                        'Supplier',
                        ref.read(repositoryProvider).masters.suppliers,
                        _draft.supplier,
                        (v) => _update(_draft.copyWith(supplier: v)),
                      ),
                    ),
                    AppTextField(
                      label: 'Purchase order number',
                      controller: _poNumber,
                      onChanged: (v) => _update(
                          _draft.copyWith(purchaseOrderNumber: v)),
                    ),
                  ],
                ),
              ),
            ),
            ExpandableSection(
              title: 'Notes',
              subtitle: 'optional',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: AppTextField(
                  label: 'Notes',
                  controller: _notes,
                  maxLines: 3,
                  helper: 'Anything the floor should know before starting.',
                  onChanged: (v) => _update(_draft.copyWith(notes: v)),
                ),
              ),
            ),

            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(Space.gutter),
                child: AppBanner(
                  tone: BannerTone.critical,
                  title: 'Could not save',
                  detail: _failure,
                ),
              ),
          ],
        ),
        bottomNavigationBar: StickyActionBar(
          primary: AppButton(
            label: _isEdit ? 'Save changes' : 'Raise jobsheet',
            busy: _busy,
            onPressed: _draft.isComplete ? _save : null,
            disabledReason:
                _draft.isComplete ? null : _draft.missing.first,
          ),
        ),
      ),
    );
  }

  /// The material a product is made from is known, so it is filled in rather
  /// than asked for.
  void _onProductChosen(String product) {
    final material = materialForProduct(product);
    _update(_draft.copyWith(
      product: product,
      materialName: material.name,
      materialCode: material.code,
    ));
  }

  String? _errorFor(String field) {
    if (!_submitted) return null;
    return switch (field) {
      'customer' when _draft.customer == null => 'Choose a customer.',
      'product' when _draft.product == null => 'Choose a product.',
      'quantity' when (_draft.quantity ?? 0) <= 0 =>
        'Enter how many are ordered.',
      'due' when _draft.dueAt == null => 'Choose the date it is due.',
      _ => null,
    };
  }

  Future<void> _pick(
    String title,
    List<String> options,
    String? selected,
    ValueChanged<String> onPicked,
  ) async {
    final picked = await showOptionPicker(
      context,
      title: title,
      options: options,
      selected: selected,
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.dueAt ?? now.add(const Duration(days: 14)),
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) _update(_draft.copyWith(dueAt: picked));
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _busy = true;
      _failure = null;
    });

    try {
      final actions = ref.read(orderActionsProvider);
      final order = _isEdit
          ? await actions.updateOrderDetails(widget.orderId!, _draft)
          : await actions.createOrder(_draft);

      if (!mounted) return;
      setState(() => _dirty = false);
      Navigator.of(context).pop();

      if (_isEdit) {
        showAppToast(context, message: 'Jobsheet updated.');
      } else {
        // A new jobsheet is opened straight away, because raising one is
        // almost always followed by looking at it.
        showAppToast(context, message: '${order.orderNo} raised.');
        openOrder(context, order.id);
      }
    } on PermissionFailure catch (e) {
      if (mounted) setState(() => _failure = e.message);
    } on RepositoryFailure catch (e) {
      if (mounted) setState(() => _failure = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
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
