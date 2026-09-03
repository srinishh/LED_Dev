import 'stage_schema.dart';

/// Each stage carries its own status vocabulary, but the management dashboard
/// has exactly one five-item legend. This file owns that mapping.
///
/// It is defined once and tested over the full cross-product of stage and
/// status, because an implicit mapping scattered across widgets is the single
/// thing most likely to drift as the app grows.

/// The five families in the dashboard legend.
enum StatusFamily {
  notStarted('Not started'),
  inProcess('In process'),
  completed('Completed'),
  failed('Failed'),
  onHold('On hold');

  const StatusFamily(this.label);

  /// Label used in the legend and in filter chips.
  final String label;
}

abstract final class StatusProjection {
  /// Projects a stage-specific status onto the legend.
  ///
  /// Throws [ArgumentError] for a status the stage does not define, so a typo
  /// fails loudly at the call site rather than silently rendering as
  /// "not started".
  static StatusFamily of(StageKey stage, String status) {
    final schema = schemaFor(stage);
    if (!schema.statusValues.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'is not a status of ${schema.name}',
      );
    }
    return _map(stage, status);
  }

  /// Non-throwing variant for rendering data of uncertain provenance.
  static StatusFamily? tryOf(StageKey stage, String status) =>
      schemaFor(stage).statusValues.contains(status)
          ? _map(stage, status)
          : null;

  static StatusFamily _map(StageKey stage, String status) {
    // Values shared across several stages, handled once.
    switch (status) {
      case 'Not Started':
      case 'Not Received':
      case 'Not Ready':
      case 'Not Tested':
        return StatusFamily.notStarted;

      case 'In Process':
      case 'In Testing':
      case 'In Transit':
      case 'Partially Received':
      case 'Quality Check Pending':
      case 'Dispatch In Process':
      case 'Wiring In Process':
      case 'Assembly In Process':
      case 'Packing In Process':
      case 'Labelling In Process':
        return StatusFamily.inProcess;

      case 'Completed':
      case 'Approved':
      case 'Passed':
        return StatusFamily.completed;

      case 'On Hold':
        return StatusFamily.onHold;

      case 'Rejected':
      case 'Failed':
        return StatusFamily.failed;

      // Rework is unfinished work that must be redone. It reads as a failure
      // on the dashboard because it demands attention, not as a hold.
      case 'Rework':
      case 'Rework Required':
      case 'Re-Test Required':
        return StatusFamily.failed;
    }

    // Values whose meaning depends on which stage they appear in.
    switch ((stage, status)) {
      // Material that has arrived is still work in progress until approved.
      case (StageKey.rawMaterial, 'Received'):
        return StatusFamily.inProcess;

      // Reaching ready-for-dispatch completes packing, and is the terminal
      // state of the readiness stage itself.
      case (StageKey.packingLabelling, 'Ready for Dispatch'):
      case (StageKey.readyForDispatch, 'Ready for Dispatch'):
        return StatusFamily.completed;

      // Wiring finished but assembly outstanding: the stage is still open.
      case (StageKey.wiringAssembly, 'Wiring Completed'):
        return StatusFamily.inProcess;

      case (StageKey.wiringAssembly, 'Assembly Completed'):
        return StatusFamily.completed;

      case (StageKey.packingLabelling, 'Packing Completed'):
      case (StageKey.packingLabelling, 'Labelling Completed'):
        return StatusFamily.inProcess;

      // Dispatched closes the readiness and dispatch stages, but at the
      // delivery stage it means the goods are still on the road.
      case (StageKey.readyForDispatch, 'Dispatched'):
      case (StageKey.dispatch, 'Dispatched'):
        return StatusFamily.completed;
      case (StageKey.delivery, 'Dispatched'):
        return StatusFamily.inProcess;

      // An order held back from dispatch always carries a reason and always
      // needs someone to act.
      case (StageKey.readyForDispatch, 'Not Dispatched'):
      case (StageKey.dispatch, 'Not Dispatched'):
        return StatusFamily.failed;

      case (StageKey.dispatch, 'Delivered'):
        return StatusFamily.completed;
      case (StageKey.delivery, 'Delivered'):
        return StatusFamily.completed;
    }

    throw StateError(
      'No legend family for ${schemaFor(stage).name} status "$status". '
      'Every status in stage_schema.dart must be projected.',
    );
  }

  /// Whether a family should pull the user's attention on the dashboard.
  static bool needsAttention(StatusFamily family) =>
      family == StatusFamily.failed || family == StatusFamily.onHold;
}

/// Projection of a quality checklist row onto the same legend, so the matrix
/// and badges treat quality identically to every other stage.
StatusFamily qualityTestFamily(TestStatus status) => switch (status) {
      TestStatus.notTested => StatusFamily.notStarted,
      TestStatus.inTesting => StatusFamily.inProcess,
      TestStatus.passed => StatusFamily.completed,
      TestStatus.failed => StatusFamily.failed,
      TestStatus.reTestRequired => StatusFamily.failed,
    };
