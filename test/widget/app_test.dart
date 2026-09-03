import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:led_ops/data/order_repository.dart';
import 'package:led_ops/design/tokens.dart';
import 'package:led_ops/domain/models/models.dart';
import 'package:led_ops/domain/stage_schema.dart';
import 'package:led_ops/features/alerts/alerts_screen.dart';
import 'package:led_ops/features/orders/order_detail_screen.dart';
import 'package:led_ops/features/orders/jobsheet_screen.dart';
import 'package:led_ops/features/orders/orders_screen.dart';
import 'package:led_ops/features/pipeline/pipeline_screen.dart';
import 'package:led_ops/features/stages/dispatch_screen.dart';
import 'package:led_ops/features/stages/quality_screen.dart';
import 'package:led_ops/features/stages/stage_execution_screen.dart';
import 'package:led_ops/design/components/inputs.dart';
import 'package:led_ops/features/today/today_screen.dart';
import 'package:led_ops/main.dart';
import 'package:led_ops/state/app_state.dart';

/// Mounts a screen inside the real providers and the real theme, so a test
/// never passes against chrome the product does not ship.
Widget host(Widget child) => ProviderScope(child: AppChrome(home: child));

void main() {
  // The seeded order held at the quality gate, used across several tests.
  const blockedOrderId = 'order-ORD-0138';

  // Every screen is designed for a phone, so the tests run at one. The
  // default test surface is a small desktop window and would push content
  // out of view.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.devicePixelRatio = 3.0;
    // Phone width, because that is what overflow depends on, but a tall
    // surface so lazily-built list content is actually laid out and can be
    // asserted on without scripting a scroll in every test.
    view.physicalSize = const Size(390 * 3, 2400 * 3);
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Skeleton shimmers loop forever by design, so pumpAndSettle would never
  /// return. A bounded run of frames is enough for data to arrive and for
  /// every transition in the app to finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('the app boots', () {
    testWidgets('the shell shows four destinations and opens on Today',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: LedOpsApp()));
      await settle(tester);

      for (final label in ['Today', 'Orders', 'Pipeline', 'More']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });
  });

  group('Today', () {
    testWidgets('an operator sees their station queue', (tester) async {
      await tester.pumpWidget(host(const TodayScreen()));
      await settle(tester);

      // The default session is an operator at laser cutting.
      expect(find.text('Laser Cutting'), findsWidgets);
      expect(find.textContaining('jobs done this shift'), findsOneWidget);
    });

    testWidgets('a manager sees exceptions before anything else',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const TodayScreen();
        }),
      ));
      await settle(tester);

      captured.read(sessionProvider.notifier).switchRole(Role.manager);
      await settle(tester);

      expect(find.text('NEEDS ATTENTION'), findsOneWidget);
      expect(find.text('Quality failed'), findsOneWidget);
      expect(find.text('WHERE THE WORK IS'), findsOneWidget);
    });
  });

  group('Orders', () {
    testWidgets('the list renders and states how many orders it shows',
        (tester) async {
      await tester.pumpWidget(host(const OrdersScreen()));
      await settle(tester);

      expect(find.textContaining('orders'), findsWidgets);
      expect(find.text('ORD-0138'), findsWidgets);
    });

    testWidgets('an empty result explains itself and offers a way back',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const OrdersScreen();
        }),
      ));
      await settle(tester);

      captured
          .read(orderFilterProvider.notifier)
          .setQuery('nothing will match this');
      await settle(tester);

      expect(find.text('No orders match'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });
  });

  group('Order detail leads with identity, status and the blocker', () {
    testWidgets('a held order shows why it cannot move', (tester) async {
      await tester
          .pumpWidget(host(const OrderDetailScreen(orderId: blockedOrderId)));
      await settle(tester);

      expect(find.text('LED High Bay 150W'), findsWidgets);
      expect(find.textContaining('Northline Infra Projects'), findsWidgets);
      expect(find.text('Blocked'), findsOneWidget);
      expect(
        find.textContaining('Load Test must pass'),
        findsWidgets,
      );
    });
  });

  group('the quality gate', () {
    testWidgets('states the block and disables the advance control',
        (tester) async {
      await tester
          .pumpWidget(host(const QualityScreen(orderId: blockedOrderId)));
      await settle(tester);

      expect(find.text('Held at quality'), findsOneWidget);
      expect(find.textContaining('Load Test must pass'), findsWidgets);
      expect(find.text('Load Test'), findsOneWidget);

      // The reason is printed beneath the control it disabled, not hidden.
      expect(
        find.textContaining('Advance to Wiring and Assembly'),
        findsOneWidget,
      );
    });

    testWidgets('passing the outstanding checks opens the gate',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const QualityScreen(orderId: blockedOrderId);
        }),
      ));
      await settle(tester);

      captured.read(sessionProvider.notifier).switchRole(Role.qualityInspector);
      await settle(tester);

      // Every mandatory check must pass, not only the one that failed: the
      // gate is about the whole checklist.
      final actions = captured.read(orderActionsProvider);
      for (final test in kQualityTests) {
        await actions.recordQualityTest(
          orderId: blockedOrderId,
          testKey: test.key,
          result: TestResult.pass,
          status: TestStatus.passed,
        );
      }
      await settle(tester);

      expect(find.text('All checks passed'), findsOneWidget);
      expect(find.text('Held at quality'), findsNothing);
    });
  });

  group('stage execution', () {
    testWidgets('renders the stage schema and its own status vocabulary',
        (tester) async {
      await tester.pumpWidget(host(
        const StageExecutionScreen(
          orderId: 'order-ORD-0142',
          stage: StageKey.laserCutting,
        ),
      ));
      await settle(tester);

      // Every status the blueprint gives this stage, and no others.
      for (final status in schemaFor(StageKey.laserCutting).statusValues) {
        expect(find.text(status), findsWidgets, reason: status);
      }
      // A representative sample of the captured fields.
      expect(find.text('ACTUAL QUANTITY CUT'), findsOneWidget);
      expect(find.text('MACHINE NUMBER'), findsOneWidget);
      expect(find.text('REQUIRED CUTTING QUANTITY'), findsOneWidget);
    });

    testWidgets('the form is filled from the order once it loads',
        (tester) async {
      // The order is not available on the first frame. A form that seeded
      // itself only in initState would show every field blank, which is how
      // this screen looked before the seeding was moved into build.
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const StageExecutionScreen(
            orderId: 'order-ORD-0142',
            stage: StageKey.painting,
          );
        }),
      ));
      await settle(tester);
      captured.read(sessionProvider.notifier).switchRole(Role.manager);
      await settle(tester);

      // Carried forward, defaulted and auto-filled values are all present.
      expect(find.text('ORD-0142'), findsWidgets);
      expect(find.text('118'), findsOneWidget);
      expect(find.text('Signal grey'), findsOneWidget);
      expect(find.text('RAL 7004'), findsOneWidget,
          reason: 'the paint code follows the chosen colour');

      // The stage's real status is selected, not the schema default.
      final segment = tester.widget<AppSegmentedControl<String>>(
        find.byType(AppSegmentedControl<String>).first,
      );
      expect(segment.selected, 'In Process');
    });

    testWidgets('welding and grinding are two tabs in one stage',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const StageExecutionScreen(
            orderId: 'order-ORD-0142',
            stage: StageKey.weldingGrinding,
          );
        }),
      ));
      await settle(tester);
      // An operator is signed in at one station, so this stage is opened by
      // someone permitted to work on it.
      captured.read(sessionProvider.notifier).switchRole(Role.manager);
      await settle(tester);

      expect(find.text('Welding'), findsWidgets);
      expect(find.text('Grinding'), findsWidgets);
      expect(find.textContaining('Overall stage:'), findsOneWidget);
    });
  });

  group('dispatch', () {
    testWidgets('choosing not dispatched demands a reason before saving',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const DispatchScreen(orderId: 'order-ORD-0119');
        }),
      ));
      await settle(tester);
      captured.read(sessionProvider.notifier).switchRole(Role.dispatchClerk);
      await settle(tester);

      await tester.tap(find.text('Not Dispatched').first);
      await settle(tester);

      expect(find.text('A reason is required'), findsOneWidget);
      expect(
        find.text('Choose why the order was not dispatched.'),
        findsOneWidget,
      );
    });
  });

  group('raising and revising a jobsheet', () {
    testWidgets('a manager can raise one, and it appears in the order book',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const OrdersScreen();
        }),
      ));
      await settle(tester);
      captured.read(sessionProvider.notifier).switchRole(Role.manager);
      await settle(tester);

      final before = captured.read(ordersProvider).value!.length;

      final order = await captured.read(orderActionsProvider).createOrder(
            NewOrderDraft(
              customer: 'Sundaram Metals',
              product: 'LED Panel 600x600',
              quantity: 64,
              priority: Priority.high,
              dueAt: DateTime.now().add(const Duration(days: 21)),
              materialName: 'CRCA sheet 1.2mm',
              materialCode: 'CRCA-12-4X8',
            ),
          );
      await settle(tester);

      expect(captured.read(ordersProvider).value!.length, before + 1);

      // It starts at the beginning of the line with nothing done.
      expect(order.currentStageKey, StageKey.rawMaterial);
      expect(order.completedStageCount, 0);
      expect(order.stages.length, 10);
      expect(order.qualityTests.length, 5);

      // The order number follows the plant's sequence rather than being typed.
      expect(order.orderNo, matches(RegExp(r'^ORD-\d{4}$')));

      // What the planner knew is already on the material stage.
      final material = order.stage(StageKey.rawMaterial).values;
      expect(material['requiredQuantity'], 64);
      expect(material['materialName'], 'CRCA sheet 1.2mm');

      // It joins the order book. Where it appears on screen depends on the
      // sort, so the list itself is what is asserted rather than pixels.
      expect(
        captured.read(filteredOrdersProvider).any((o) => o.id == order.id),
        isTrue,
      );

      // Searching for it finds it.
      captured.read(orderFilterProvider.notifier).setQuery(order.orderNo);
      await settle(tester);
      expect(find.text(order.orderNo), findsWidgets);
    });

    testWidgets('an incomplete jobsheet says what is missing', (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const JobsheetScreen();
        }),
      ));
      await settle(tester);
      captured.read(sessionProvider.notifier).switchRole(Role.manager);
      await settle(tester);

      // The control is disabled and names the first thing outstanding.
      expect(find.text('Raise jobsheet'), findsOneWidget);
      expect(find.text('Choose a customer.'), findsOneWidget);
    });

    testWidgets('only a manager can raise one', (tester) async {
      await tester.pumpWidget(host(const JobsheetScreen()));
      await settle(tester);

      expect(find.text('You do not have access'), findsOneWidget);
      expect(find.textContaining('raised and revised by a manager'),
          findsOneWidget);
    });

    testWidgets('revising a live jobsheet is recorded on the timeline',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const OrdersScreen();
        }),
      ));
      await settle(tester);
      captured.read(sessionProvider.notifier).switchRole(Role.manager);
      await settle(tester);

      final original = captured.read(orderProvider(blockedOrderId))!;
      await captured.read(orderActionsProvider).updateOrderDetails(
            blockedOrderId,
            NewOrderDraft(
              customer: original.customer,
              product: original.product,
              quantity: 120,
              priority: original.priority,
              dueAt: original.dueAt,
              materialName: 'Aluminium sheet 2mm',
            ),
          );
      await settle(tester);

      expect(captured.read(orderProvider(blockedOrderId))!.quantity, 120);

      // The floor may already be working to the old number, so the change is
      // written into the history rather than applied silently.
      final events =
          await captured.read(repositoryProvider).fetchTimeline(blockedOrderId);
      final revision = events.where((e) => e.summary == 'Jobsheet revised');
      expect(revision, isNotEmpty);
      expect(revision.last.detail, contains('quantity 96 to 120'));
    });
  });

  group('pipeline', () {
    testWidgets('the board lists all ten stages', (tester) async {
      await tester.pumpWidget(host(const PipelineScreen()));
      await settle(tester);

      expect(find.text('Board'), findsOneWidget);
      expect(find.text('Matrix'), findsOneWidget);
      for (final key in StageKey.ordered) {
        expect(
          find.text(schemaFor(key).name),
          findsWidgets,
          reason: schemaFor(key).name,
        );
      }
    });

    testWidgets('the matrix carries a legend so the marks can be read',
        (tester) async {
      await tester.pumpWidget(host(const PipelineScreen()));
      await settle(tester);

      await tester.tap(find.text('Matrix'));
      await settle(tester);

      expect(find.text('Order'), findsOneWidget);
      for (final label in [
        'Not started',
        'In process',
        'Completed',
        'Failed',
        'On hold',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });
  });

  group('alerts', () {
    testWidgets('failures are raised and can be filtered', (tester) async {
      await tester.pumpWidget(host(const AlertsScreen()));
      await settle(tester);

      expect(find.text('Load Test failed'), findsWidgets);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Acknowledged'), findsOneWidget);
    });
  });

  group('every screen renders its designed states', () {
    Future<void> withMode(
      WidgetTester tester,
      RepositoryMode mode,
      Widget screen,
    ) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return screen;
        }),
      ));
      await settle(tester);
      captured.read(orderActionsProvider).setMode(mode);
      await settle(tester);
    }

    testWidgets('empty', (tester) async {
      await withMode(tester, RepositoryMode.empty, const OrdersScreen());
      await settle(tester);
      expect(find.text('No orders yet'), findsOneWidget);
    });

    testWidgets('error offers a retry', (tester) async {
      await withMode(tester, RepositoryMode.error, const OrdersScreen());
      await settle(tester);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline is stated rather than treated as a failure',
        (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          final connectivity = ref.watch(connectivityProvider);
          return Scaffold(
            body: Text(
              connectivity.offline ? 'offline' : 'online',
              textDirection: TextDirection.ltr,
            ),
          );
        }),
      ));
      await settle(tester);
      expect(find.text('online'), findsOneWidget);

      captured.read(orderActionsProvider).setMode(RepositoryMode.offline);
      await settle(tester);
      expect(find.text('offline'), findsOneWidget);
    });

    testWidgets('loading holds a skeleton rather than an empty screen',
        (tester) async {
      await withMode(tester, RepositoryMode.loading, const OrdersScreen());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No orders yet'), findsNothing);
      expect(find.text('Could not load'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('layouts survive text scaled to the supported maximum',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      for (final screen in <Widget>[
        const OrdersScreen(),
        const OrderDetailScreen(orderId: blockedOrderId),
        const QualityScreen(orderId: blockedOrderId),
        const PipelineScreen(),
      ]) {
        await tester.pumpWidget(host(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(kMaxTextScale),
            ),
            child: screen,
          ),
        ));
        await settle(tester);
        expect(tester.takeException(), isNull,
            reason: '${screen.runtimeType} overflowed at $kMaxTextScale x');
      }
    });

    testWidgets('the dark theme renders every screen', (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(host(
        Consumer(builder: (context, ref, _) {
          captured = ref;
          return const OrdersScreen();
        }),
      ));
      await settle(tester);

      captured.read(themeModeProvider.notifier).set(Brightness.dark);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
