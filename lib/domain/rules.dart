import 'models/models.dart';
import 'stage_schema.dart';

/// Business rules from the source blueprint.
///
/// Rules live here rather than in widgets, and they return a [RuleViolation]
/// carrying the sentence the user should read. The UI prints that sentence
/// underneath the control it disabled, so a blocked user always learns why at
/// the point of blockage instead of by trial and error.

/// Identifiers, so a violation can be traced back to the rule and the rule
/// back to the blueprint.
enum RuleId {
  stageOrder,
  materialShortfall,
  requiredFields,
  qualityGate,
  assemblyBothHalves,
  labelVerification,
  notDispatchedReason,
  deliveryEvidence,
  weldingAndGrinding,
  timestampOrder,
  permission,
}

class RuleViolation {
  const RuleViolation(this.rule, this.message, {this.field});

  final RuleId rule;

  /// A complete sentence naming the cause and the fix. Shown verbatim.
  final String message;

  /// The field the user should be sent to, when one is responsible.
  final String? field;

  @override
  String toString() => message;
}

/// Outcome of a rule check. Empty means the action is allowed.
typedef RuleResult = List<RuleViolation>;

abstract final class Rules {
  // -------------------------------------------------------------------------
  // R-01  Stage order
  // -------------------------------------------------------------------------

  /// A stage cannot begin until the one before it is complete.
  static RuleResult canStartStage(Order order, StageKey stage) {
    final previous = stage.previous;
    if (previous == null) return const [];
    if (order.stage(previous).isComplete) return const [];
    return [
      RuleViolation(
        RuleId.stageOrder,
        '${schemaFor(previous).name} must be completed first.',
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // R-04  Quality gate
  // -------------------------------------------------------------------------

  /// Wiring and Assembly cannot begin while a mandatory check is unpassed.
  /// This is the blueprint's hardest rule and the one the app most needs to
  /// enforce rather than merely display.
  static RuleResult qualityGate(Order order) {
    final blocking = order.blockingTests;
    if (blocking.isEmpty) return const [];

    final failed = [
      for (final t in blocking)
        if (t.status == TestStatus.failed ||
            t.status == TestStatus.reTestRequired)
          t,
    ];

    final next = schemaFor(StageKey.wiringAssembly).name;
    final unrecorded = blocking.length - failed.length;

    final failedPart = failed.length == 1
        ? '${failed.first.name} must pass'
        : '${failed.length} checks must pass';
    final unrecordedPart = unrecorded == 1
        ? '${blocking.firstWhere((t) => !failed.contains(t)).name} has not '
            'been recorded'
        : '$unrecorded checks have not been recorded';

    final String message;
    if (failed.isNotEmpty && unrecorded > 0) {
      message = '$failedPart and $unrecordedPart, before the order can move '
          'to $next.';
    } else if (failed.isNotEmpty) {
      message = '$failedPart before the order can move to $next.';
    } else {
      message = '${unrecordedPart[0].toUpperCase()}${unrecordedPart.substring(1)}'
          ' yet.';
    }

    return [RuleViolation(RuleId.qualityGate, message)];
  }

  // -------------------------------------------------------------------------
  // R-03, R-02, R-05, R-06, R-07, R-08, R-09, R-10  Completion checks
  // -------------------------------------------------------------------------

  /// Whether a stage may be marked complete, and what is missing if not.
  static RuleResult canCompleteStage(
    Order order,
    StageKey stage, {
    // Stages that capture everything in sub-records, such as welding and
    // grinding, have no top-level values.
    Map<String, Object?> values = const {},
    Map<String, SubRecordState> subRecords = const {},
    DateTime? now,
  }) {
    final schema = schemaFor(stage);
    final violations = <RuleViolation>[];
    final clock = now ?? DateTime.now();

    // R-03: required fields, naming the first that is missing.
    for (final field in schema.completionRequiredFields) {
      if (_isEmpty(values[field.key])) {
        violations.add(RuleViolation(
          RuleId.requiredFields,
          'Enter ${field.label.toLowerCase()} to complete this stage.',
          field: field.key,
        ));
      }
    }

    switch (stage) {
      // R-02: material cannot be more than partially received while short.
      case StageKey.rawMaterial:
        final required = _int(values['requiredQuantity']);
        final available = _int(values['availableQuantity']);
        if (required != null && available != null && available < required) {
          violations.add(RuleViolation(
            RuleId.materialShortfall,
            'Only $available of $required received. The stage stays at '
                'Partially Received until the full quantity arrives.',
            field: 'availableQuantity',
          ));
        }

      // R-09: the stage completes only when both activities do.
      case StageKey.weldingGrinding:
        violations.addAll(_weldingAndGrinding(subRecords));

      // R-05: both wiring and assembly must be finished.
      case StageKey.wiringAssembly:
        violations.addAll(_wiringAndAssembly(values));

      // R-06: the label must be verified before the order is ready to go.
      case StageKey.packingLabelling:
        if (values['labelVerification'] != true) {
          violations.add(const RuleViolation(
            RuleId.labelVerification,
            'Verify the label number before marking the order ready for '
                'dispatch.',
            field: 'labelVerification',
          ));
        }

      default:
        break;
    }

    // R-10: a stage cannot finish before it started, or in the future.
    violations.addAll(_timestamps(values, clock));

    return violations;
  }

  static RuleResult _weldingAndGrinding(
    Map<String, SubRecordState> subRecords,
  ) {
    final schema = schemaFor(StageKey.weldingGrinding);
    final outstanding = <String>[];

    for (final sub in schema.subRecords) {
      final state = subRecords[sub.key];
      final done = state != null &&
          sub.statuses
              .firstWhere((s) => s.value == state.status,
                  orElse: () => const StatusOption('Not Started'))
              .terminal;
      if (!done) outstanding.add(sub.name.toLowerCase());
    }

    if (outstanding.isEmpty) return const [];
    return [
      RuleViolation(
        RuleId.weldingAndGrinding,
        'Complete ${_list(outstanding)} before finishing this stage.',
      ),
    ];
  }

  static RuleResult _wiringAndAssembly(Map<String, Object?> values) {
    const done = 'Completed';
    final outstanding = <String>[
      if (values['wiringStatus'] != done) 'wiring',
      if (values['assemblyStatus'] != done) 'assembly',
    ];
    if (outstanding.isEmpty) return const [];
    return [
      RuleViolation(
        RuleId.assemblyBothHalves,
        'Complete ${_list(outstanding)} before finishing this stage.',
        field: outstanding.first == 'wiring' ? 'wiringStatus' : 'assemblyStatus',
      ),
    ];
  }

  static RuleResult _timestamps(Map<String, Object?> values, DateTime now) {
    final violations = <RuleViolation>[];
    const pairs = [
      ('startedAt', 'completedAt', 'Completion date and time'),
      ('startDate', 'completionDate', 'Completion date'),
    ];

    for (final (startKey, endKey, label) in pairs) {
      final start = _date(values[startKey]);
      final end = _date(values[endKey]);
      if (start != null && end != null && end.isBefore(start)) {
        violations.add(RuleViolation(
          RuleId.timestampOrder,
          '$label cannot be earlier than the start.',
          field: endKey,
        ));
      }
      if (end != null && end.isAfter(now)) {
        violations.add(RuleViolation(
          RuleId.timestampOrder,
          '$label cannot be in the future.',
          field: endKey,
        ));
      }
    }
    return violations;
  }

  // -------------------------------------------------------------------------
  // R-07  Dispatch exceptions
  // -------------------------------------------------------------------------

  /// An order recorded as not dispatched must say why.
  static RuleResult canSaveDispatch({
    required String status,
    NotDispatchedReason? reason,
    String? detail,
  }) {
    if (status != 'Not Dispatched') return const [];

    if (reason == null) {
      return const [
        RuleViolation(
          RuleId.notDispatchedReason,
          'Choose why the order was not dispatched.',
          field: 'notDispatchedReason',
        ),
      ];
    }
    if (reason.requiresDetail && _isEmpty(detail)) {
      return const [
        RuleViolation(
          RuleId.notDispatchedReason,
          'Describe the reason the order was not dispatched.',
          field: 'notDispatchedDetail',
        ),
      ];
    }
    return const [];
  }

  // -------------------------------------------------------------------------
  // R-08  Delivery evidence
  // -------------------------------------------------------------------------

  /// Delivery is only recorded with a date, a recipient and proof.
  static RuleResult canMarkDelivered(Map<String, Object?> values) {
    final missing = <RuleViolation>[
      if (_isEmpty(values['actualDeliveryDate']))
        const RuleViolation(
          RuleId.deliveryEvidence,
          'Enter the actual delivery date.',
          field: 'actualDeliveryDate',
        ),
      if (_isEmpty(values['receivedBy']))
        const RuleViolation(
          RuleId.deliveryEvidence,
          'Enter who received the delivery.',
          field: 'receivedBy',
        ),
      if (_isEmpty(values['proofOfDelivery']))
        const RuleViolation(
          RuleId.deliveryEvidence,
          'Attach proof of delivery.',
          field: 'proofOfDelivery',
        ),
    ];
    return missing;
  }

  // -------------------------------------------------------------------------
  // R-12  Permissions
  // -------------------------------------------------------------------------

  /// Whether this user may execute this stage.
  static RuleResult canExecuteStage(User user, Order order, StageKey stage) {
    if (user.isManager) return const [];

    final schema = schemaFor(stage);

    switch (user.role) {
      case Role.qualityInspector:
        if (stage == StageKey.qualityTesting) return const [];
        return [
          RuleViolation(
            RuleId.permission,
            '${schema.name} is updated by the operator at that station.',
          ),
        ];

      case Role.dispatchClerk:
        const allowed = {
          StageKey.readyForDispatch,
          StageKey.dispatch,
          StageKey.delivery,
        };
        if (allowed.contains(stage)) return const [];
        return [
          RuleViolation(
            RuleId.permission,
            'Dispatch can update dispatch and delivery stages only.',
          ),
        ];

      case Role.operator:
        if (stage == StageKey.qualityTesting) {
          return const [
            RuleViolation(
              RuleId.permission,
              'Quality checks are recorded by a quality inspector.',
            ),
          ];
        }
        if (user.station != null && user.station != stage) {
          return [
            RuleViolation(
              RuleId.permission,
              'You are signed in at ${schemaFor(user.station!).name}. Switch '
                  'station to update ${schema.name}.',
            ),
          ];
        }
        return const [];

      case Role.manager:
        return const [];
    }
  }

  /// Editing a finished stage, or cancelling an order, is a manager action
  /// and always carries a reason that is written to the timeline.
  static RuleResult canEditCompletedStage(User user) {
    if (user.isManager) return const [];
    return const [
      RuleViolation(
        RuleId.permission,
        'Only a manager can change a completed stage.',
      ),
    ];
  }

  static RuleResult canOverrideQualityGate(User user) {
    if (user.isManager) return const [];
    return const [
      RuleViolation(
        RuleId.permission,
        'Only a manager can release an order past a failed quality check.',
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Advancement
  // -------------------------------------------------------------------------

  /// Everything standing between the order and its next stage. This is what
  /// the Advance control on Order Detail reads to decide whether it is
  /// enabled, and what sentence to print when it is not.
  static RuleResult canAdvance(Order order, User user, {DateTime? now}) {
    if (order.isCancelled) {
      return const [
        RuleViolation(RuleId.stageOrder, 'This order has been cancelled.'),
      ];
    }
    if (order.isFinished) {
      return const [
        RuleViolation(RuleId.stageOrder, 'This order is already complete.'),
      ];
    }

    final current = order.currentStageKey;
    final violations = <RuleViolation>[
      ...canExecuteStage(user, order, current),
      ...canCompleteStage(
        order,
        current,
        values: order.stage(current).values,
        subRecords: order.stage(current).subRecords,
        now: now,
      ),
    ];

    // The gate applies when the order is about to enter assembly.
    if (current == StageKey.qualityTesting ||
        current.next == StageKey.wiringAssembly) {
      violations.addAll(qualityGate(order));
    }

    return violations;
  }

  /// True when the order is held at the quality gate specifically. Order
  /// Detail uses this to raise a blocker banner rather than a quiet message.
  static bool isBlockedByQuality(Order order) =>
      order.currentStageKey == StageKey.qualityTesting &&
      order.blockingTests.isNotEmpty;

  // -------------------------------------------------------------------------
  // Derivations
  // -------------------------------------------------------------------------

  /// R-09: the welding and grinding stage status follows its two activities
  /// and is never set directly.
  static String deriveWeldingGrindingStatus(
    Map<String, SubRecordState> subRecords,
  ) {
    final schema = schemaFor(StageKey.weldingGrinding);
    final states = [
      for (final sub in schema.subRecords) subRecords[sub.key]?.status,
    ];

    if (states.any((s) => s == 'On Hold')) return 'On Hold';
    if (states.any((s) => s == 'Rework Required')) return 'Rework';
    if (states.every((s) => s == 'Completed')) return 'Completed';
    if (states.any((s) => s != null && s != 'Not Started')) return 'In Process';
    return 'Not Started';
  }

  /// R-05: the assembly stage status follows its two halves.
  static String deriveWiringAssemblyStatus(Map<String, Object?> values) {
    final wiring = values['wiringStatus'] as String?;
    final assembly = values['assemblyStatus'] as String?;

    if (wiring == 'Rework Required' || assembly == 'Rework Required') {
      return 'Rework Required';
    }
    if (assembly == 'Completed') return 'Assembly Completed';
    if (assembly == 'In Process') return 'Assembly In Process';
    if (wiring == 'Completed') return 'Wiring Completed';
    if (wiring == 'In Process') return 'Wiring In Process';
    return 'Not Started';
  }

  /// The blueprint asks for material to be shown as in process or not, rather
  /// than leaving it to be inferred from the status name.
  static bool materialIsInProcess(String status) =>
      status == 'In Process' || status == 'Quality Check Pending';

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static bool _isEmpty(Object? value) =>
      value == null ||
      (value is String && value.trim().isEmpty) ||
      (value is Iterable && value.isEmpty);

  static int? _int(Object? v) => switch (v) {
        int i => i,
        String s => int.tryParse(s),
        _ => null,
      };

  static DateTime? _date(Object? v) => switch (v) {
        DateTime d => d,
        String s => DateTime.tryParse(s),
        _ => null,
      };

  /// Joins a short list into readable prose: "wiring and assembly".
  static String _list(List<String> items) => switch (items.length) {
        0 => '',
        1 => items.first,
        2 => '${items[0]} and ${items[1]}',
        _ =>
          '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
      };
}

/// Convenience for the many places that only need to know whether an action
/// is allowed and, if not, what one sentence to show.
extension RuleResultX on RuleResult {
  bool get allowed => isEmpty;
  bool get blocked => isNotEmpty;

  /// The sentence to print under a disabled control.
  String? get reason => isEmpty ? null : first.message;

  /// The field to focus after a failed submit.
  String? get firstField {
    for (final v in this) {
      if (v.field != null) return v.field;
    }
    return null;
  }
}
