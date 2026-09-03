import 'package:flutter/material.dart';

import '../icons.dart';

import '../../domain/status_projection.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'status.dart';

/// Severity of a banner, which sets its rule colour and icon.
enum BannerTone { critical, warning, info, positive }

/// A banner with a coloured left rule.
///
/// Exceptions get this treatment rather than a card, so that on a dashboard
/// of otherwise flat content they are unmistakably the thing to look at.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.title,
    this.detail,
    this.tone = BannerTone.info,
    this.count,
    this.onTap,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String? detail;
  final BannerTone tone;
  final int? count;
  final VoidCallback? onTap;
  final IconData? icon;

  /// A single line, for lists of exception groups where the explanation adds
  /// height without adding information.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (rule, text, defaultIcon) = switch (tone) {
      BannerTone.critical => (
          c.failedFill,
          c.failedText,
          PhFill.warning,
        ),
      BannerTone.warning => (
          c.onHoldFill,
          c.onHoldText,
          PhFill.pause,
        ),
      BannerTone.positive => (
          c.completedFill,
          c.completedText,
          PhFill.checkCircle,
        ),
      BannerTone.info => (
          c.accent,
          c.inkSecondary,
          Ph.info,
        ),
    };

    return Semantics(
      button: onTap != null,
      label: '$title${detail == null ? '' : '. $detail'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.controlAll,
        child: Container(
          constraints: BoxConstraints(
            minHeight: compact ? Sizes.touchMin : Sizes.rowComfortable,
          ),
          decoration: BoxDecoration(
            color: rule.withValues(alpha: 0.07),
            borderRadius: Radii.controlAll,
            border: Border(left: BorderSide(color: rule, width: 4)),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: compact ? Space.sm : Space.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon ?? defaultIcon, size: Sizes.iconMd, color: text),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: AppType.rowPrimary.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail != null && !compact) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        detail!,
                        style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: Space.md),
                Text(
                  '$count',
                  style: AppType.numeric(AppType.entityName)
                      .copyWith(color: text),
                ),
              ],
              if (onTap != null) ...[
                const SizedBox(width: Space.sm),
                Icon(
                  Ph.caretRight,
                  size: Sizes.iconMd,
                  color: c.inkFaint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a screen has nothing to display.
///
/// Empty is not an error. It says what would appear here and, where the user
/// can do something about it, offers the action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Ph.tray,
                size: Sizes.iconXl,
                color: c.inkFaint,
              ),
              const SizedBox(height: Space.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppType.entityName.copyWith(color: c.ink),
              ),
              const SizedBox(height: Space.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppType.rowSecondary.copyWith(color: c.inkMuted),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Space.xl),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  kind: ButtonKind.secondary,
                  expand: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a read fails. Always offers a way forward rather than a dead
/// end.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Could not load',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Ph.warningCircle,
        title: title,
        body: message,
        actionLabel: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
}

/// Shown when the signed-in role may not see something. It explains the
/// restriction instead of presenting a blank screen.
class AppPermissionState extends StatelessWidget {
  const AppPermissionState({
    super.key,
    required this.message,
    this.onRequestAccess,
  });

  final String message;
  final VoidCallback? onRequestAccess;

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Ph.lock,
        title: 'You do not have access',
        body: message,
        actionLabel: onRequestAccess == null ? null : 'Request access',
        onAction: onRequestAccess,
      );
}

/// Placeholder blocks matching the shape of the content that is loading, so
/// the layout does not jump when data arrives.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = Radii.badgeAll,
  });

  const Skeleton.text({super.key, this.width = 160})
      : height = 14,
        radius = Radii.badgeAll;

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A shimmer that cannot be turned off is a problem for anyone sensitive
    // to motion, so the blocks sit still under reduced motion.
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = context.reduceMotion ? 0.5 : _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(c.hairline, c.raised, t),
            borderRadius: widget.radius,
          ),
        );
      },
    );
  }
}

/// Skeleton in the shape of a list row.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: context.density.rowHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Skeleton(width: 20, height: 20, radius: Radii.pillAll),
            const SizedBox(width: Space.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton.text(width: 96),
                const SizedBox(height: Space.sm),
                Skeleton.text(width: 180 + (context.density.index * 20)),
              ],
            ),
          ],
        ),
      );
}

/// A list of row skeletons, used while a queue or order list loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox.shrink(),
        itemBuilder: (_, _) => const SkeletonRow(),
      );
}

/// The persistent strip shown when the device is offline or the cached data
/// is no longer known to be current.
class ConnectivityStrip extends StatelessWidget {
  const ConnectivityStrip({
    super.key,
    required this.offline,
    this.queuedCount = 0,
    this.staleSince,
    this.onView,
  });

  final bool offline;
  final int queuedCount;

  /// When set, data is readable but out of date.
  final Duration? staleSince;

  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    if (!offline && staleSince == null) return const SizedBox.shrink();
    final c = context.colors;

    final message = offline
        ? queuedCount == 0
            ? 'Offline. Showing the last data received.'
            : 'Offline. $queuedCount change${queuedCount == 1 ? '' : 's'} '
                'waiting to send.'
        : 'Last updated ${_ago(staleSince!)} ago.';

    return Semantics(
      liveRegion: true,
      child: Container(
        height: Sizes.offlineStrip,
        color: offline ? c.ink : c.onHoldFill.withValues(alpha: 0.16),
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Row(
          children: [
            Icon(
              offline
                  ? Ph.cloudSlash
                  : Ph.clockCounterClockwise,
              size: Sizes.iconSm,
              color: offline ? c.onInk : c.onHoldText,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                message,
                style: AppType.helper.copyWith(
                  color: offline ? c.onInk : c.onHoldText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onView != null)
              Semantics(
                button: true,
                child: InkWell(
                  onTap: onView,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    child: Text(
                      offline && queuedCount > 0 ? 'View' : 'Refresh',
                      style: AppType.helper.copyWith(
                        color: offline ? c.accentText : c.onHoldText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'moments';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} hr';
    return '${d.inDays} days';
  }
}

/// Confirmation of an action, with an undo where the action is reversible.
void showAppToast(
  BuildContext context, {
  required String message,
  String? undoLabel,
  VoidCallback? onUndo,
  BannerTone tone = BannerTone.positive,
}) {
  final c = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            tone == BannerTone.critical
                ? PhFill.warning
                : PhFill.checkCircle,
            size: Sizes.iconMd,
            color: tone == BannerTone.critical ? c.error : c.secondary,
          ),
          const SizedBox(width: Space.md),
          Expanded(child: Text(message)),
        ],
      ),
      duration: const Duration(seconds: 4),
      action: (undoLabel != null && onUndo != null)
          ? SnackBarAction(label: undoLabel, onPressed: onUndo)
          : null,
    ),
  );
}

/// A blocker shown at the top of a detail screen. It repeats the rule's own
/// sentence, so the explanation the user reads here is the same one they see
/// beneath the disabled control.
class BlockerBanner extends StatelessWidget {
  const BlockerBanner({
    super.key,
    required this.reason,
    this.title = 'Blocked',
    this.onTap,
  });

  final String title;
  final String reason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppBanner(
        tone: BannerTone.critical,
        icon: PhFill.lock,
        title: title,
        detail: reason,
        onTap: onTap,
      );
}

/// Maps a status family onto a banner tone, so alerts and statuses agree.
BannerTone toneForFamily(StatusFamily family) => switch (family) {
      StatusFamily.failed => BannerTone.critical,
      StatusFamily.onHold => BannerTone.warning,
      StatusFamily.completed => BannerTone.positive,
      _ => BannerTone.info,
    };

/// Convenience for showing a status family inline with its wording.
class InlineStatus extends StatelessWidget {
  const InlineStatus({
    super.key,
    required this.family,
    required this.label,
  });

  final StatusFamily family;
  final String label;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(family: family, label: label);
}
