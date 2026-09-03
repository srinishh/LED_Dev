import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/icons.dart';

import 'design/components/feedback.dart';
import 'design/components/shell.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/more/more_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/pipeline/pipeline_screen.dart';
import 'features/today/today_screen.dart';
import 'state/app_state.dart';

void main() {
  runApp(const ProviderScope(child: LedOpsApp()));
}

class LedOpsApp extends StatelessWidget {
  const LedOpsApp({super.key});

  @override
  Widget build(BuildContext context) => const AppChrome(home: RootShell());
}

/// Theme, tokens and text-scale clamping, wrapped around whatever screen is
/// being shown. The app and the tests both mount this, so a test never
/// exercises a theme the product does not ship.
class AppChrome extends ConsumerWidget {
  const AppChrome({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(themeModeProvider);
    final density = ref.watch(densityProvider);
    final colors =
        brightness == Brightness.dark ? AppColors.dark : AppColors.light;

    return MaterialApp(
      title: 'LED Operations',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(colors, brightness),
      builder: (context, child) => AppTheme(
        colors: colors,
        density: density,
        brightness: brightness,
        // Scaling is honoured up to the range the layouts are verified
        // against, rather than allowed to break them.
        child: withClampedTextScale(context, child ?? const SizedBox.shrink()),
      ),
      home: home,
    );
  }
}

/// The four top-level destinations.
///
/// An IndexedStack keeps each tab's scroll position and filter state alive, so
/// moving between them and back does not lose the user's place.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  var _index = 0;

  static const _destinations = [
    NavDestination(
      icon: Ph.squaresFour,
      activeIcon: PhFill.squaresFour,
      label: 'Today',
    ),
    NavDestination(
      icon: Ph.package,
      activeIcon: PhFill.package,
      label: 'Orders',
    ),
    NavDestination(
      icon: Ph.flowArrow,
      activeIcon: PhFill.flowArrow,
      label: 'Pipeline',
    ),
    NavDestination(
      icon: Ph.dotsThreeCircle,
      activeIcon: PhFill.dotsThreeCircle,
      label: 'More',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityProvider);

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: Column(
        children: [
          // Connectivity sits above every screen, because acting on stale
          // data is worse than waiting for fresh data.
          if (connectivity.isDegraded)
            SafeArea(
              bottom: false,
              child: ConnectivityStrip(
                offline: connectivity.offline,
                queuedCount: connectivity.queued,
                staleSince: connectivity.stale,
                onView: () => setState(() => _index = 3),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                TodayScreen(),
                OrdersScreen(),
                PipelineScreen(),
                MoreScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        destinations: _destinations,
        currentIndex: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Opens the alerts screen. Alerts are reachable from every top-level screen
/// through the app bar, so they never need a tab of their own.
void openAlerts(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
  );
}
