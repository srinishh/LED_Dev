import '../domain/models/models.dart';
import '../domain/rules.dart';
import '../domain/stage_schema.dart';
import 'order_repository.dart';

/// Seed data for the in-memory repository.
///
/// The set is built so that every rule and every screen state can be reached
/// from real data rather than described in the abstract: a quality failure
/// holding an order at the gate, two orders on hold, one in rework, one held
/// back from dispatch with a reason, one overdue, one short on material, and
/// one delivered and closed.
///
/// Names, quantities and identifiers are deliberately specific. Round numbers
/// and placeholder names make a demo read as a mock rather than as a plant.

/// The clock the seed is built around, so relative dates stay stable.
final DateTime kSeedNow = DateTime(2026, 8, 30, 14, 20);

const kMasterData = MasterData(
  suppliers: [
    'Kaveri Metals and Alloys',
    'Perumal Sheet Works',
    'Vaigai Extrusions',
    'Sri Balaji Steel Traders',
    'Hindustan Aluminium Depot',
  ],
  machines: [
    'LC-01 Trumpf 3030',
    'LC-02 Amada LCG',
    'WS-04 MIG bay',
    'WS-05 TIG bay',
    'GR-02 belt grinder',
    'PB-01 powder booth',
  ],
  operators: [
    'Ramanathan Selvaraj',
    'Farhan Qureshi',
    'Meenakshi Balan',
    'Devika Ranganathan',
    'Joseph Anthonysamy',
    'Nandini Venkatesh',
    'Ashwin Pillai',
    'Sharmila Devarajan',
  ],
  paintTypes: ['Powder coat', 'Epoxy primer', 'PU top coat'],
  paintColours: [
    'Signal grey',
    'Traffic white',
    'Anthracite',
    'Jet black',
    'Pure white',
  ],
  paintCodes: {
    'Signal grey': 'RAL 7004',
    'Traffic white': 'RAL 9016',
    'Anthracite': 'RAL 7016',
    'Jet black': 'RAL 9005',
    'Pure white': 'RAL 9010',
  },
  paintingMethods: ['Electrostatic spray', 'Dip coat', 'Manual spray'],
  packingTypes: [
    'Carton with foam insert',
    'Wooden crate',
    'Shrink wrapped pallet',
    'Corrugated box',
  ],
  transporters: [
    'Sundaram Roadways',
    'VRL Logistics',
    'Kaveri Cargo Movers',
    'TCI Freight',
  ],
  components: [
    'LED module 50W',
    'LED module 150W',
    'Constant current driver 150W',
    'Constant current driver 50W',
    'Toughened glass diffuser',
    'Silicone gasket',
    'Surge protection device',
    'Mounting bracket set',
  ],
  workStatuses: ['Not Started', 'In Process', 'Completed', 'Rework Required'],
  customers: [
    'Anaimalai Textiles',
    'Coimbatore Metro Works',
    'Cuddalore Chemicals',
    'Dindigul Lock Works',
    'Erode Spinning Mills',
    'Hosur Auto Components',
    'Kanchipuram Silk Weavers Society',
    'Karur Paper Mills',
    'Kaveri Switchgear',
    'Madurai Transport Corporation',
    'Namakkal Poultry Farms',
    'Nilgiri Tea Estates',
    'Northline Infra Projects',
    'Pollachi Cold Storage',
    'Ramco Cements Depot',
    'Salem Steel Fabricators',
    'Sundaram Metals',
    'Thoothukudi Port Services',
    'Tiruppur Knitwear Park',
    'Trichy Rail Workshop',
    'Vaidya Electricals',
    'Villupuram Sugar Mills',
  ],
  products: [
    'LED Panel 600x600',
    'LED Panel 300x1200',
    'LED High Bay 100W',
    'LED High Bay 150W',
    'LED Bay Light 80W',
    'LED Flood Light 200W',
    'LED Flood Light 400W',
    'LED Street Light 90W',
    'LED Street Light 120W',
    'LED Batten 20W',
    'LED Batten 40W',
  ],
);

/// The material a product is normally made from, so raising a jobsheet fills
/// in what the plant already knows.
({String name, String code}) materialForProduct(String product) {
  if (product.contains('Panel')) {
    return (name: 'CRCA sheet 1.2mm', code: 'CRCA-12-4X8');
  }
  if (product.contains('Batten')) {
    return (name: 'Aluminium profile 35mm', code: 'ALP-35-3M');
  }
  return (name: 'Aluminium sheet 2mm', code: 'AL-2MM-4X8');
}

/// Shape of one seeded order before stage records are built.
class _Spec {
  const _Spec({
    required this.no,
    required this.customer,
    required this.product,
    required this.quantity,
    required this.priority,
    required this.receivedDaysAgo,
    required this.dueInDays,
    required this.completedThrough,
    this.currentStatus,
    this.qualityOverrides = const {},
    this.notDispatched,
    this.materialShortfall,
    this.notes,
  });

  final String no;
  final String customer;
  final String product;
  final int quantity;
  final Priority priority;
  final int receivedDaysAgo;
  final int dueInDays;

  /// Index of the last stage that is complete. -1 means nothing is done.
  final int completedThrough;

  /// Status of the stage the order is sitting at, when it is not the plain
  /// in-process value.
  final String? currentStatus;

  final Map<String, TestStatus> qualityOverrides;
  final NotDispatchedReason? notDispatched;

  /// Quantity actually received, when less than required.
  final int? materialShortfall;

  final String? notes;
}

const _specs = <_Spec>[
  // Held at the quality gate. This is the blueprint's hardest rule and the
  // order the manager journey opens on.
  _Spec(
    no: 'ORD-0138',
    customer: 'Northline Infra Projects',
    product: 'LED High Bay 150W',
    quantity: 96,
    priority: Priority.urgent,
    receivedDaysAgo: 21,
    dueInDays: -1,
    completedThrough: 3,
    qualityOverrides: {
      'load': TestStatus.failed,
      'insulation': TestStatus.notTested,
    },
    notes: 'Deflection measured 3.2mm against a 2.0mm limit on the first '
        'load test.',
  ),

  _Spec(
    no: 'ORD-0142',
    customer: 'Sundaram Metals',
    product: 'LED Panel 600x600',
    quantity: 118,
    priority: Priority.high,
    receivedDaysAgo: 18,
    dueInDays: 3,
    completedThrough: 2,
  ),

  // On hold, waiting on the powder booth.
  _Spec(
    no: 'ORD-0135',
    customer: 'Vaidya Electricals',
    product: 'LED Flood Light 200W',
    quantity: 64,
    priority: Priority.standard,
    receivedDaysAgo: 24,
    dueInDays: 6,
    completedThrough: 1,
    currentStatus: 'On Hold',
    notes: 'Powder booth down for filter replacement.',
  ),

  // Rework after a welding inspection.
  _Spec(
    no: 'ORD-0129',
    customer: 'Kaveri Switchgear',
    product: 'LED Street Light 90W',
    quantity: 240,
    priority: Priority.high,
    receivedDaysAgo: 29,
    dueInDays: 2,
    completedThrough: 1,
    currentStatus: 'Rework',
    notes: 'Porosity found on 14 housings at the corner welds.',
  ),

  // Short on material, so the stage cannot pass Partially Received.
  _Spec(
    no: 'ORD-0151',
    customer: 'Anaimalai Textiles',
    product: 'LED Batten 40W',
    quantity: 420,
    priority: Priority.standard,
    receivedDaysAgo: 6,
    dueInDays: 14,
    completedThrough: -1,
    currentStatus: 'Partially Received',
    materialShortfall: 265,
  ),

  // Held back from dispatch, with a reason on the record.
  _Spec(
    no: 'ORD-0117',
    customer: 'Ramco Cements Depot',
    product: 'LED High Bay 100W',
    quantity: 72,
    priority: Priority.high,
    receivedDaysAgo: 38,
    dueInDays: -3,
    completedThrough: 6,
    currentStatus: 'Not Dispatched',
    notDispatched: NotDispatchedReason.vehicleNotAvailable,
  ),

  _Spec(
    no: 'ORD-0119',
    customer: 'Erode Spinning Mills',
    product: 'LED Panel 300x1200',
    quantity: 156,
    priority: Priority.standard,
    receivedDaysAgo: 35,
    dueInDays: -2,
    completedThrough: 7,
    notDispatched: null,
  ),

  // On the road.
  _Spec(
    no: 'ORD-0112',
    customer: 'Coimbatore Metro Works',
    product: 'LED Flood Light 400W',
    quantity: 38,
    priority: Priority.standard,
    receivedDaysAgo: 44,
    dueInDays: 1,
    completedThrough: 8,
    currentStatus: 'In Transit',
  ),

  // Delivered and closed.
  _Spec(
    no: 'ORD-0104',
    customer: 'Salem Steel Fabricators',
    product: 'LED High Bay 150W',
    quantity: 84,
    priority: Priority.standard,
    receivedDaysAgo: 52,
    dueInDays: -8,
    completedThrough: 9,
  ),

  _Spec(
    no: 'ORD-0144',
    customer: 'Tiruppur Knitwear Park',
    product: 'LED Batten 20W',
    quantity: 610,
    priority: Priority.standard,
    receivedDaysAgo: 15,
    dueInDays: 9,
    completedThrough: 1,
  ),
  _Spec(
    no: 'ORD-0146',
    customer: 'Madurai Transport Corporation',
    product: 'LED Street Light 120W',
    quantity: 188,
    priority: Priority.high,
    receivedDaysAgo: 13,
    dueInDays: 7,
    completedThrough: 1,
  ),
  _Spec(
    no: 'ORD-0147',
    customer: 'Sundaram Metals',
    product: 'LED Panel 600x600',
    quantity: 92,
    priority: Priority.standard,
    receivedDaysAgo: 12,
    dueInDays: 11,
    completedThrough: 0,
  ),
  _Spec(
    no: 'ORD-0149',
    customer: 'Hosur Auto Components',
    product: 'LED Bay Light 80W',
    quantity: 134,
    priority: Priority.standard,
    receivedDaysAgo: 9,
    dueInDays: 12,
    completedThrough: 0,
  ),
  _Spec(
    no: 'ORD-0152',
    customer: 'Trichy Rail Workshop',
    product: 'LED Flood Light 200W',
    quantity: 46,
    priority: Priority.high,
    receivedDaysAgo: 5,
    dueInDays: 16,
    completedThrough: -1,
  ),
  _Spec(
    no: 'ORD-0153',
    customer: 'Vaidya Electricals',
    product: 'LED Batten 40W',
    quantity: 275,
    priority: Priority.standard,
    receivedDaysAgo: 4,
    dueInDays: 18,
    completedThrough: -1,
    currentStatus: 'Not Received',
  ),
  _Spec(
    no: 'ORD-0140',
    customer: 'Karur Paper Mills',
    product: 'LED High Bay 100W',
    quantity: 58,
    priority: Priority.standard,
    receivedDaysAgo: 17,
    dueInDays: 5,
    completedThrough: 3,
  ),
  _Spec(
    no: 'ORD-0136',
    customer: 'Nilgiri Tea Estates',
    product: 'LED Batten 20W',
    quantity: 340,
    priority: Priority.standard,
    receivedDaysAgo: 22,
    dueInDays: 4,
    completedThrough: 4,
  ),
  _Spec(
    no: 'ORD-0133',
    customer: 'Pollachi Cold Storage',
    product: 'LED Bay Light 80W',
    quantity: 71,
    priority: Priority.high,
    receivedDaysAgo: 26,
    dueInDays: 1,
    completedThrough: 5,
  ),
  _Spec(
    no: 'ORD-0131',
    customer: 'Dindigul Lock Works',
    product: 'LED Panel 300x1200',
    quantity: 122,
    priority: Priority.standard,
    receivedDaysAgo: 27,
    dueInDays: 3,
    completedThrough: 5,
  ),
  _Spec(
    no: 'ORD-0127',
    customer: 'Thoothukudi Port Services',
    product: 'LED Flood Light 400W',
    quantity: 29,
    priority: Priority.urgent,
    receivedDaysAgo: 31,
    dueInDays: 0,
    completedThrough: 6,
  ),
  _Spec(
    no: 'ORD-0124',
    customer: 'Namakkal Poultry Farms',
    product: 'LED Batten 40W',
    quantity: 388,
    priority: Priority.standard,
    receivedDaysAgo: 33,
    dueInDays: -1,
    completedThrough: 6,
  ),
  _Spec(
    no: 'ORD-0121',
    customer: 'Kanchipuram Silk Weavers Society',
    product: 'LED Panel 600x600',
    quantity: 164,
    priority: Priority.standard,
    receivedDaysAgo: 34,
    dueInDays: 2,
    completedThrough: 7,
  ),
  _Spec(
    no: 'ORD-0109',
    customer: 'Cuddalore Chemicals',
    product: 'LED High Bay 150W',
    quantity: 53,
    priority: Priority.standard,
    receivedDaysAgo: 47,
    dueInDays: -5,
    completedThrough: 8,
    currentStatus: 'In Transit',
  ),
  _Spec(
    no: 'ORD-0101',
    customer: 'Villupuram Sugar Mills',
    product: 'LED Street Light 90W',
    quantity: 210,
    priority: Priority.standard,
    receivedDaysAgo: 56,
    dueInDays: -12,
    completedThrough: 9,
  ),
];

/// Builds the full seeded order book together with its timeline.
({List<Order> orders, Map<String, List<TimelineEvent>> timelines}) buildSeed() {
  final orders = <Order>[];
  final timelines = <String, List<TimelineEvent>>{};

  for (var i = 0; i < _specs.length; i++) {
    final spec = _specs[i];
    final id = 'order-${spec.no}';
    final received = kSeedNow.subtract(Duration(days: spec.receivedDaysAgo));
    final events = <TimelineEvent>[];

    events.add(TimelineEvent(
      orderId: id,
      type: TimelineEventType.orderCreated,
      actor: 'Devika Ranganathan',
      at: received,
      summary: 'Order received from ${spec.customer}',
      detail: '${spec.quantity} units of ${spec.product}',
    ));

    final stages = <StageKey, StageRecord>{};
    // Work is spread across the days between receipt and now.
    final span = spec.receivedDaysAgo.clamp(1, 60);

    for (final key in StageKey.ordered) {
      final schema = schemaFor(key);
      final position = key.index;
      final startedAt = received.add(
        Duration(hours: (span * 24 * position ~/ 11) + 6),
      );

      if (position <= spec.completedThrough) {
        final completedAt = startedAt.add(Duration(hours: 6 + (position * 3)));
        final actor = kMasterData.operators[(i + position) % 8];
        stages[key] = StageRecord(
          stageKey: key,
          status: schema.terminalStatus,
          values: _valuesFor(spec, key, startedAt, completedAt, actor),
          subRecords: _subRecordsFor(key, 'Completed', startedAt, actor),
          startedAt: startedAt,
          completedAt: completedAt,
          updatedBy: actor,
          updatedAt: completedAt,
        );

        events.add(TimelineEvent(
          orderId: id,
          stageKey: key,
          type: TimelineEventType.stageStarted,
          actor: actor,
          at: startedAt,
          summary: '${schema.name} started',
        ));
        events.add(TimelineEvent(
          orderId: id,
          stageKey: key,
          type: key == StageKey.dispatch
              ? TimelineEventType.dispatched
              : key == StageKey.delivery
                  ? TimelineEventType.delivered
                  : TimelineEventType.stageCompleted,
          actor: actor,
          at: completedAt,
          summary: '${schema.name} completed',
          detail: _completionDetail(spec, key),
        ));
      } else if (position == spec.completedThrough + 1) {
        // The stage the order is sitting at.
        final status = spec.currentStatus ?? _inProgressStatus(key);
        final actor = kMasterData.operators[(i + position) % 8];
        final isIdle = status == schema.initialStatus;
        stages[key] = StageRecord(
          stageKey: key,
          status: status,
          values: _valuesFor(spec, key, startedAt, null, actor),
          subRecords: _subRecordsFor(key, status, startedAt, actor),
          startedAt: isIdle ? null : startedAt,
          updatedBy: isIdle ? null : actor,
          updatedAt: isIdle ? null : startedAt,
        );
        if (!isIdle) {
          events.add(TimelineEvent(
            orderId: id,
            stageKey: key,
            type: TimelineEventType.stageStarted,
            actor: actor,
            at: startedAt,
            summary: '${schema.name} started',
          ));
          if (status == 'On Hold' || status == 'Rework') {
            events.add(TimelineEvent(
              orderId: id,
              stageKey: key,
              type: TimelineEventType.statusChanged,
              actor: actor,
              at: startedAt.add(const Duration(hours: 4)),
              summary: '${schema.name} moved to $status',
              detail: spec.notes,
              severity: EventSeverity.warning,
            ));
          }
        }
      } else {
        stages[key] = StageRecord(
          stageKey: key,
          status: schema.initialStatus,
          subRecords: _subRecordsFor(key, 'Not Started', null, null),
        );
      }
    }

    // Quality checklist.
    final qualityDone = spec.completedThrough >= StageKey.qualityTesting.index;
    final tests = <QualityTestRecord>[];
    for (final def in kQualityTests) {
      final override = spec.qualityOverrides[def.key];
      final status = override ??
          (qualityDone ? TestStatus.passed : TestStatus.notTested);
      final tester = kMasterData.operators[(i + def.key.length) % 8];
      final testedAt = received.add(Duration(days: span - 2, hours: 11));
      final recorded = status != TestStatus.notTested;

      tests.add(QualityTestRecord(
        definition: def,
        status: status,
        result: switch (status) {
          TestStatus.passed => TestResult.pass,
          TestStatus.failed => TestResult.fail,
          _ => TestResult.pending,
        },
        testedBy: recorded ? tester : null,
        testedAt: recorded ? testedAt : null,
        notes: status == TestStatus.failed ? spec.notes : null,
      ));

      if (recorded) {
        events.add(TimelineEvent(
          orderId: id,
          stageKey: StageKey.qualityTesting,
          type: TimelineEventType.qualityRecorded,
          actor: tester,
          at: testedAt,
          summary: '${def.name} ${status == TestStatus.passed ? 'passed' : ''
              '${status.label.toLowerCase()}'}',
          detail: status == TestStatus.failed ? spec.notes : null,
          severity: status == TestStatus.failed
              ? EventSeverity.critical
              : EventSeverity.normal,
        ));
      }
    }

    if (spec.qualityOverrides.values.any((s) => s == TestStatus.failed)) {
      events.add(TimelineEvent(
        orderId: id,
        stageKey: StageKey.qualityTesting,
        type: TimelineEventType.blocked,
        actor: 'System',
        at: received.add(Duration(days: span - 2, hours: 12)),
        summary: 'Order held at Quality Testing',
        detail: 'Wiring and Assembly cannot start until the failed check '
            'passes.',
        severity: EventSeverity.critical,
      ));
    }

    events.sort((a, b) => a.at.compareTo(b.at));
    timelines[id] = events;

    orders.add(Order(
      id: id,
      orderNo: spec.no,
      customer: spec.customer,
      product: spec.product,
      quantity: spec.quantity,
      priority: spec.priority,
      receivedAt: received,
      dueAt: kSeedNow.add(Duration(days: spec.dueInDays)),
      stages: stages,
      qualityTests: tests,
      notes: spec.notes,
      dispatch: DispatchRecord(
        notDispatchedReason: spec.notDispatched,
      ),
    ));
  }

  return (orders: orders, timelines: timelines);
}

String _inProgressStatus(StageKey key) => switch (key) {
      StageKey.rawMaterial => 'In Process',
      StageKey.qualityTesting => 'In Testing',
      StageKey.wiringAssembly => 'Wiring In Process',
      StageKey.packingLabelling => 'Packing In Process',
      StageKey.readyForDispatch => 'Not Ready',
      StageKey.dispatch => 'In Process',
      StageKey.delivery => 'Dispatched',
      _ => 'In Process',
    };

String? _completionDetail(_Spec spec, StageKey key) => switch (key) {
      StageKey.laserCutting => '${spec.quantity} pieces cut',
      StageKey.dispatch => 'Invoice INV-2026-${spec.no.substring(4)}',
      StageKey.delivery => 'Received at ${spec.customer}',
      _ => null,
    };

Map<String, SubRecordState> _subRecordsFor(
  StageKey key,
  String stageStatus,
  DateTime? start,
  String? actor,
) {
  if (key != StageKey.weldingGrinding) return const {};

  // The stage status is derived from these two activities, so the seed has to
  // set the activities such that the derivation reproduces the stage status
  // it claims. Welding carries the exceptional state; grinding follows.
  final (welding, grinding) = switch (stageStatus) {
    'Completed' => ('Completed', 'Completed'),
    'On Hold' => ('On Hold', 'Not Started'),
    'Rework' => ('Rework Required', 'Not Started'),
    'In Process' => ('In Process', 'Not Started'),
    _ => ('Not Started', 'Not Started'),
  };

  return {
    'welding': SubRecordState(
      key: 'welding',
      status: welding,
      values: {
        'welder': actor,
        'workstation': 'WS-04 MIG bay',
        'componentName': 'Housing frame',
        'startDate': ?start,
      },
    ),
    'grinding': SubRecordState(
      key: 'grinding',
      status: grinding,
      values: {
        'operatorName': actor,
        if (start != null && grinding != 'Not Started') 'startDate': start,
      },
    ),
  };
}

Map<String, Object?> _valuesFor(
  _Spec spec,
  StageKey key,
  DateTime start,
  DateTime? end,
  String actor,
) {
  final jobNo = spec.no;
  switch (key) {
    case StageKey.rawMaterial:
      final available = spec.materialShortfall ?? spec.quantity;
      return {
        'materialName': _materialFor(spec.product),
        'materialCode': _materialCode(spec.product),
        'requiredQuantity': spec.quantity,
        'availableQuantity': available,
        'supplier': kMasterData.suppliers[spec.no.hashCode.abs() % 5],
        'purchaseOrderNumber': 'PO-2026-${spec.no.substring(4)}',
        'materialReceivedDate': start,
        if (spec.materialShortfall != null)
          'remarks': 'Balance ${spec.quantity - available} pieces promised '
              'next week.',
      };

    case StageKey.laserCutting:
      return {
        'jobNumber': jobNo,
        'materialName': _materialFor(spec.product),
        'materialQuantity': spec.quantity,
        'requiredCuttingQuantity': spec.quantity,
        'actualQuantityCut': ?(end != null ? spec.quantity : null),
        'machineNumber': kMasterData.machines[spec.no.hashCode.abs() % 2],
        'operatorName': actor,
        'startedAt': start,
        'completedAt': ?end,
      };

    case StageKey.painting:
      const colour = 'Signal grey';
      return {
        'jobNumber': jobNo,
        'component': '${spec.product} housing',
        'quantity': spec.quantity,
        'paintType': 'Powder coat',
        'paintColour': colour,
        'paintCode': kMasterData.paintCodes[colour],
        'paintingMethod': 'Electrostatic spray',
        'operatorName': actor,
        'startDate': start,
        'completionDate': ?end,
      };

    case StageKey.wiringAssembly:
      final done = end != null;
      return {
        'jobNumber': jobNo,
        'productName': spec.product,
        'quantity': spec.quantity,
        'wiringStatus': done ? 'Completed' : 'In Process',
        'assemblyStatus': done ? 'Completed' : 'Not Started',
        'technicianName': actor,
        'startedAt': start,
        if (done) 'completedAt': end,
        if (done)
          'componentsUsed': [
            '${_moduleFor(spec.product)} x${spec.quantity}',
            'Constant current driver x${spec.quantity}',
            'Silicone gasket x${spec.quantity}',
          ],
      };

    case StageKey.packingLabelling:
      final boxes = (spec.quantity / 8).ceil();
      final done = end != null;
      return {
        'productName': spec.product,
        'jobNumber': jobNo,
        'quantity': spec.quantity,
        'numberOfBoxes': boxes,
        'packingType': 'Carton with foam insert',
        'packedBy': actor,
        'packingDate': start,
        'labelNumber': 'LBL-2026-${spec.no.substring(4)}',
        'batchNumber': 'BTH-${spec.no.substring(4)}09',
        'serialNumber': 'SN-${spec.quantity}-${spec.no.substring(4)}',
        'labelVerification': done,
      };

    case StageKey.readyForDispatch:
      return {
        'jobNumber': jobNo,
        'customerName': spec.customer,
        'product': spec.product,
        'quantity': spec.quantity,
        'packingCompletedDate': start,
        'readyForDispatchDate': start.add(const Duration(days: 1)),
      };

    case StageKey.dispatch:
      return {
        'invoiceNumber': 'INV-2026-${spec.no.substring(4)}',
        'invoiceDate': start,
        'dispatchDate': start,
        'customerName': spec.customer,
        'deliveryAddress': _addressFor(spec.customer),
        'numberOfPackages': (spec.quantity / 8).ceil(),
        'quantityDispatched': spec.quantity,
        'vehicleNumber': _vehicleFor(spec.no),
        'driverName': _driverFor(spec.no),
        'driverContactNumber': _phoneFor(spec.no),
        'transporterName':
            kMasterData.transporters[spec.no.hashCode.abs() % 4],
        'lrNumber': 'LR-${spec.no.hashCode.abs() % 90000 + 10000}',
      };

    case StageKey.delivery:
      return {
        'dispatchDate': start.subtract(const Duration(days: 2)),
        'customerName': spec.customer,
        'vehicleNumber': _vehicleFor(spec.no),
        'invoiceNumber': 'INV-2026-${spec.no.substring(4)}',
        'expectedDeliveryDate': start.add(const Duration(days: 1)),
        'actualDeliveryDate': ?end,
        if (end != null) 'receivedBy': _receiverFor(spec.customer),
        if (end != null) 'proofOfDelivery': 'Signed challan',
      };

    default:
      return {'jobNumber': jobNo};
  }
}

String _materialFor(String product) => product.contains('Panel')
    ? 'CRCA sheet 1.2mm'
    : product.contains('Batten')
        ? 'Aluminium profile 35mm'
        : 'Aluminium sheet 2mm';

String _materialCode(String product) => product.contains('Panel')
    ? 'CRCA-12-4X8'
    : product.contains('Batten')
        ? 'ALP-35-3M'
        : 'AL-2MM-4X8';

String _moduleFor(String product) =>
    product.contains('150W') ? 'LED module 150W' : 'LED module 50W';

String _addressFor(String customer) =>
    '$customer\nPlot 14, SIDCO Industrial Estate\nCoimbatore 641021';

String _vehicleFor(String no) {
  const series = ['TN 38 BQ', 'TN 45 AZ', 'KA 05 CH', 'TN 66 DL'];
  final h = no.hashCode.abs();
  return '${series[h % 4]} ${h % 9000 + 1000}';
}

String _driverFor(String no) {
  const drivers = [
    'Murugesan Palanisamy',
    'Abdul Rahman Shaikh',
    'Karthikeyan Duraisamy',
    'Sathish Kumar Manickam',
  ];
  return drivers[no.hashCode.abs() % 4];
}

String _phoneFor(String no) {
  final h = no.hashCode.abs();
  return '+91 9${(h % 900000000 + 100000000)}';
}

String _receiverFor(String customer) {
  const receivers = [
    'Anbarasan Krishnamoorthy',
    'Latha Subramanian',
    'Ilango Ravichandran',
    'Preethi Nagarajan',
  ];
  return receivers[customer.hashCode.abs() % 4];
}

/// Alerts derived from order state, so the list never drifts from the data.
List<Alert> deriveAlerts(List<Order> orders, DateTime now) {
  final alerts = <Alert>[];

  for (final order in orders) {
    for (final test in order.failedTests) {
      alerts.add(Alert(
        id: '${order.id}-quality-${test.definition.key}',
        orderId: order.id,
        orderNo: order.orderNo,
        stageKey: StageKey.qualityTesting,
        title: '${test.name} failed',
        detail: test.notes ??
            'The order cannot move to Wiring and Assembly until this passes.',
        severity: EventSeverity.critical,
        raisedAt: test.testedAt ?? now,
      ));
    }

    for (final stage in order.stagesNeedingAttention) {
      if (stage.stageKey == StageKey.qualityTesting) continue;
      alerts.add(Alert(
        id: '${order.id}-stage-${stage.stageKey.name}',
        orderId: order.id,
        orderNo: order.orderNo,
        stageKey: stage.stageKey,
        title: '${stage.schema.name} is ${stage.status.toLowerCase()}',
        detail: order.notes ?? 'Needs a decision before work can continue.',
        severity: stage.family.name == 'failed'
            ? EventSeverity.critical
            : EventSeverity.warning,
        raisedAt: stage.updatedAt ?? now,
      ));
    }

    final reason = order.dispatch.reasonLabel;
    if (reason != null) {
      alerts.add(Alert(
        id: '${order.id}-dispatch',
        orderId: order.id,
        orderNo: order.orderNo,
        stageKey: StageKey.dispatch,
        title: 'Not dispatched',
        detail: reason,
        severity: EventSeverity.warning,
        raisedAt: order.stage(StageKey.readyForDispatch).updatedAt ?? now,
      ));
    }

    if (order.isOverdue(now)) {
      final late = now.difference(order.dueAt).inDays;
      alerts.add(Alert(
        id: '${order.id}-overdue',
        orderId: order.id,
        orderNo: order.orderNo,
        title: 'Overdue by ${late == 0 ? 'less than a day' : '$late day'
            '${late == 1 ? '' : 's'}'}',
        detail: 'Due ${order.dueAt.day}/${order.dueAt.month}, still at '
            '${order.currentStage.schema.name}.',
        severity: EventSeverity.warning,
        raisedAt: order.dueAt,
      ));
    }
  }

  alerts.sort((a, b) {
    final bySeverity = b.severity.index.compareTo(a.severity.index);
    if (bySeverity != 0) return bySeverity;
    return b.raisedAt.compareTo(a.raisedAt);
  });
  return alerts;
}

/// Sanity check used by the seed test: the demo data must actually contain
/// each exception the screens are designed to show.
({
  int qualityFailures,
  int onHold,
  int rework,
  int notDispatched,
  int overdue,
  int materialShort,
  int delivered,
}) seedCoverage(List<Order> orders, DateTime now) {
  var onHold = 0;
  var rework = 0;
  var materialShort = 0;

  for (final order in orders) {
    for (final key in StageKey.ordered) {
      final status = order.stage(key).status;
      if (status == 'On Hold') onHold++;
      if (status == 'Rework' || status == 'Rework Required') rework++;
      if (status == 'Partially Received') materialShort++;
    }
  }

  return (
    qualityFailures: orders.where((o) => o.hasQualityFailure).length,
    onHold: onHold,
    rework: rework,
    notDispatched:
        orders.where((o) => o.dispatch.notDispatchedReason != null).length,
    overdue: orders.where((o) => o.isOverdue(now)).length,
    materialShort: materialShort,
    delivered: orders.where((o) => o.isFinished).length,
  );
}

/// Rules are re-exported here so the seed can assert its own consistency.
bool seedRespectsRules(List<Order> orders) {
  for (final order in orders) {
    // A stage may only be complete if everything before it is complete.
    var seenIncomplete = false;
    for (final key in StageKey.ordered) {
      final complete = order.stage(key).isComplete;
      if (!complete) {
        seenIncomplete = true;
      } else if (seenIncomplete) {
        return false;
      }
    }
    // An order past quality testing must have passed every mandatory check.
    if (order.stage(StageKey.qualityTesting).isComplete &&
        order.blockingTests.isNotEmpty) {
      return false;
    }
    // Welding and grinding must agree with their derived status.
    final wg = order.stage(StageKey.weldingGrinding);
    if (wg.subRecords.isNotEmpty &&
        Rules.deriveWeldingGrindingStatus(wg.subRecords) != wg.status) {
      return false;
    }
  }
  return true;
}
