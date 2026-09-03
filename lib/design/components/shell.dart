import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';

import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';

/// Chrome scales less than content.
///
/// App bars have a fixed height, so at the largest text sizes a title and its
/// subtitle would outgrow the bar. Clamping the scale here keeps the chrome
/// stable and leaves the extra size for the content, which is where reading
/// actually happens. Material's own toolbars do the same.
Widget _chromeTextScale(BuildContext context, Widget child) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(
      textScaler: media.textScaler.clamp(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.3,
      ),
    ),
    child: child,
  );
}

/// The app bar on a top-level destination. The title is the screen name and
/// the trailing slots hold only globally useful actions.
class RootAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RootAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.scrolled = false,
  });

  final String title;

  /// Context that locates the user, such as the plant and shift.
  final String? subtitle;

  final List<Widget> actions;

  /// Raises the bar once content has scrolled beneath it.
  final bool scrolled;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _chromeTextScale(
      context,
      AnimatedContainer(
        duration: Motion.resolve(context, Motion.quick),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(
            bottom: BorderSide(
              color: scrolled ? c.hairline : Colors.transparent,
            ),
          ),
          boxShadow: scrolled ? Elevation.stickyBar(c) : null,
        ),
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.gutter, right: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: AppType.screenTitle.copyWith(color: c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppType.rowSecondary.copyWith(
                            color: c.inkMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app bar on a nested screen. Back is always present, always labelled
/// for assistive technology, and always at least 48dp.
class NestedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NestedAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;

  /// A subtitle needs a taller bar. The height is known at construction
  /// because the subtitle is, so the bar never has to squeeze its own text.
  static const double _tallBar = 68;

  @override
  Size get preferredSize =>
      Size.fromHeight(subtitle == null ? Sizes.appBar : _tallBar);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _chromeTextScale(
      context,
      Container(
        color: c.surface,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: subtitle == null ? Sizes.appBar : _tallBar,
          child: Row(
            children: [
              AppIconButton(
                icon: Ph.arrowLeft,
                semanticLabel: 'Back',
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppType.entityName.copyWith(
                          color: c.ink,
                          fontSize: 20,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppType.helper.copyWith(color: c.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              ...actions,
              const SizedBox(width: Space.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// One top-level destination.
class NavDestination {
  const NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Bottom navigation across the four top-level destinations.
///
/// Every item carries an icon and a text label, and the active item is marked
/// three ways at once: a filled icon, a heavier label and an accent rule. One
/// signal alone would fail for anyone who cannot separate the colours.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: Sizes.bottomNav,
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _NavItem(
                  destination: destinations[i],
                  selected: i == currentIndex,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: Motion.resolve(context, Motion.quick),
                height: 2,
                width: selected ? 32 : 0,
                color: c.accent,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? destination.activeIcon : destination.icon,
                    size: Sizes.iconLg,
                    color: selected ? c.ink : c.inkMuted,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.label,
                    style: AppType.helper.copyWith(
                      fontSize: 11,
                      height: 1.1,
                      color: selected ? c.ink : c.inkMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The standard bottom sheet: a drag handle, a title, scrollable content and
/// a sticky action. Preferred over a dialog for anything the user chooses,
/// because it sits within thumb reach.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Sticky primary action at the foot of the sheet.
  final Widget? action;

  /// A secondary control beside the title, such as a reset.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(color: c.surface, borderRadius: Radii.sheetTop),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: c.hairlineStrong,
                borderRadius: Radii.pillAll,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.sm,
              Space.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: AppType.entityName.copyWith(
                            color: c.ink,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppType.helper.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
                AppIconButton(
                  icon: Ph.x,
                  semanticLabel: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(child: SingleChildScrollView(child: child)),
          if (action != null) StickyActionBar(primary: action!),
        ],
      ),
    );
  }
}

/// Opens a sheet. Dismissal is by drag, by the close button or by tapping the
/// scrim, so there is always more than one way out.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.scrim,
    builder: builder,
  );
}

/// Confirmation before something that cannot easily be undone.
///
/// The destructive choice is worded as the action it performs rather than
/// "OK", and it is visually separated from the safe choice.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final c = context.colors;
      return AlertDialog(
        title: Text(title, style: AppType.entityName.copyWith(color: c.ink)),
        content: Text(
          message,
          style: AppType.rowSecondary.copyWith(color: c.inkSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          Space.lg,
          0,
          Space.lg,
          Space.lg,
        ),
        actions: [
          Column(
            children: [
              AppButton(
                label: confirmLabel,
                kind: ButtonKind.destructive,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: Space.sm),
              AppButton(
                label: cancelLabel,
                kind: ButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Asks before discarding work in progress, so a mis-swipe never costs an
/// operator their entry.
Future<bool> confirmDiscardChanges(BuildContext context) => confirmDestructive(
  context,
  title: 'Discard your changes',
  message:
      'You have entered information that has not been saved. '
      'Leaving now will discard it.',
  confirmLabel: 'Discard',
  cancelLabel: 'Keep editing',
);

/// A simple picker used for master-data selects.
Future<String?> showOptionPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
}) {
  return showAppSheet<String>(
    context,
    builder: (context) {
      final c = context.colors;
      return AppBottomSheet(
        title: title,
        child: Column(
          children: [
            for (final option in options)
              Semantics(
                button: true,
                selected: option == selected,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(option),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: Sizes.rowComfortable,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.gutter,
                      vertical: Space.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: AppType.rowPrimary.copyWith(color: c.ink),
                          ),
                        ),
                        if (option == selected)
                          Icon(
                            PhFill.checkCircle,
                            size: Sizes.iconMd,
                            color: c.accentText,
                          ),
                      ],
                    ),
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
