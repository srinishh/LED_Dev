import 'package:flutter_test/flutter_test.dart';
import 'package:led_ops/domain/stage_schema.dart';
import 'package:led_ops/domain/status_projection.dart';

void main() {
  group('StatusProjection covers the full cross-product', () {
    test('every declared status of every stage maps to a legend family', () {
      final unmapped = <String>[];
      var pairs = 0;

      for (final stage in StageKey.ordered) {
        for (final status in schemaFor(stage).statusValues) {
          pairs++;
          try {
            StatusProjection.of(stage, status);
          } catch (e) {
            unmapped.add('${schemaFor(stage).name} / $status  ->  $e');
          }
        }
      }

      expect(
        unmapped,
        isEmpty,
        reason: 'These stage/status pairs have no legend family:\n'
            '${unmapped.join('\n')}',
      );
      // Guards against a status being silently deleted from the schema.
      expect(pairs, greaterThanOrEqualTo(47));
    });

    test('a status not belonging to the stage is rejected', () {
      expect(
        () => StatusProjection.of(StageKey.laserCutting, 'Delivered'),
        throwsArgumentError,
      );
    });

    test('tryOf returns null rather than throwing', () {
      expect(StatusProjection.tryOf(StageKey.laserCutting, 'Delivered'),
          isNull);
      expect(StatusProjection.tryOf(StageKey.laserCutting, 'Completed'),
          StatusFamily.completed);
    });
  });

  group('stage-dependent meanings are preserved', () {
    test('Dispatched is progress at delivery but completion at dispatch', () {
      expect(StatusProjection.of(StageKey.delivery, 'Dispatched'),
          StatusFamily.inProcess);
      expect(StatusProjection.of(StageKey.dispatch, 'Dispatched'),
          StatusFamily.completed);
    });

    test('wiring finished alone does not complete the assembly stage', () {
      expect(StatusProjection.of(StageKey.wiringAssembly, 'Wiring Completed'),
          StatusFamily.inProcess);
      expect(StatusProjection.of(StageKey.wiringAssembly, 'Assembly Completed'),
          StatusFamily.completed);
    });

    test('received material is still in process until approved', () {
      expect(StatusProjection.of(StageKey.rawMaterial, 'Received'),
          StatusFamily.inProcess);
      expect(StatusProjection.of(StageKey.rawMaterial, 'Approved'),
          StatusFamily.completed);
      expect(StatusProjection.of(StageKey.rawMaterial, 'Rejected'),
          StatusFamily.failed);
    });

    test('rework and re-test read as failures that need attention', () {
      expect(StatusProjection.of(StageKey.weldingGrinding, 'Rework'),
          StatusFamily.failed);
      expect(StatusProjection.of(StageKey.qualityTesting, 'Re-Test Required'),
          StatusFamily.failed);
      expect(StatusProjection.needsAttention(StatusFamily.failed), isTrue);
      expect(StatusProjection.needsAttention(StatusFamily.onHold), isTrue);
      expect(StatusProjection.needsAttention(StatusFamily.inProcess), isFalse);
    });

    test('an undispatched order reads as needing attention', () {
      expect(StatusProjection.of(StageKey.dispatch, 'Not Dispatched'),
          StatusFamily.failed);
    });
  });

  group('schema integrity', () {
    test('all ten stages are defined and ordered', () {
      expect(StageKey.ordered.length, 10);
      expect(kStageSchemas.length, 10);
      expect(schemaFor(StageKey.rawMaterial).name, 'Raw Material');
      expect(schemaFor(StageKey.delivery).name, 'Delivery');
      expect(StageKey.rawMaterial.next, StageKey.laserCutting);
      expect(StageKey.delivery.next, isNull);
      expect(StageKey.rawMaterial.previous, isNull);
    });

    test('every stage has exactly one terminal status', () {
      for (final stage in StageKey.ordered) {
        final schema = schemaFor(stage);
        final terminals = schema.statuses.where((s) => s.terminal).toList();
        expect(terminals.length, 1,
            reason: '${schema.name} must have one terminal status');
      }
    });

    test('field keys are unique within a stage', () {
      for (final stage in StageKey.ordered) {
        final schema = schemaFor(stage);
        final keys = [for (final f in schema.fields) f.key];
        expect(keys.toSet().length, keys.length,
            reason: '${schema.name} has a duplicate field key');
      }
    });

    test('the five mandatory quality checks are defined', () {
      expect(kQualityTests.length, 5);
      expect(kQualityTests.every((t) => t.required), isTrue);
      expect(
        [for (final t in kQualityTests) t.name],
        [
          'Visual Inspection',
          'Dimension Test',
          'Electrical Test',
          'Load Test',
          'Insulation Test',
        ],
      );
    });

    test('the nine not-dispatched reasons are defined, Other needs detail',
        () {
      expect(NotDispatchedReason.values.length, 9);
      expect(NotDispatchedReason.other.requiresDetail, isTrue);
      expect(NotDispatchedReason.paymentPending.requiresDetail, isFalse);
    });
  });

  group('field counts match the source blueprint', () {
    // Each stage captures the fields named in the blueprint. These counts are
    // a tripwire: changing a stage's field set must be a deliberate edit here
    // as well as in the schema.
    const expected = <StageKey, int>{
      StageKey.rawMaterial: 8,
      StageKey.laserCutting: 10,
      StageKey.weldingGrinding: 0, // captured in sub-records
      StageKey.painting: 10,
      StageKey.qualityTesting: 0, // captured as a checklist
      StageKey.wiringAssembly: 10,
      StageKey.packingLabelling: 11,
      StageKey.readyForDispatch: 6,
      StageKey.dispatch: 12,
      StageKey.delivery: 9,
    };

    for (final entry in expected.entries) {
      test('${schemaFor(entry.key).name} captures ${entry.value} fields', () {
        expect(schemaFor(entry.key).fields.length, entry.value);
      });
    }

    test('welding and grinding are captured as two sub-records', () {
      // Field counts exclude each sub-record's own status, which the
      // blueprint lists alongside the fields but which is modelled as the
      // sub-record's status vocabulary rather than as a captured value.
      final schema = schemaFor(StageKey.weldingGrinding);
      expect(schema.subRecords.length, 2);
      expect(schema.subRecords[0].name, 'Welding');
      expect(schema.subRecords[0].fields.length, 8);
      expect(schema.subRecords[0].statusValues.length, 5);
      expect(schema.subRecords[1].name, 'Grinding');
      expect(schema.subRecords[1].fields.length, 6);
      expect(schema.subRecords[1].statusValues.length, 5);
    });
  });
}
