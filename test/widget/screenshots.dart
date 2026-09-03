import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:led_ops/domain/models/models.dart';
import 'package:led_ops/domain/stage_schema.dart';
import 'package:led_ops/features/orders/jobsheet_screen.dart';
import 'package:led_ops/features/orders/order_detail_screen.dart';
import 'package:led_ops/features/orders/orders_screen.dart';
import 'package:led_ops/features/orders/timeline_screen.dart';
import 'package:led_ops/features/pipeline/pipeline_screen.dart';
import 'package:led_ops/features/stages/quality_screen.dart';
import 'package:led_ops/features/stages/stage_execution_screen.dart';
import 'package:led_ops/features/today/today_screen.dart';
import 'package:led_ops/main.dart';
import 'package:led_ops/state/app_state.dart';

/// Renders the key screens to PNGs so the design can be looked at rather than
/// only asserted on.
///
/// Deliberately not named `*_test.dart`, so it stays out of the default run:
/// these images change whenever the design does, and comparing them across
/// machines compares font rasterisers as much as layout. Regenerate with:
///
///   flutter test test/widget/screenshots.dart --update-goldens
void main() {
  setUpAll(() async {
    // Golden output is meaningless without the real fonts.
    for (final entry in <String, List<String>>{
      'Inter': [
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Medium.ttf',
        'assets/fonts/Inter-SemiBold.ttf',
        'assets/fonts/Inter-Bold.ttf',
      ],
      'Phosphor': ['assets/fonts/Phosphor.ttf'],
      'PhosphorFill': ['assets/fonts/Phosphor-Fill.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(
          File(path).readAsBytes().then((b) => ByteData.view(b.buffer)),
        );
      }
      await loader.load();
    }
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Role? role,
    Brightness brightness = Brightness.light,
    double height = 844,
  }) async {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.devicePixelRatio = 2.0;
    view.physicalSize = Size(390 * 2, height * 2);
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      child: AppChrome(
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return screen;
        }),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    if (role != null) {
      captured.read(sessionProvider.notifier).switchRole(role);
    }
    if (brightness == Brightness.dark) {
      captured.read(themeModeProvider.notifier).set(Brightness.dark);
    }
    if (role != null || brightness == Brightness.dark) {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await expectLater(
      find.byType(AppChrome),
      matchesGoldenFile('../../screenshots/$name.png'),
    );
  }

  const blocked = 'order-ORD-0138';

  testWidgets('today operator', (t) =>
      shoot(t, '01-today-operator', const TodayScreen()));

  testWidgets('today manager', (t) => shoot(
        t,
        '02-today-manager',
        const TodayScreen(),
        role: Role.manager,
        height: 1000,
      ));

  testWidgets('orders', (t) => shoot(t, '03-orders', const OrdersScreen()));

  testWidgets('order detail', (t) => shoot(
        t,
        '04-order-detail',
        const OrderDetailScreen(orderId: blocked),
        height: 1000,
      ));

  testWidgets('quality gate', (t) => shoot(
        t,
        '05-quality-gate',
        const QualityScreen(orderId: blocked),
        role: Role.qualityInspector,
        height: 950,
      ));

  testWidgets('stage execution', (t) => shoot(
        t,
        '06-stage-execution',
        const StageExecutionScreen(
          orderId: 'order-ORD-0142',
          stage: StageKey.painting,
        ),
        role: Role.manager,
        height: 1100,
      ));

  testWidgets('pipeline board', (t) =>
      shoot(t, '07-pipeline-board', const PipelineScreen(), height: 1000));

  testWidgets('timeline', (t) => shoot(
        t,
        '08-timeline',
        const TimelineScreen(orderId: blocked),
        height: 1000,
      ));

  testWidgets('new jobsheet', (t) => shoot(
        t,
        '10-new-jobsheet',
        const JobsheetScreen(),
        role: Role.manager,
        height: 1000,
      ));

  testWidgets('orders dark', (t) => shoot(
        t,
        '09-orders-dark',
        const OrdersScreen(),
        brightness: Brightness.dark,
      ));
}
