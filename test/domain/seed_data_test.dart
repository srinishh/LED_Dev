import 'package:flutter_test/flutter_test.dart';
import 'package:led_ops/data/seed_data.dart';
import 'package:led_ops/domain/models/models.dart';
import 'package:led_ops/domain/rules.dart';
import 'package:led_ops/domain/stage_schema.dart';

void main() {
  final seed = buildSeed();
  final orders = seed.orders;

  group('the seed is a usable order book', () {
    test('it holds enough orders to exercise the screens', () {
      expect(orders.length, greaterThanOrEqualTo(24));
    });

    test('order numbers are unique', () {
      final numbers = [for (final o in orders) o.orderNo];
      expect(numbers.toSet().length, numbers.length);
    });

    test('every order carries all ten stage records', () {
      for (final order in orders) {
        expect(order.stages.length, 10, reason: order.orderNo);
        for (final key in StageKey.ordered) {
          final record = order.stage(key);
          expect(
            schemaFor(key).statusValues,
            contains(record.status),
            reason: '${order.orderNo} / ${schemaFor(key).name}',
          );
        }
      }
    });

    test('every order carries the five mandatory quality checks', () {
      for (final order in orders) {
        expect(order.qualityTests.length, 5, reason: order.orderNo);
      }
    });

    test('the data obeys its own rules', () {
      expect(seedRespectsRules(orders), isTrue);
    });

    test('orders are spread across the whole pipeline', () {
      final occupied = {for (final o in orders) o.currentStageKey};
      expect(occupied.length, greaterThanOrEqualTo(7),
          reason: 'the pipeline board would look empty otherwise');
    });
  });

  group('every designed exception is present in the data', () {
    final coverage = seedCoverage(orders, kSeedNow);

    test('a quality failure holds an order at the gate', () {
      expect(coverage.qualityFailures, greaterThanOrEqualTo(1));

      final blocked =
          orders.firstWhere((o) => o.hasQualityFailure);
      expect(Rules.qualityGate(blocked).blocked, isTrue);
      expect(blocked.orderNo, 'ORD-0138');
      expect(blocked.failedTests.single.name, 'Load Test');
    });

    test('orders are on hold and in rework', () {
      expect(coverage.onHold, greaterThanOrEqualTo(1));
      expect(coverage.rework, greaterThanOrEqualTo(1));
    });

    test('an order is held back from dispatch with a listed reason', () {
      expect(coverage.notDispatched, greaterThanOrEqualTo(1));
      final held = orders
          .firstWhere((o) => o.dispatch.notDispatchedReason != null);
      expect(held.dispatch.reasonLabel, 'Vehicle Not Available');
    });

    test('orders are overdue', () {
      expect(coverage.overdue, greaterThanOrEqualTo(1));
    });

    test('an order is short on material', () {
      expect(coverage.materialShort, greaterThanOrEqualTo(1));

      final short =
          orders.firstWhere((o) => o.stage(StageKey.rawMaterial).status ==
              'Partially Received');
      final values = short.stage(StageKey.rawMaterial).values;
      expect(values['availableQuantity'] as int,
          lessThan(values['requiredQuantity'] as int));
      expect(
        Rules.canCompleteStage(short, StageKey.rawMaterial,
            values: values, now: kSeedNow).blocked,
        isTrue,
      );
    });

    test('an order is delivered and closed', () {
      expect(coverage.delivered, greaterThanOrEqualTo(1));
      final done = orders.firstWhere((o) => o.isFinished);
      expect(done.progress, 1.0);
      expect(done.stage(StageKey.delivery).values['receivedBy'], isNotNull);
      expect(done.stage(StageKey.delivery).values['proofOfDelivery'],
          isNotNull);
    });
  });

  group('the timeline answers the questions the blueprint asks', () {
    test('a finished order records every stage from material to delivery', () {
      final done = orders.firstWhere((o) => o.isFinished);
      final events = seed.timelines[done.id]!;

      // Material arrival, cutting start, who welded, painting completion,
      // quality results, assembly, packing, invoice, dispatch, delivery.
      for (final key in StageKey.ordered) {
        expect(
          events.any((e) => e.stageKey == key),
          isTrue,
          reason: 'no event for ${schemaFor(key).name} on ${done.orderNo}',
        );
      }

      final welding = events.firstWhere(
        (e) => e.stageKey == StageKey.weldingGrinding,
      );
      expect(welding.actor, isNotEmpty,
          reason: 'the blueprint asks who completed welding');

      expect(
        events.any((e) => e.type == TimelineEventType.qualityRecorded),
        isTrue,
      );
      expect(
        events.any((e) => e.detail?.contains('INV-') ?? false),
        isTrue,
        reason: 'the blueprint asks when the invoice was generated',
      );
      expect(
        events.any((e) => e.type == TimelineEventType.delivered),
        isTrue,
      );
    });

    test('events are in chronological order', () {
      for (final events in seed.timelines.values) {
        for (var i = 1; i < events.length; i++) {
          expect(
            events[i].at.isBefore(events[i - 1].at),
            isFalse,
            reason: 'timeline is out of order',
          );
        }
      }
    });

    test('a blocked order records why it is blocked', () {
      final blocked = orders.firstWhere((o) => o.hasQualityFailure);
      final events = seed.timelines[blocked.id]!;
      final block =
          events.where((e) => e.type == TimelineEventType.blocked).toList();
      expect(block, isNotEmpty);
      expect(block.single.severity, EventSeverity.critical);
    });
  });

  group('alerts derive from order state', () {
    final alerts = deriveAlerts(orders, kSeedNow);

    test('a failed check raises a critical alert', () {
      final critical =
          alerts.where((a) => a.severity == EventSeverity.critical);
      expect(critical, isNotEmpty);
      expect(
        critical.any((a) => a.title == 'Load Test failed'),
        isTrue,
      );
    });

    test('an undispatched order raises an alert carrying its reason', () {
      final dispatch =
          alerts.firstWhere((a) => a.title == 'Not dispatched');
      expect(dispatch.detail, 'Vehicle Not Available');
    });

    test('critical alerts sort above warnings', () {
      for (var i = 1; i < alerts.length; i++) {
        expect(
          alerts[i].severity.index > alerts[i - 1].severity.index,
          isFalse,
        );
      }
    });
  });

  group('copy quality', () {
    // The em-dash is the clearest signature of machine-written text, and it
    // has no place in an operational interface. Hyphens only.
    test('no seeded string contains an em-dash or en-dash', () {
      final offenders = <String>[];

      void check(String? value, String where) {
        if (value == null) return;
        if (value.contains('—') || value.contains('–')) {
          offenders.add('$where: $value');
        }
      }

      for (final order in orders) {
        check(order.customer, order.orderNo);
        check(order.product, order.orderNo);
        check(order.notes, order.orderNo);
        for (final stage in order.stages.values) {
          for (final entry in stage.values.entries) {
            if (entry.value is String) {
              check(entry.value as String, '${order.orderNo}/${entry.key}');
            }
          }
        }
      }
      for (final events in seed.timelines.values) {
        for (final e in events) {
          check(e.summary, 'timeline');
          check(e.detail, 'timeline');
        }
      }
      for (final a in deriveAlerts(orders, kSeedNow)) {
        check(a.title, 'alert');
        check(a.detail, 'alert');
      }

      expect(offenders, isEmpty);
    });

    test('customers and operators are specific, not placeholders', () {
      const placeholders = [
        'acme',
        'john doe',
        'jane doe',
        'lorem',
        'test customer',
        'example',
        'nexus',
        'foo',
      ];
      for (final order in orders) {
        final name = order.customer.toLowerCase();
        for (final p in placeholders) {
          expect(name.contains(p), isFalse, reason: order.customer);
        }
      }
      for (final op in kMasterData.operators) {
        expect(op.split(' ').length, greaterThanOrEqualTo(2),
            reason: '$op should read as a real person');
      }
    });

    test('quantities are organic rather than round demo numbers', () {
      final roundCount =
          orders.where((o) => o.quantity % 50 == 0).length;
      expect(roundCount / orders.length, lessThan(0.2),
          reason: 'too many quantities look invented');
    });
  });
}
