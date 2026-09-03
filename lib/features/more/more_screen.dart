import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/icons.dart';

import '../../data/order_repository.dart';
import '../../design/components/buttons.dart';
import '../../design/components/feedback.dart';
import '../../design/components/rows.dart';
import '../../design/components/shell.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../domain/models/models.dart';
import '../../domain/stage_schema.dart';
import '../../state/app_state.dart';

/// Everything infrequent: who you are, how the app looks, what is waiting to
/// send, and the controls used to review each screen state.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final pending = ref.watch(pendingWritesProvider);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: const RootAppBar(title: 'More'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          _Profile(session: session),
          const SizedBox(height: Space.section),

          const SectionHeader(title: 'Working as'),
          AppListRow(
            primary: session.user.role.label,
            secondary: 'Changes what Today shows and which actions you have.',
            leading: Icon(
              Ph.identificationBadge,
              size: Sizes.iconMd,
              color: context.colors.inkMuted,
            ),
            onTap: () => _pickRole(context, ref, session.user.role),
          ),
          const RowSeparator(),
          if (session.user.role == Role.operator) ...[
            AppListRow(
              primary: session.user.station == null
                  ? 'No station selected'
                  : schemaFor(session.user.station!).name,
              secondary: 'The station whose queue you see.',
              leading: Icon(
                Ph.mapPin,
                size: Sizes.iconMd,
                color: context.colors.inkMuted,
              ),
              onTap: () => _pickStation(context, ref, session.user.station),
            ),
            const RowSeparator(),
          ],

          const SizedBox(height: Space.section),
          const SectionHeader(title: 'Waiting to send'),
          _PendingQueue(writes: pending),

          const SizedBox(height: Space.section),
          const SectionHeader(title: 'Display'),
          _DisplaySettings(),

          const SizedBox(height: Space.section),
          const SectionHeader(title: 'Review controls'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.md,
            ),
            child: Text(
              'These switch the app into each of the states it is designed '
              'for, so every one can be seen rather than described.',
              style: AppType.rowSecondary
                  .copyWith(color: context.colors.inkMuted),
            ),
          ),
          const _DevPanel(),
        ],
      ),
    );
  }

  Future<void> _pickRole(
    BuildContext context,
    WidgetRef ref,
    Role current,
  ) async {
    final picked = await showOptionPicker(
      context,
      title: 'Working as',
      options: [for (final r in Role.values) r.label],
      selected: current.label,
    );
    if (picked == null) return;
    final role = Role.values.firstWhere((r) => r.label == picked);
    ref.read(sessionProvider.notifier).switchRole(role);
  }

  Future<void> _pickStation(
    BuildContext context,
    WidgetRef ref,
    StageKey? current,
  ) async {
    final picked = await showOptionPicker(
      context,
      title: 'Your station',
      options: [for (final k in StageKey.ordered) schemaFor(k).name],
      selected: current == null ? null : schemaFor(current).name,
    );
    if (picked == null) return;
    final stage =
        StageKey.ordered.firstWhere((k) => schemaFor(k).name == picked);
    ref.read(sessionProvider.notifier).switchStation(stage);
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initials = session.user.name
        .split(' ')
        .take(2)
        .map((p) => p.isEmpty ? '' : p[0])
        .join();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.raised,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: AppType.entityName.copyWith(color: c.inkSecondary),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.user.name,
                  style: AppType.entityName.copyWith(color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.plant}. ${session.shift}',
                  style: AppType.rowSecondary.copyWith(color: c.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Changes made offline, and what can be done about them.
class _PendingQueue extends ConsumerWidget {
  const _PendingQueue({required this.writes});

  final List<PendingWrite> writes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (writes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Text(
          'Everything you have entered has been sent.',
          style: AppType.rowSecondary
              .copyWith(color: context.colors.inkMuted),
        ),
      );
    }

    return Column(
      children: [
        for (final write in writes) ...[
          AppListRow(
            primary: write.description,
            secondary: '${write.orderNo}. Queued ${_ago(write.queuedAt)} ago.',
            leading: Icon(
              Ph.cloudSlash,
              size: Sizes.iconMd,
              color: context.colors.inkMuted,
            ),
            showChevron: false,
            trailingTop: TextButton(
              onPressed: () =>
                  ref.read(orderActionsProvider).discardQueuedWrite(write.id),
              child: Text(
                'Discard',
                style: AppType.status
                    .copyWith(color: context.colors.failedText),
              ),
            ),
          ),
          const RowSeparator(),
        ],
        Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: AppButton(
            label: 'Send now',
            kind: ButtonKind.secondary,
            onPressed: () async {
              final sent =
                  await ref.read(orderActionsProvider).retryQueuedWrites();
              if (!context.mounted) return;
              showAppToast(
                context,
                message: sent == 0
                    ? 'Still offline. Changes are kept until a connection '
                        'returns.'
                    : '$sent change${sent == 1 ? '' : 's'} sent.',
                tone: sent == 0 ? BannerTone.warning : BannerTone.positive,
              );
            },
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'moments';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    return '${d.inHours} hr';
  }
}

class _DisplaySettings extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(densityProvider);
    final brightness = ref.watch(themeModeProvider);

    return Column(
      children: [
        AppListRow(
          primary: 'Row height',
          secondary: density == Density.operational
              ? 'Taller rows, easier with gloves.'
              : 'Standard rows.',
          leading: Icon(
            Ph.rows,
            size: Sizes.iconMd,
            color: context.colors.inkMuted,
          ),
          trailingTop: Text(
            density == Density.operational ? 'Operational' : 'Standard',
            style: AppType.status
                .copyWith(color: context.colors.accentText),
          ),
          showChevron: false,
          onTap: () => ref.read(densityProvider.notifier).set(
                density == Density.operational
                    ? Density.comfortable
                    : Density.operational,
              ),
        ),
        const RowSeparator(),
        AppListRow(
          primary: 'Appearance',
          secondary: brightness == Brightness.dark
              ? 'Dark, for night shift.'
              : 'Light.',
          leading: Icon(
            brightness == Brightness.dark
                ? Ph.moon
                : Ph.sun,
            size: Sizes.iconMd,
            color: context.colors.inkMuted,
          ),
          trailingTop: Text(
            brightness == Brightness.dark ? 'Dark' : 'Light',
            style: AppType.status
                .copyWith(color: context.colors.accentText),
          ),
          showChevron: false,
          onTap: () => ref.read(themeModeProvider.notifier).set(
                brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
        ),
        const RowSeparator(),
      ],
    );
  }
}

/// Switches the repository between the conditions each screen is designed
/// for, so the loading, empty, offline, error and permission states can be
/// walked through rather than taken on trust.
class _DevPanel extends ConsumerWidget {
  const _DevPanel();

  static const _modes = <(RepositoryMode, String, String)>[
    (RepositoryMode.normal, 'Normal', 'Live data, everything working.'),
    (RepositoryMode.loading, 'Loading', 'Screens hold their skeletons.'),
    (RepositoryMode.empty, 'Empty', 'No orders in the system.'),
    (RepositoryMode.error, 'Error', 'Reads and writes fail.'),
    (
      RepositoryMode.offline,
      'Offline',
      'Reads from cache, writes queue up.',
    ),
    (
      RepositoryMode.partialSync,
      'Stale data',
      'Readable but out of date.',
    ),
    (
      RepositoryMode.permissionDenied,
      'No access',
      'The role cannot see this data.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(repositoryRevisionProvider);
    final current = ref.read(repositoryProvider).mode;

    return Column(
      children: [
        for (final (mode, label, detail) in _modes) ...[
          AppListRow(
            primary: label,
            secondary: detail,
            leading: Icon(
              mode == current
                  ? PhFill.checkCircle
                  : Ph.circle,
              size: Sizes.iconMd,
              color: mode == current
                  ? context.colors.accentText
                  : context.colors.inkFaint,
            ),
            showChevron: false,
            onTap: () {
              ref.read(orderActionsProvider).setMode(mode);
              showAppToast(
                context,
                message: 'Showing the $label state.',
                tone: BannerTone.info,
              );
            },
          ),
          const RowSeparator(),
        ],
        Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            children: [
              AppButton(
                label: 'Slow the connection',
                kind: ButtonKind.secondary,
                onPressed: () {
                  ref
                      .read(orderActionsProvider)
                      .setLatency(const Duration(milliseconds: 1200));
                  showAppToast(
                    context,
                    message: 'Reads now take a moment, so skeletons are '
                        'visible.',
                    tone: BannerTone.info,
                  );
                },
              ),
              const SizedBox(height: Space.sm),
              AppButton(
                label: 'Reset the data',
                kind: ButtonKind.destructive,
                onPressed: () async {
                  final confirmed = await confirmDestructive(
                    context,
                    title: 'Reset the data',
                    message: 'Every change made in this session will be '
                        'discarded and the sample orders restored.',
                    confirmLabel: 'Reset',
                  );
                  if (!confirmed || !context.mounted) return;
                  ref.read(orderActionsProvider).resetData();
                  showAppToast(context, message: 'Sample data restored.');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
