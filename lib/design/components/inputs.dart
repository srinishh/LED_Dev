import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';

import '../theme.dart';
import '../tokens.dart';

/// A labelled input.
///
/// The label is always visible above the field, never a placeholder that
/// vanishes on focus. Errors sit directly below the field they belong to and
/// state both the cause and the fix. Validation runs on blur rather than on
/// each keystroke, so the field does not scold the user mid-word.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.helper,
    this.error,
    this.warning,
    this.unit,
    this.required = false,
    this.readOnly = false,
    this.source,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.onEditingComplete,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;

  /// Persistent guidance, shown whether or not the field is focused.
  final String? helper;

  /// Blocking problem. Replaces the helper and turns the border.
  final String? error;

  /// Non-blocking note, such as a quantity above the requirement.
  final String? warning;

  /// Trailing unit, for example "pcs".
  final String? unit;

  final bool required;

  /// Read-only fields stay visible with their source named, so the operator
  /// sees where a value came from. This is distinct from disabled.
  final bool readOnly;
  final String? source;

  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.initialValue);
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _focused = _focus.hasFocus);
    // Validation is deferred until the user leaves the field.
    if (!_focus.hasFocus) widget.onEditingComplete?.call();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = widget.error != null;
    final hasWarning = !hasError && widget.warning != null;

    final borderColour = hasError
        ? c.failedFill
        : hasWarning
            ? c.onHoldFill
            : _focused
                ? c.accent
                : c.hairline;
    final borderWidth = (hasError || hasWarning || _focused) ? 2.0 : 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            label: widget.label,
            required: widget.required,
            source: widget.source,
            readOnly: widget.readOnly,
          ),
          const SizedBox(height: Space.sm),
          Container(
            constraints: BoxConstraints(
              minHeight: widget.maxLines > 1 ? 96 : Sizes.control,
            ),
            decoration: BoxDecoration(
              color: widget.readOnly ? c.raised : c.surface,
              borderRadius: Radii.controlAll,
              border: Border.all(color: borderColour, width: borderWidth),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Row(
              crossAxisAlignment: widget.maxLines > 1
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    readOnly: widget.readOnly,
                    autofocus: widget.autofocus,
                    keyboardType: widget.keyboardType,
                    maxLines: widget.maxLines,
                    minLines: widget.maxLines > 1 ? 3 : 1,
                    onChanged: widget.onChanged,
                    style: (widget.keyboardType == TextInputType.number ||
                                widget.keyboardType == TextInputType.phone
                            ? AppType.numeric(AppType.fieldValue)
                            : AppType.fieldValue)
                        .copyWith(
                      color: widget.readOnly ? c.inkSecondary : c.ink,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: widget.maxLines > 1 ? Space.md : Space.lg,
                      ),
                    ),
                  ),
                ),
                if (widget.unit != null) ...[
                  const SizedBox(width: Space.sm),
                  Text(
                    widget.unit!,
                    style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                  ),
                ],
                if (widget.readOnly) ...[
                  const SizedBox(width: Space.sm),
                  Icon(
                    Ph.lock,
                    size: Sizes.iconSm,
                    color: c.inkFaint,
                  ),
                ],
              ],
            ),
          ),
          _FieldMessage(
            error: widget.error,
            warning: widget.warning,
            helper: widget.helper,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    this.required = false,
    this.source,
    this.readOnly = false,
  });

  final String label;
  final bool required;
  final String? source;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Flexible(
          child: Text(
            label.toUpperCase(),
            style: AppType.fieldLabel.copyWith(color: c.inkFaint),
          ),
        ),
        if (required)
          Text(
            ' *',
            style: AppType.fieldLabel.copyWith(color: c.failedText),
            semanticsLabel: ' required',
          ),
        if (source != null) ...[
          const SizedBox(width: Space.sm),
          Text(
            'from $source',
            style: AppType.helper.copyWith(color: c.inkFaint, fontSize: 11),
          ),
        ] else if (readOnly) ...[
          const SizedBox(width: Space.sm),
          Text(
            'set automatically',
            style: AppType.helper.copyWith(color: c.inkFaint, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Error, warning or helper text below a field. Only one shows at a time, and
/// errors always win.
class _FieldMessage extends StatelessWidget {
  const _FieldMessage({this.error, this.warning, this.helper});

  final String? error;
  final String? warning;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (text, colour, icon) = error != null
        ? (error!, c.failedText, PhFill.warningCircle)
        : warning != null
            ? (warning!, c.onHoldText, Ph.warning)
            : helper != null
                ? (helper!, c.inkMuted, null)
                : (null, c.inkMuted, null);

    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Semantics(
        liveRegion: error != null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: Sizes.iconSm, color: colour),
              ),
              const SizedBox(width: Space.sm),
            ],
            Expanded(
              child: Text(text, style: AppType.helper.copyWith(color: colour)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A value chosen from master data. Opens a sheet rather than a dropdown, so
/// the list is reachable with one thumb and readable at arm's length.
class AppSelectField extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Choose',
    this.helper,
    this.error,
    this.required = false,
    this.readOnly = false,
    this.source,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final String placeholder;
  final String? helper;
  final String? error;
  final bool required;
  final bool readOnly;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = error != null;
    final empty = value == null || value!.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            label: label,
            required: required,
            source: source,
            readOnly: readOnly,
          ),
          const SizedBox(height: Space.sm),
          Semantics(
            button: !readOnly,
            label: '$label, ${empty ? 'not set' : value}',
            excludeSemantics: true,
            child: InkWell(
              onTap: readOnly ? null : onTap,
              borderRadius: Radii.controlAll,
              child: Container(
                height: Sizes.control,
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                decoration: BoxDecoration(
                  color: readOnly ? c.raised : c.surface,
                  borderRadius: Radii.controlAll,
                  border: Border.all(
                    color: hasError ? c.failedFill : c.hairline,
                    width: hasError ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        empty ? placeholder : value!,
                        style: AppType.fieldValue.copyWith(
                          color: empty
                              ? c.inkFaint
                              : (readOnly ? c.inkSecondary : c.ink),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      readOnly
                          ? Ph.lock
                          : Ph.caretDown,
                      size: Sizes.iconMd,
                      color: c.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _FieldMessage(error: error, helper: helper),
        ],
      ),
    );
  }
}

/// Search. Debounced by the caller; this only owns presentation and the
/// clear affordance.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: Sizes.searchField,
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: Radii.controlAll,
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          Icon(
            Ph.magnifyingGlass,
            size: Sizes.iconMd,
            color: c.inkMuted,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                setState(() {});
                widget.onChanged(v);
              },
              style: AppType.rowPrimary.copyWith(color: c.ink),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppType.rowPrimary.copyWith(color: c.inkFaint),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            Semantics(
              button: true,
              label: 'Clear search',
              child: InkResponse(
                onTap: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                radius: 20,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xs),
                  child: Icon(
                    Ph.x,
                    size: Sizes.iconMd,
                    color: c.inkMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A choice between a small number of values, each visible at once. Used for
/// stage status, where seeing the whole vocabulary matters.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.enabledOf,
    this.equalWidth = false,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// Lets a caller grey out a value that is not currently reachable.
  final bool Function(T)? enabledOf;

  /// Splits the available width evenly between the segments. Used where the
  /// control is a view switch rather than one field among many, so that it
  /// reads as a control for the whole screen.
  final bool equalWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: Radii.controlAll,
      ),
      child: equalWidth
          ? Row(
              children: [
                for (final value in values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.xxs,
                      ),
                      child: _Segment(
                        label: labelOf(value),
                        selected: value == selected,
                        enabled: enabledOf?.call(value) ?? true,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(value);
                        },
                      ),
                    ),
                  ),
              ],
            )
          : Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final value in values)
                  _Segment(
                    label: labelOf(value),
                    selected: value == selected,
                    enabled: enabledOf?.call(value) ?? true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(value);
                    },
                  ),
              ],
            ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: Radii.controlAll,
        child: AnimatedContainer(
          duration: Motion.resolve(context, Motion.quick),
          curve: Motion.enter,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: selected ? c.surface : Colors.transparent,
            borderRadius: Radii.controlAll,
            border: selected ? Border.all(color: c.accent, width: 1.5) : null,
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: AppType.status.copyWith(
                color: !enabled
                    ? c.inkDisabled
                    : selected
                        ? c.ink
                        : c.inkMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter or choice chip.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// When present the chip shows a clear affordance, used for active filters.
  final VoidCallback? onRemove;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.pillAll,
        child: AnimatedContainer(
          duration: Motion.resolve(context, Motion.quick),
          height: Sizes.chip,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: selected ? c.accentWash : Colors.transparent,
            borderRadius: Radii.pillAll,
            border: Border.all(
              color: selected ? c.accent : c.hairlineStrong,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(
                  Ph.check,
                  size: Sizes.iconSm,
                  color: c.accentText,
                ),
                const SizedBox(width: Space.xs + 2),
              ],
              Text(
                label,
                style: AppType.status.copyWith(
                  color: selected ? c.ink : c.inkSecondary,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: Space.sm),
                Text(
                  '$count',
                  style: AppType.numeric(AppType.status)
                      .copyWith(color: c.inkMuted),
                ),
              ],
              if (onRemove != null) ...[
                const SizedBox(width: Space.xs),
                Semantics(
                  button: true,
                  label: 'Remove $label filter',
                  child: InkResponse(
                    onTap: onRemove,
                    radius: 16,
                    child: Icon(
                      Ph.x,
                      size: Sizes.iconSm,
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
