/// The ten production stages, their captured fields and their status
/// vocabularies, transcribed from the source blueprint.
///
/// This file is the functional contract. Stage Execution renders directly
/// from it, so adding or changing a captured field is a data edit here rather
/// than a new screen.
library;

/// Stable identifiers for the ten stages. The blueprint numbers its steps
/// 1 to 10; those numbers are internal keys only and never appear in the UI,
/// where stages are always named.
enum StageKey {
  rawMaterial,
  laserCutting,
  weldingGrinding,
  painting,
  qualityTesting,
  wiringAssembly,
  packingLabelling,
  readyForDispatch,
  dispatch,
  delivery;

  /// Ordered sequence, matching the blueprint's production flow.
  static const List<StageKey> ordered = StageKey.values;

  int get order => index;

  StageKey? get next =>
      index + 1 < StageKey.values.length ? StageKey.values[index + 1] : null;

  StageKey? get previous => index > 0 ? StageKey.values[index - 1] : null;
}

/// How a field is captured. Drives keyboard type, picker and validation.
enum FieldType {
  text,
  multiline,
  integer,
  phone,
  date,
  dateTime,
  select,
  boolean,
  componentList,
  attachment,
}

/// Where a field's initial value comes from, so operators type as little as
/// possible.
enum DefaultSource {
  none,
  orderNumber,
  orderCustomer,
  orderProduct,
  orderQuantity,
  sessionUser,
  sessionMachine,
  today,
  now,
  lastUsed,
  carriedForward,
}

/// When a field must hold a value.
enum Requirement {
  /// Never blocks.
  optional,

  /// Must be present before the stage can be started or saved.
  required,

  /// Must be present only to mark the stage Completed.
  requiredToComplete,

  /// Required only when a stage-specific condition holds. The condition is
  /// evaluated in `rules.dart`, which owns all conditional logic.
  conditional,
}

/// One captured field on a stage.
class FieldSchema {
  const FieldSchema({
    required this.key,
    required this.label,
    required this.type,
    this.requirement = Requirement.optional,
    this.defaultSource = DefaultSource.none,
    this.readOnly = false,
    this.carriedFrom,
    this.optionsKey,
    this.unit,
    this.group,
    this.helper,
  });

  final String key;
  final String label;
  final FieldType type;
  final Requirement requirement;
  final DefaultSource defaultSource;

  /// Read-only fields are shown with their source named rather than hidden,
  /// so the operator can see where a value came from.
  final bool readOnly;
  final StageKey? carriedFrom;

  /// Key into the master-data tables for [FieldType.select].
  final String? optionsKey;

  /// Trailing unit shown beside a numeric value, for example "pcs".
  final String? unit;

  /// Fieldset heading. Related fields are grouped rather than listed flat.
  final String? group;

  /// Persistent helper text below the input, not a placeholder.
  final String? helper;
}

/// A stage's own status vocabulary. The blueprint gives each stage a different
/// set, and those differences are preserved exactly rather than flattened.
class StatusOption {
  const StatusOption(this.value, {this.terminal = false});

  /// Stored and displayed verbatim, as written in the blueprint.
  final String value;

  /// True for the value that means the stage is finished.
  final bool terminal;
}

/// A complete stage definition.
class StageSchema {
  const StageSchema({
    required this.key,
    required this.name,
    required this.shortName,
    required this.fields,
    required this.statuses,
    required this.initialStatus,
    this.subRecords = const [],
    this.note,
  });

  final StageKey key;

  /// The name shown everywhere in the UI.
  final String name;

  /// Abbreviation for the matrix header, where column width is scarce.
  final String shortName;

  final List<FieldSchema> fields;
  final List<StatusOption> statuses;
  final String initialStatus;

  /// Sub-records for stages that capture two parallel activities, currently
  /// only Welding and Grinding.
  final List<StageSubRecord> subRecords;

  final String? note;

  String get terminalStatus =>
      statuses.firstWhere((s) => s.terminal, orElse: () => statuses.last).value;

  List<String> get statusValues => [for (final s in statuses) s.value];

  /// Fields that must hold a value before the stage can be completed.
  List<FieldSchema> get completionRequiredFields => [
        for (final f in fields)
          if (f.requirement == Requirement.required ||
              f.requirement == Requirement.requiredToComplete)
            f,
      ];

  List<String> get groups {
    final seen = <String>[];
    for (final f in fields) {
      final g = f.group;
      if (g != null && !seen.contains(g)) seen.add(g);
    }
    return seen;
  }

  List<FieldSchema> fieldsIn(String group) =>
      [for (final f in fields) if (f.group == group) f];
}

/// A named group of fields captured as a parallel activity within one stage.
class StageSubRecord {
  const StageSubRecord({
    required this.key,
    required this.name,
    required this.fields,
    required this.statuses,
    required this.initialStatus,
  });

  final String key;
  final String name;
  final List<FieldSchema> fields;
  final List<StatusOption> statuses;
  final String initialStatus;

  List<String> get statusValues => [for (final s in statuses) s.value];
}

// ---------------------------------------------------------------------------
// Shared status vocabularies
// ---------------------------------------------------------------------------

/// The five-value set the blueprint reuses across Laser Cutting and Painting.
const _standardStatuses = <StatusOption>[
  StatusOption('Not Started'),
  StatusOption('In Process'),
  StatusOption('Completed', terminal: true),
  StatusOption('On Hold'),
  StatusOption('Rework Required'),
];

// ---------------------------------------------------------------------------
// The ten stages
// ---------------------------------------------------------------------------

const _rawMaterial = StageSchema(
  key: StageKey.rawMaterial,
  name: 'Raw Material',
  shortName: 'Material',
  initialStatus: 'Not Received',
  statuses: [
    StatusOption('Not Received'),
    StatusOption('Partially Received'),
    StatusOption('Received'),
    StatusOption('Quality Check Pending'),
    StatusOption('Approved'),
    StatusOption('Rejected'),
    StatusOption('In Process'),
    StatusOption('Completed', terminal: true),
  ],
  note: 'Shows whether material is in process, so the state is never inferred '
      'from the status name alone.',
  fields: [
    FieldSchema(
      key: 'materialName',
      label: 'Material name',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Material',
    ),
    FieldSchema(
      key: 'materialCode',
      label: 'Material code',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Material',
      helper: 'Uppercase letters, numbers and dashes.',
    ),
    FieldSchema(
      key: 'requiredQuantity',
      label: 'Required quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Quantities',
    ),
    FieldSchema(
      key: 'availableQuantity',
      label: 'Available quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      unit: 'pcs',
      group: 'Quantities',
      helper: 'Below the required quantity, the status stays at Partially '
          'Received.',
    ),
    FieldSchema(
      key: 'supplier',
      label: 'Supplier',
      type: FieldType.select,
      requirement: Requirement.required,
      defaultSource: DefaultSource.lastUsed,
      optionsKey: 'suppliers',
      group: 'Procurement',
    ),
    FieldSchema(
      key: 'purchaseOrderNumber',
      label: 'Purchase order number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Procurement',
    ),
    FieldSchema(
      key: 'materialReceivedDate',
      label: 'Material received date',
      type: FieldType.date,
      requirement: Requirement.conditional,
      defaultSource: DefaultSource.today,
      group: 'Procurement',
    ),
    FieldSchema(
      key: 'remarks',
      label: 'Remarks',
      type: FieldType.multiline,
      requirement: Requirement.conditional,
      group: 'Notes',
    ),
  ],
);

const _laserCutting = StageSchema(
  key: StageKey.laserCutting,
  name: 'Laser Cutting',
  shortName: 'Cutting',
  initialStatus: 'Not Started',
  statuses: _standardStatuses,
  fields: [
    FieldSchema(
      key: 'jobNumber',
      label: 'Job number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderNumber,
      readOnly: true,
      group: 'Job',
    ),
    FieldSchema(
      key: 'materialName',
      label: 'Material name',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.rawMaterial,
      readOnly: true,
      group: 'Job',
    ),
    FieldSchema(
      key: 'materialQuantity',
      label: 'Material quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.rawMaterial,
      unit: 'pcs',
      group: 'Quantities',
    ),
    FieldSchema(
      key: 'requiredCuttingQuantity',
      label: 'Required cutting quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Quantities',
    ),
    FieldSchema(
      key: 'actualQuantityCut',
      label: 'Actual quantity cut',
      type: FieldType.integer,
      requirement: Requirement.requiredToComplete,
      unit: 'pcs',
      group: 'Quantities',
    ),
    FieldSchema(
      key: 'machineNumber',
      label: 'Machine number',
      type: FieldType.select,
      requirement: Requirement.required,
      defaultSource: DefaultSource.sessionMachine,
      optionsKey: 'machines',
      group: 'Resource',
    ),
    FieldSchema(
      key: 'operatorName',
      label: 'Operator',
      type: FieldType.select,
      requirement: Requirement.required,
      defaultSource: DefaultSource.sessionUser,
      optionsKey: 'operators',
      group: 'Resource',
    ),
    FieldSchema(
      key: 'startedAt',
      label: 'Start date and time',
      type: FieldType.dateTime,
      requirement: Requirement.required,
      defaultSource: DefaultSource.now,
      group: 'Timing',
    ),
    FieldSchema(
      key: 'completedAt',
      label: 'Completion date and time',
      type: FieldType.dateTime,
      requirement: Requirement.requiredToComplete,
      defaultSource: DefaultSource.now,
      group: 'Timing',
    ),
    FieldSchema(
      key: 'remarks',
      label: 'Remarks',
      type: FieldType.multiline,
      requirement: Requirement.conditional,
      group: 'Notes',
      helper: 'Required when the stage is on hold or needs rework.',
    ),
  ],
);

const _weldingGrinding = StageSchema(
  key: StageKey.weldingGrinding,
  name: 'Welding and Grinding',
  shortName: 'Welding',
  initialStatus: 'Not Started',
  statuses: [
    StatusOption('Not Started'),
    StatusOption('In Process'),
    StatusOption('Completed', terminal: true),
    StatusOption('On Hold'),
    StatusOption('Rework'),
  ],
  note: 'Overall status is derived from both sub-records and cannot be set '
      'directly.',
  fields: [],
  subRecords: [
    StageSubRecord(
      key: 'welding',
      name: 'Welding',
      initialStatus: 'Not Started',
      statuses: _standardStatuses,
      fields: [
        FieldSchema(
          key: 'jobNumber',
          label: 'Job number',
          type: FieldType.text,
          requirement: Requirement.required,
          defaultSource: DefaultSource.orderNumber,
          readOnly: true,
          group: 'Job',
        ),
        FieldSchema(
          key: 'componentName',
          label: 'Component name',
          type: FieldType.text,
          requirement: Requirement.required,
          group: 'Job',
        ),
        FieldSchema(
          key: 'quantity',
          label: 'Quantity',
          type: FieldType.integer,
          requirement: Requirement.required,
          defaultSource: DefaultSource.orderQuantity,
          unit: 'pcs',
          group: 'Job',
        ),
        FieldSchema(
          key: 'welder',
          label: 'Welder',
          type: FieldType.select,
          requirement: Requirement.required,
          defaultSource: DefaultSource.sessionUser,
          optionsKey: 'operators',
          group: 'Resource',
        ),
        FieldSchema(
          key: 'workstation',
          label: 'Machine or workstation',
          type: FieldType.select,
          requirement: Requirement.required,
          defaultSource: DefaultSource.sessionMachine,
          optionsKey: 'machines',
          group: 'Resource',
        ),
        FieldSchema(
          key: 'startDate',
          label: 'Start date',
          type: FieldType.date,
          requirement: Requirement.required,
          defaultSource: DefaultSource.today,
          group: 'Timing',
        ),
        FieldSchema(
          key: 'completionDate',
          label: 'Completion date',
          type: FieldType.date,
          requirement: Requirement.requiredToComplete,
          defaultSource: DefaultSource.today,
          group: 'Timing',
        ),
        FieldSchema(
          key: 'remarks',
          label: 'Remarks',
          type: FieldType.multiline,
          group: 'Notes',
        ),
      ],
    ),
    StageSubRecord(
      key: 'grinding',
      name: 'Grinding',
      initialStatus: 'Not Started',
      statuses: _standardStatuses,
      fields: [
        FieldSchema(
          key: 'quantityReceived',
          label: 'Quantity received from welding',
          type: FieldType.integer,
          requirement: Requirement.required,
          defaultSource: DefaultSource.carriedForward,
          carriedFrom: StageKey.weldingGrinding,
          unit: 'pcs',
          group: 'Quantities',
          helper: 'Defaults to the quantity welding completed.',
        ),
        FieldSchema(
          key: 'quantityCompleted',
          label: 'Quantity completed',
          type: FieldType.integer,
          requirement: Requirement.requiredToComplete,
          unit: 'pcs',
          group: 'Quantities',
        ),
        FieldSchema(
          key: 'operatorName',
          label: 'Operator',
          type: FieldType.select,
          requirement: Requirement.required,
          defaultSource: DefaultSource.sessionUser,
          optionsKey: 'operators',
          group: 'Resource',
        ),
        FieldSchema(
          key: 'startDate',
          label: 'Start date',
          type: FieldType.date,
          requirement: Requirement.required,
          defaultSource: DefaultSource.today,
          group: 'Timing',
        ),
        FieldSchema(
          key: 'completionDate',
          label: 'Completion date',
          type: FieldType.date,
          requirement: Requirement.requiredToComplete,
          defaultSource: DefaultSource.today,
          group: 'Timing',
        ),
        FieldSchema(
          key: 'remarks',
          label: 'Remarks',
          type: FieldType.multiline,
          group: 'Notes',
        ),
      ],
    ),
  ],
);

const _painting = StageSchema(
  key: StageKey.painting,
  name: 'Painting',
  shortName: 'Painting',
  initialStatus: 'Not Started',
  statuses: _standardStatuses,
  fields: [
    FieldSchema(
      key: 'jobNumber',
      label: 'Job number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderNumber,
      readOnly: true,
      group: 'Job',
    ),
    FieldSchema(
      key: 'component',
      label: 'Product or component',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderProduct,
      group: 'Job',
    ),
    FieldSchema(
      key: 'quantity',
      label: 'Quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Job',
    ),
    FieldSchema(
      key: 'paintType',
      label: 'Paint type',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'paintTypes',
      group: 'Paint',
    ),
    FieldSchema(
      key: 'paintColour',
      label: 'Paint colour',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'paintColours',
      group: 'Paint',
    ),
    FieldSchema(
      key: 'paintCode',
      label: 'Paint code',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Paint',
      helper: 'Filled from the selected colour. Edit if the batch differs.',
    ),
    FieldSchema(
      key: 'paintingMethod',
      label: 'Painting method',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'paintingMethods',
      group: 'Paint',
    ),
    FieldSchema(
      key: 'operatorName',
      label: 'Operator',
      type: FieldType.select,
      requirement: Requirement.required,
      defaultSource: DefaultSource.sessionUser,
      optionsKey: 'operators',
      group: 'Resource',
    ),
    FieldSchema(
      key: 'startDate',
      label: 'Start date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.today,
      group: 'Timing',
    ),
    FieldSchema(
      key: 'completionDate',
      label: 'Completion date',
      type: FieldType.date,
      requirement: Requirement.requiredToComplete,
      defaultSource: DefaultSource.today,
      group: 'Timing',
    ),
  ],
);

const _qualityTesting = StageSchema(
  key: StageKey.qualityTesting,
  name: 'Quality Testing',
  shortName: 'Quality',
  initialStatus: 'Not Tested',
  statuses: [
    StatusOption('Not Tested'),
    StatusOption('In Testing'),
    StatusOption('Passed', terminal: true),
    StatusOption('Failed'),
    StatusOption('Re-Test Required'),
  ],
  note: 'A failed or untested mandatory check blocks the order from moving to '
      'Wiring and Assembly.',
  fields: [],
);

const _wiringAssembly = StageSchema(
  key: StageKey.wiringAssembly,
  name: 'Wiring and Assembly',
  shortName: 'Assembly',
  initialStatus: 'Not Started',
  statuses: [
    StatusOption('Not Started'),
    StatusOption('Wiring In Process'),
    StatusOption('Wiring Completed'),
    StatusOption('Assembly In Process'),
    StatusOption('Assembly Completed', terminal: true),
    StatusOption('Rework Required'),
  ],
  note: 'Completed only once wiring and assembly are both finished.',
  fields: [
    FieldSchema(
      key: 'jobNumber',
      label: 'Job number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderNumber,
      readOnly: true,
      group: 'Job',
    ),
    FieldSchema(
      key: 'productName',
      label: 'Product name',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderProduct,
      group: 'Job',
    ),
    FieldSchema(
      key: 'quantity',
      label: 'Quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Job',
    ),
    FieldSchema(
      key: 'wiringStatus',
      label: 'Wiring status',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'workStatuses',
      group: 'Progress',
    ),
    FieldSchema(
      key: 'assemblyStatus',
      label: 'Assembly status',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'workStatuses',
      group: 'Progress',
    ),
    FieldSchema(
      key: 'technicianName',
      label: 'Technician',
      type: FieldType.select,
      requirement: Requirement.required,
      defaultSource: DefaultSource.sessionUser,
      optionsKey: 'operators',
      group: 'Resource',
    ),
    FieldSchema(
      key: 'startedAt',
      label: 'Start date and time',
      type: FieldType.dateTime,
      requirement: Requirement.required,
      defaultSource: DefaultSource.now,
      group: 'Timing',
    ),
    FieldSchema(
      key: 'completedAt',
      label: 'Completion date and time',
      type: FieldType.dateTime,
      requirement: Requirement.requiredToComplete,
      defaultSource: DefaultSource.now,
      group: 'Timing',
    ),
    FieldSchema(
      key: 'componentsUsed',
      label: 'Components used',
      type: FieldType.componentList,
      requirement: Requirement.requiredToComplete,
      optionsKey: 'components',
      group: 'Components',
    ),
    FieldSchema(
      key: 'remarks',
      label: 'Remarks',
      type: FieldType.multiline,
      group: 'Notes',
    ),
  ],
);

const _packingLabelling = StageSchema(
  key: StageKey.packingLabelling,
  name: 'Packing and Labelling',
  shortName: 'Packing',
  initialStatus: 'Not Started',
  statuses: [
    StatusOption('Not Started'),
    StatusOption('Packing In Process'),
    StatusOption('Packing Completed'),
    StatusOption('Labelling In Process'),
    StatusOption('Labelling Completed'),
    StatusOption('Ready for Dispatch', terminal: true),
  ],
  note: 'Label verification must be confirmed before the order can be marked '
      'ready for dispatch.',
  fields: [
    FieldSchema(
      key: 'productName',
      label: 'Product name',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderProduct,
      group: 'Job',
    ),
    FieldSchema(
      key: 'jobNumber',
      label: 'Job number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderNumber,
      readOnly: true,
      group: 'Job',
    ),
    FieldSchema(
      key: 'quantity',
      label: 'Quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Job',
    ),
    FieldSchema(
      key: 'numberOfBoxes',
      label: 'Number of boxes',
      type: FieldType.integer,
      requirement: Requirement.required,
      unit: 'boxes',
      group: 'Packing',
    ),
    FieldSchema(
      key: 'packingType',
      label: 'Packing type',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'packingTypes',
      group: 'Packing',
    ),
    FieldSchema(
      key: 'packedBy',
      label: 'Packed by',
      type: FieldType.select,
      requirement: Requirement.required,
      defaultSource: DefaultSource.sessionUser,
      optionsKey: 'operators',
      group: 'Packing',
    ),
    FieldSchema(
      key: 'packingDate',
      label: 'Packing date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.today,
      group: 'Packing',
    ),
    FieldSchema(
      key: 'labelNumber',
      label: 'Label number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Labelling',
    ),
    FieldSchema(
      key: 'batchNumber',
      label: 'Batch number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Labelling',
    ),
    FieldSchema(
      key: 'serialNumber',
      label: 'Serial number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Labelling',
      helper: 'Checked against serial numbers already recorded.',
    ),
    FieldSchema(
      key: 'labelVerification',
      label: 'Label verification',
      type: FieldType.boolean,
      requirement: Requirement.requiredToComplete,
      group: 'Labelling',
      helper: 'Scan the label or type the number to confirm it matches.',
    ),
  ],
);

const _readyForDispatch = StageSchema(
  key: StageKey.readyForDispatch,
  name: 'Ready for Dispatch',
  shortName: 'Ready',
  initialStatus: 'Not Ready',
  statuses: [
    StatusOption('Not Ready'),
    StatusOption('Ready for Dispatch', terminal: true),
    StatusOption('Dispatch In Process'),
    StatusOption('Dispatched'),
    StatusOption('Not Dispatched'),
  ],
  fields: [
    FieldSchema(
      key: 'jobNumber',
      label: 'Order number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderNumber,
      readOnly: true,
      group: 'Order',
    ),
    FieldSchema(
      key: 'customerName',
      label: 'Customer',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderCustomer,
      readOnly: true,
      group: 'Order',
    ),
    FieldSchema(
      key: 'product',
      label: 'Product',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderProduct,
      readOnly: true,
      group: 'Order',
    ),
    FieldSchema(
      key: 'quantity',
      label: 'Quantity',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Order',
    ),
    FieldSchema(
      key: 'packingCompletedDate',
      label: 'Packing completed date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.packingLabelling,
      readOnly: true,
      group: 'Timing',
    ),
    FieldSchema(
      key: 'readyForDispatchDate',
      label: 'Ready for dispatch date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.today,
      group: 'Timing',
    ),
  ],
);

const _dispatch = StageSchema(
  key: StageKey.dispatch,
  name: 'Dispatch',
  shortName: 'Dispatch',
  initialStatus: 'In Process',
  statuses: [
    StatusOption('In Process'),
    StatusOption('Dispatched', terminal: true),
    StatusOption('Delivered'),
    StatusOption('Not Dispatched'),
  ],
  note: 'Recording Not Dispatched requires a reason before the record can be '
      'saved.',
  fields: [
    FieldSchema(
      key: 'invoiceNumber',
      label: 'Invoice number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Invoice',
    ),
    FieldSchema(
      key: 'invoiceDate',
      label: 'Invoice date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.today,
      group: 'Invoice',
    ),
    FieldSchema(
      key: 'dispatchDate',
      label: 'Dispatch date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.today,
      group: 'Invoice',
    ),
    FieldSchema(
      key: 'customerName',
      label: 'Customer',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderCustomer,
      readOnly: true,
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'deliveryAddress',
      label: 'Delivery address',
      type: FieldType.multiline,
      requirement: Requirement.required,
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'numberOfPackages',
      label: 'Number of packages',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.packingLabelling,
      unit: 'packages',
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'quantityDispatched',
      label: 'Quantity dispatched',
      type: FieldType.integer,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderQuantity,
      unit: 'pcs',
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'vehicleNumber',
      label: 'Vehicle number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Vehicle and driver',
      helper: 'For example TN 38 BQ 4417.',
    ),
    FieldSchema(
      key: 'driverName',
      label: 'Driver name',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Vehicle and driver',
    ),
    FieldSchema(
      key: 'driverContactNumber',
      label: 'Driver contact number',
      type: FieldType.phone,
      requirement: Requirement.required,
      group: 'Vehicle and driver',
    ),
    FieldSchema(
      key: 'transporterName',
      label: 'Transporter',
      type: FieldType.select,
      requirement: Requirement.required,
      optionsKey: 'transporters',
      group: 'Transport',
    ),
    FieldSchema(
      key: 'lrNumber',
      label: 'LR or transport number',
      type: FieldType.text,
      requirement: Requirement.required,
      group: 'Transport',
    ),
  ],
);

const _delivery = StageSchema(
  key: StageKey.delivery,
  name: 'Delivery',
  shortName: 'Delivery',
  initialStatus: 'Dispatched',
  statuses: [
    StatusOption('Dispatched'),
    StatusOption('In Transit'),
    StatusOption('Delivered'),
    StatusOption('Completed', terminal: true),
  ],
  note: 'Marking the order delivered records the actual delivery date and '
      'closes the order.',
  fields: [
    FieldSchema(
      key: 'dispatchDate',
      label: 'Dispatch date',
      type: FieldType.date,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.dispatch,
      readOnly: true,
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'customerName',
      label: 'Customer',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.orderCustomer,
      readOnly: true,
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'vehicleNumber',
      label: 'Vehicle number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.dispatch,
      readOnly: true,
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'invoiceNumber',
      label: 'Invoice number',
      type: FieldType.text,
      requirement: Requirement.required,
      defaultSource: DefaultSource.carriedForward,
      carriedFrom: StageKey.dispatch,
      readOnly: true,
      group: 'Consignment',
    ),
    FieldSchema(
      key: 'expectedDeliveryDate',
      label: 'Expected delivery date',
      type: FieldType.date,
      requirement: Requirement.required,
      group: 'Delivery',
    ),
    FieldSchema(
      key: 'actualDeliveryDate',
      label: 'Actual delivery date',
      type: FieldType.date,
      requirement: Requirement.conditional,
      defaultSource: DefaultSource.today,
      group: 'Delivery',
    ),
    FieldSchema(
      key: 'receivedBy',
      label: 'Received by',
      type: FieldType.text,
      requirement: Requirement.conditional,
      group: 'Delivery',
    ),
    FieldSchema(
      key: 'proofOfDelivery',
      label: 'Proof of delivery',
      type: FieldType.attachment,
      requirement: Requirement.conditional,
      group: 'Delivery',
      helper: 'Photograph of the signed challan, or a signature.',
    ),
    FieldSchema(
      key: 'remarks',
      label: 'Remarks',
      type: FieldType.multiline,
      group: 'Notes',
    ),
  ],
);

/// Every stage, keyed for lookup.
const Map<StageKey, StageSchema> kStageSchemas = {
  StageKey.rawMaterial: _rawMaterial,
  StageKey.laserCutting: _laserCutting,
  StageKey.weldingGrinding: _weldingGrinding,
  StageKey.painting: _painting,
  StageKey.qualityTesting: _qualityTesting,
  StageKey.wiringAssembly: _wiringAssembly,
  StageKey.packingLabelling: _packingLabelling,
  StageKey.readyForDispatch: _readyForDispatch,
  StageKey.dispatch: _dispatch,
  StageKey.delivery: _delivery,
};

StageSchema schemaFor(StageKey key) => kStageSchemas[key]!;

// ---------------------------------------------------------------------------
// Quality checklist
// ---------------------------------------------------------------------------

/// One row of the mandatory quality checklist.
class QualityTestDefinition {
  const QualityTestDefinition({
    required this.key,
    required this.name,
    this.required = true,
  });

  final String key;
  final String name;
  final bool required;
}

/// The five checks the blueprint mandates, in order.
const List<QualityTestDefinition> kQualityTests = [
  QualityTestDefinition(key: 'visual', name: 'Visual Inspection'),
  QualityTestDefinition(key: 'dimension', name: 'Dimension Test'),
  QualityTestDefinition(key: 'electrical', name: 'Electrical Test'),
  QualityTestDefinition(key: 'load', name: 'Load Test'),
  QualityTestDefinition(key: 'insulation', name: 'Insulation Test'),
];

/// Result recorded against a checklist row.
enum TestResult { pending, pass, fail }

/// Lifecycle of a checklist row, distinct from its result.
enum TestStatus {
  notTested('Not Tested'),
  inTesting('In Testing'),
  passed('Passed'),
  failed('Failed'),
  reTestRequired('Re-Test Required');

  const TestStatus(this.label);
  final String label;
}

// ---------------------------------------------------------------------------
// Dispatch exceptions
// ---------------------------------------------------------------------------

/// The reasons the blueprint allows when an order is not dispatched. The list
/// is closed; "Other" additionally requires free text.
enum NotDispatchedReason {
  vehicleNotAvailable('Vehicle Not Available'),
  customerRequestedDelay('Customer Requested Delay'),
  paymentPending('Payment Pending'),
  documentationPending('Documentation Pending'),
  productionDelay('Production Delay'),
  qualityIssue('Quality Issue'),
  materialShortage('Material Shortage'),
  transporterUnavailable('Transporter Unavailable'),
  other('Other');

  const NotDispatchedReason(this.label);
  final String label;

  bool get requiresDetail => this == NotDispatchedReason.other;
}
