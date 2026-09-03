import 'package:flutter_test/flutter_test.dart';
import 'package:led_ops/domain/models/models.dart';
import 'package:led_ops/domain/rules.dart';
import 'package:led_ops/domain/stage_schema.dart';

/// Fixed clock so date rules are deterministic.
final _now = DateTime(2026, 8, 30, 14, 0);

StageRecord _record(
  StageKey key, {
  String? status,
  Map<String, Object?> values = const {},
  Map<String, SubRecordState> subRecords = const {},
}) =>
    StageRecord(
      stageKey: key,
      status: status ?? schemaFor(key).initialStatus,
      values: values,
      subRecords: subRecords,
    );

QualityTestRecord _test(
  QualityTestDefinition def, {
  TestStatus status = TestStatus.notTested,
}) =>
    QualityTestRecord(definition: def, status: status);

Order _order({
  Map<StageKey, StageRecord>? stages,
  List<QualityTestRecord>? tests,
  int completedThrough = -1,
  bool cancelled = false,
}) {
  final built = <StageKey, StageRecord>{};
  for (final key in StageKey.ordered) {
    built[key] = key.index <= completedThrough
        ? _record(key, status: schemaFor(key).terminalStatus)
        : _record(key);
  }
  if (stages != null) built.addAll(stages);

  return Order(
    id: 'o1',
    orderNo: 'ORD-0142',
    customer: 'Sundaram Metals',
    product: 'LED High Bay 150W',
    quantity: 118,
    priority: Priority.high,
    receivedAt: DateTime(2026, 8, 12),
    dueAt: DateTime(2026, 9, 2),
    isCancelled: cancelled,
    stages: built,
    qualityTests:
        tests ?? [for (final d in kQualityTests) _test(d)],
  );
}

const _operator = User(
  id: 'u1',
  name: 'Ramanathan Selvaraj',
  role: Role.operator,
  station: StageKey.laserCutting,
);
const _manager = User(id: 'u2', name: 'Devika Ranganathan', role: Role.manager);
const _inspector =
    User(id: 'u3', name: 'Farhan Qureshi', role: Role.qualityInspector);
const _dispatch =
    User(id: 'u4', name: 'Meenakshi Balan', role: Role.dispatchClerk);

void main() {
  group('R-01 stages advance in order', () {
    test('a stage cannot start before its predecessor completes', () {
      final order = _order();
      final result = Rules.canStartStage(order, StageKey.laserCutting);
      expect(result.blocked, isTrue);
      expect(result.reason, 'Raw Material must be completed first.');
    });

    test('the first stage has nothing to wait for', () {
      expect(
        Rules.canStartStage(_order(), StageKey.rawMaterial).allowed,
        isTrue,
      );
    });

    test('a stage starts once its predecessor is complete', () {
      final order = _order(completedThrough: StageKey.rawMaterial.index);
      expect(
        Rules.canStartStage(order, StageKey.laserCutting).allowed,
        isTrue,
      );
    });
  });

  group('R-02 material shortfall', () {
    test('completion is blocked while less than required has arrived', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.rawMaterial,
        now: _now,
        values: {
          'materialName': 'Aluminium sheet 2mm',
          'materialCode': 'AL-2MM-4X8',
          'requiredQuantity': 118,
          'availableQuantity': 90,
          'supplier': 'Kaveri Metals',
          'purchaseOrderNumber': 'PO-2026-0431',
          'materialReceivedDate': DateTime(2026, 8, 20),
        },
      );
      expect(result.blocked, isTrue);
      expect(
        result.reason,
        'Only 90 of 118 received. The stage stays at Partially Received '
        'until the full quantity arrives.',
      );
      expect(result.firstField, 'availableQuantity');
    });

    test('completion is allowed once the full quantity is available', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.rawMaterial,
        now: _now,
        values: {
          'materialName': 'Aluminium sheet 2mm',
          'materialCode': 'AL-2MM-4X8',
          'requiredQuantity': 118,
          'availableQuantity': 118,
          'supplier': 'Kaveri Metals',
          'purchaseOrderNumber': 'PO-2026-0431',
          'materialReceivedDate': DateTime(2026, 8, 20),
        },
      );
      expect(result.allowed, isTrue);
    });
  });

  group('R-03 required fields', () {
    test('a missing required field names itself in the message', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.laserCutting,
        now: _now,
        values: {
          'jobNumber': 'ORD-0142',
          'materialName': 'Aluminium sheet 2mm',
          'materialQuantity': 118,
          'requiredCuttingQuantity': 118,
          // actualQuantityCut deliberately absent
          'machineNumber': 'LC-02',
          'operatorName': 'Ramanathan Selvaraj',
          'startedAt': DateTime(2026, 8, 30, 9),
          'completedAt': DateTime(2026, 8, 30, 12),
        },
      );
      expect(result.blocked, isTrue);
      expect(result.reason, 'Enter actual quantity cut to complete this stage.');
      expect(result.firstField, 'actualQuantityCut');
    });
  });

  group('R-04 quality gate', () {
    List<QualityTestRecord> testsWith(Map<String, TestStatus> overrides) => [
          for (final d in kQualityTests)
            _test(d, status: overrides[d.key] ?? TestStatus.passed),
        ];

    test('a failed mandatory check names itself and the stage it blocks', () {
      final order = _order(
        completedThrough: StageKey.painting.index,
        tests: testsWith({'load': TestStatus.failed}),
      );
      final result = Rules.qualityGate(order);
      expect(result.blocked, isTrue);
      expect(
        result.reason,
        'Load Test must pass before the order can move to '
        'Wiring and Assembly.',
      );
    });

    test('several failures are counted rather than listed', () {
      final order = _order(
        tests: testsWith({
          'load': TestStatus.failed,
          'insulation': TestStatus.reTestRequired,
        }),
      );
      expect(
        Rules.qualityGate(order).reason,
        '2 checks must pass before the order can move to '
        'Wiring and Assembly.',
      );
    });

    test('failures and unrecorded checks are reported together, so the '
        'message agrees with the count on screen', () {
      final order = _order(
        tests: testsWith({
          'load': TestStatus.failed,
          'insulation': TestStatus.notTested,
        }),
      );
      expect(
        Rules.qualityGate(order).reason,
        'Load Test must pass and Insulation Test has not been recorded, '
        'before the order can move to Wiring and Assembly.',
      );
    });

    test('an unrecorded check blocks with a different message', () {
      final order = _order(tests: testsWith({'load': TestStatus.notTested}));
      expect(
        Rules.qualityGate(order).reason,
        'Load Test has not been recorded yet.',
      );
    });

    test('the gate opens once every mandatory check passes', () {
      expect(Rules.qualityGate(_order(tests: testsWith({}))).allowed, isTrue);
    });

    test('advancing out of quality testing is blocked by a failure', () {
      final order = _order(
        completedThrough: StageKey.painting.index,
        tests: testsWith({'load': TestStatus.failed}),
      );
      expect(order.currentStageKey, StageKey.qualityTesting);
      expect(Rules.isBlockedByQuality(order), isTrue);
      final result = Rules.canAdvance(order, _manager, now: _now);
      expect(result.blocked, isTrue);
      expect(
        result.any((v) => v.rule == RuleId.qualityGate),
        isTrue,
      );
    });

    test('a re-test that passes releases the order', () {
      final order = _order(
        completedThrough: StageKey.painting.index,
        tests: testsWith({}),
      );
      expect(Rules.isBlockedByQuality(order), isFalse);
      expect(Rules.qualityGate(order).allowed, isTrue);
    });

    test('only a manager can override the gate', () {
      expect(Rules.canOverrideQualityGate(_manager).allowed, isTrue);
      expect(Rules.canOverrideQualityGate(_inspector).blocked, isTrue);
      expect(
        Rules.canOverrideQualityGate(_operator).reason,
        'Only a manager can release an order past a failed quality check.',
      );
    });
  });

  group('R-05 wiring and assembly both complete', () {
    Map<String, Object?> values({
      required String wiring,
      required String assembly,
    }) =>
        {
          'jobNumber': 'ORD-0142',
          'productName': 'LED High Bay 150W',
          'quantity': 118,
          'wiringStatus': wiring,
          'assemblyStatus': assembly,
          'technicianName': 'Ramanathan Selvaraj',
          'startedAt': DateTime(2026, 8, 29, 8),
          'completedAt': DateTime(2026, 8, 29, 16),
          'componentsUsed': const ['Driver 150W x118'],
        };

    test('wiring alone leaves the stage open and says which half is left', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.wiringAssembly,
        now: _now,
        values: values(wiring: 'Completed', assembly: 'In Process'),
      );
      expect(result.blocked, isTrue);
      expect(result.reason, 'Complete assembly before finishing this stage.');
    });

    test('neither half done names both', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.wiringAssembly,
        now: _now,
        values: values(wiring: 'In Process', assembly: 'Not Started'),
      );
      expect(
        result.reason,
        'Complete wiring and assembly before finishing this stage.',
      );
    });

    test('both halves complete the stage', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.wiringAssembly,
        now: _now,
        values: values(wiring: 'Completed', assembly: 'Completed'),
      );
      expect(result.allowed, isTrue);
    });

    test('the derived status tracks the two halves', () {
      expect(
        Rules.deriveWiringAssemblyStatus(
            values(wiring: 'Completed', assembly: 'Completed')),
        'Assembly Completed',
      );
      expect(
        Rules.deriveWiringAssemblyStatus(
            values(wiring: 'Completed', assembly: 'Not Started')),
        'Wiring Completed',
      );
      expect(
        Rules.deriveWiringAssemblyStatus(
            values(wiring: 'In Process', assembly: 'Not Started')),
        'Wiring In Process',
      );
      expect(
        Rules.deriveWiringAssemblyStatus(
            values(wiring: 'Completed', assembly: 'Rework Required')),
        'Rework Required',
      );
    });
  });

  group('R-06 label verification', () {
    Map<String, Object?> packing({required bool verified}) => {
          'productName': 'LED High Bay 150W',
          'jobNumber': 'ORD-0142',
          'quantity': 118,
          'numberOfBoxes': 12,
          'packingType': 'Carton with foam insert',
          'packedBy': 'Meenakshi Balan',
          'packingDate': DateTime(2026, 8, 29),
          'labelNumber': 'LBL-2026-8841',
          'batchNumber': 'BTH-0926',
          'serialNumber': 'SN-118-0431',
          'labelVerification': verified,
        };

    test('ready for dispatch is blocked until the label is verified', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.packingLabelling,
        now: _now,
        values: packing(verified: false),
      );
      expect(result.blocked, isTrue);
      expect(
        result.reason,
        'Verify the label number before marking the order ready for dispatch.',
      );
    });

    test('verification releases the stage', () {
      expect(
        Rules.canCompleteStage(
          _order(),
          StageKey.packingLabelling,
          now: _now,
          values: packing(verified: true),
        ).allowed,
        isTrue,
      );
    });
  });

  group('R-07 not dispatched needs a reason', () {
    test('dispatched needs no reason', () {
      expect(Rules.canSaveDispatch(status: 'Dispatched').allowed, isTrue);
    });

    test('not dispatched without a reason is refused', () {
      final result = Rules.canSaveDispatch(status: 'Not Dispatched');
      expect(result.blocked, isTrue);
      expect(result.reason, 'Choose why the order was not dispatched.');
    });

    test('a listed reason is enough', () {
      expect(
        Rules.canSaveDispatch(
          status: 'Not Dispatched',
          reason: NotDispatchedReason.vehicleNotAvailable,
        ).allowed,
        isTrue,
      );
    });

    test('Other additionally requires free text', () {
      final blank = Rules.canSaveDispatch(
        status: 'Not Dispatched',
        reason: NotDispatchedReason.other,
      );
      expect(blank.blocked, isTrue);
      expect(blank.reason,
          'Describe the reason the order was not dispatched.');

      expect(
        Rules.canSaveDispatch(
          status: 'Not Dispatched',
          reason: NotDispatchedReason.other,
          detail: 'Consignee godown closed for stocktaking.',
        ).allowed,
        isTrue,
      );
    });

    test('whitespace does not satisfy the detail requirement', () {
      expect(
        Rules.canSaveDispatch(
          status: 'Not Dispatched',
          reason: NotDispatchedReason.other,
          detail: '   ',
        ).blocked,
        isTrue,
      );
    });
  });

  group('R-08 delivery evidence', () {
    test('delivery without proof, date or recipient is refused', () {
      final result = Rules.canMarkDelivered(const {});
      expect(result.length, 3);
      expect(result.reason, 'Enter the actual delivery date.');
    });

    test('a complete record is accepted', () {
      expect(
        Rules.canMarkDelivered({
          'actualDeliveryDate': DateTime(2026, 9, 1),
          'receivedBy': 'Anbarasan Krishnamoorthy',
          'proofOfDelivery': 'challan-0142.jpg',
        }).allowed,
        isTrue,
      );
    });

    test('a missing signature alone still blocks', () {
      final result = Rules.canMarkDelivered({
        'actualDeliveryDate': DateTime(2026, 9, 1),
        'receivedBy': 'Anbarasan Krishnamoorthy',
      });
      expect(result.reason, 'Attach proof of delivery.');
      expect(result.firstField, 'proofOfDelivery');
    });
  });

  group('R-09 welding and grinding derive one status', () {
    SubRecordState sub(String key, String status) =>
        SubRecordState(key: key, status: status);

    test('the stage stays open until both activities finish', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.weldingGrinding,
        now: _now,
        subRecords: {
          'welding': sub('welding', 'Completed'),
          'grinding': sub('grinding', 'In Process'),
        },
      );
      expect(result.blocked, isTrue);
      expect(result.reason, 'Complete grinding before finishing this stage.');
    });

    test('both complete finishes the stage', () {
      expect(
        Rules.canCompleteStage(
          _order(),
          StageKey.weldingGrinding,
          now: _now,
          subRecords: {
            'welding': sub('welding', 'Completed'),
            'grinding': sub('grinding', 'Completed'),
          },
        ).allowed,
        isTrue,
      );
    });

    test('the derived status reflects both activities', () {
      expect(
        Rules.deriveWeldingGrindingStatus({
          'welding': sub('welding', 'Completed'),
          'grinding': sub('grinding', 'Completed'),
        }),
        'Completed',
      );
      expect(
        Rules.deriveWeldingGrindingStatus({
          'welding': sub('welding', 'Completed'),
          'grinding': sub('grinding', 'Not Started'),
        }),
        'In Process',
      );
      expect(
        Rules.deriveWeldingGrindingStatus({
          'welding': sub('welding', 'On Hold'),
          'grinding': sub('grinding', 'Not Started'),
        }),
        'On Hold',
      );
      expect(
        Rules.deriveWeldingGrindingStatus({
          'welding': sub('welding', 'Rework Required'),
          'grinding': sub('grinding', 'Not Started'),
        }),
        'Rework',
      );
      expect(
        Rules.deriveWeldingGrindingStatus({
          'welding': sub('welding', 'Not Started'),
          'grinding': sub('grinding', 'Not Started'),
        }),
        'Not Started',
      );
    });
  });

  group('R-10 timestamps stay coherent', () {
    test('completion cannot precede the start', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.painting,
        now: _now,
        values: {
          'jobNumber': 'ORD-0142',
          'component': 'Housing',
          'quantity': 118,
          'paintType': 'Powder coat',
          'paintColour': 'Signal grey',
          'paintCode': 'RAL 7004',
          'paintingMethod': 'Electrostatic spray',
          'operatorName': 'Ramanathan Selvaraj',
          'startDate': DateTime(2026, 8, 28),
          'completionDate': DateTime(2026, 8, 27),
        },
      );
      expect(result.blocked, isTrue);
      expect(result.reason, 'Completion date cannot be earlier than the start.');
    });

    test('completion cannot be in the future', () {
      final result = Rules.canCompleteStage(
        _order(),
        StageKey.painting,
        now: _now,
        values: {
          'jobNumber': 'ORD-0142',
          'component': 'Housing',
          'quantity': 118,
          'paintType': 'Powder coat',
          'paintColour': 'Signal grey',
          'paintCode': 'RAL 7004',
          'paintingMethod': 'Electrostatic spray',
          'operatorName': 'Ramanathan Selvaraj',
          'startDate': DateTime(2026, 8, 28),
          'completionDate': DateTime(2026, 9, 15),
        },
      );
      expect(result.reason, 'Completion date cannot be in the future.');
    });
  });

  group('R-12 permissions', () {
    test('an operator can only work at their own station', () {
      expect(
        Rules.canExecuteStage(_operator, _order(), StageKey.laserCutting)
            .allowed,
        isTrue,
      );
      final elsewhere =
          Rules.canExecuteStage(_operator, _order(), StageKey.painting);
      expect(elsewhere.blocked, isTrue);
      expect(
        elsewhere.reason,
        'You are signed in at Laser Cutting. Switch station to update '
        'Painting.',
      );
    });

    test('quality is recorded by an inspector, not an operator', () {
      expect(
        Rules.canExecuteStage(_operator, _order(), StageKey.qualityTesting)
            .reason,
        'Quality checks are recorded by a quality inspector.',
      );
      expect(
        Rules.canExecuteStage(_inspector, _order(), StageKey.qualityTesting)
            .allowed,
        isTrue,
      );
    });

    test('dispatch covers the last three stages only', () {
      for (final stage in [
        StageKey.readyForDispatch,
        StageKey.dispatch,
        StageKey.delivery,
      ]) {
        expect(Rules.canExecuteStage(_dispatch, _order(), stage).allowed,
            isTrue);
      }
      expect(
        Rules.canExecuteStage(_dispatch, _order(), StageKey.painting).reason,
        'Dispatch can update dispatch and delivery stages only.',
      );
    });

    test('a manager can execute any stage', () {
      for (final stage in StageKey.ordered) {
        expect(Rules.canExecuteStage(_manager, _order(), stage).allowed,
            isTrue);
      }
    });

    test('only a manager edits a completed stage', () {
      expect(Rules.canEditCompletedStage(_manager).allowed, isTrue);
      expect(
        Rules.canEditCompletedStage(_operator).reason,
        'Only a manager can change a completed stage.',
      );
    });
  });

  group('advancement', () {
    test('a cancelled order cannot advance', () {
      final result =
          Rules.canAdvance(_order(cancelled: true), _manager, now: _now);
      expect(result.reason, 'This order has been cancelled.');
    });

    test('a finished order cannot advance', () {
      final order = _order(completedThrough: StageKey.delivery.index);
      expect(order.isFinished, isTrue);
      expect(
        Rules.canAdvance(order, _manager, now: _now).reason,
        'This order is already complete.',
      );
    });
  });

  group('derived material state', () {
    test('material in process is stated rather than inferred', () {
      expect(Rules.materialIsInProcess('In Process'), isTrue);
      expect(Rules.materialIsInProcess('Quality Check Pending'), isTrue);
      expect(Rules.materialIsInProcess('Not Received'), isFalse);
      expect(Rules.materialIsInProcess('Completed'), isFalse);
    });
  });

  group('order derivations', () {
    test('current stage is the first incomplete one', () {
      final order = _order(completedThrough: StageKey.painting.index);
      expect(order.currentStageKey, StageKey.qualityTesting);
      expect(order.completedStageCount, 4);
      expect(order.progress, closeTo(0.4, 0.001));
    });

    test('overdue is measured against the due date', () {
      final order = _order();
      expect(order.isOverdue(DateTime(2026, 9, 5)), isTrue);
      expect(order.isOverdue(DateTime(2026, 8, 30)), isFalse);
      expect(order.daysUntilDue(_now), 3);
    });

    test('a failed check surfaces on the order', () {
      final order = _order(tests: [
        for (final d in kQualityTests)
          _test(d,
              status: d.key == 'load' ? TestStatus.failed : TestStatus.passed),
      ]);
      expect(order.hasQualityFailure, isTrue);
      expect(order.failedTests.single.name, 'Load Test');
      expect(order.needsAttention, isTrue);
    });
  });
}
