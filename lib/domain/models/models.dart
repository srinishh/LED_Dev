import '../stage_schema.dart';
import '../status_projection.dart';

/// Who is using the app. Role decides what Today shows, which stages can be
/// executed, and which actions are permitted.
enum Role {
  operator('Operator'),
  qualityInspector('Quality Inspector'),
  dispatchClerk('Dispatch Clerk'),
  manager('Manager');

  const Role(this.label);
  final String label;
}

/// How urgently an order needs to move.
enum Priority {
  standard('Standard'),
  high('High'),
  urgent('Urgent');

  const Priority(this.label);
  final String label;
}

/// Whether a local change has reached the server yet.
enum SyncState { synced, pending, conflict, failed }

class User {
  const User({
    required this.id,
    required this.name,
    required this.role,
    this.station,
    this.machine,
  });

  final String id;
  final String name;
  final Role role;

  /// The stage this person works at. Drives the operator work queue.
  final StageKey? station;

  /// Default machine, so the operator does not retype it every job.
  final String? machine;

  bool get isManager => role == Role.manager;
}

/// One stage of one order: its captured values, its status and its history.
class StageRecord {
  const StageRecord({
    required this.stageKey,
    required this.status,
    this.values = const {},
    this.subRecords = const {},
    this.startedAt,
    this.completedAt,
    this.updatedBy,
    this.updatedAt,
    this.syncState = SyncState.synced,
  });

  final StageKey stageKey;
  final String status;

  /// Captured values, keyed by [FieldSchema.key].
  final Map<String, Object?> values;

  /// Values for stages that capture parallel activities, keyed by
  /// [StageSubRecord.key].
  final Map<String, SubRecordState> subRecords;

  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? updatedBy;
  final DateTime? updatedAt;
  final SyncState syncState;

  StageSchema get schema => schemaFor(stageKey);

  StatusFamily get family => StatusProjection.of(stageKey, status);

  bool get isComplete => family == StatusFamily.completed;
  bool get isNotStarted => family == StatusFamily.notStarted;
  bool get needsAttention => StatusProjection.needsAttention(family);

  /// How long this stage has been open, for the operator queue and for the
  /// stage-duration comparison on Order Detail.
  Duration? elapsedAt(DateTime now) {
    final start = startedAt;
    if (start == null) return null;
    return (completedAt ?? now).difference(start);
  }

  StageRecord copyWith({
    String? status,
    Map<String, Object?>? values,
    Map<String, SubRecordState>? subRecords,
    DateTime? startedAt,
    DateTime? completedAt,
    String? updatedBy,
    DateTime? updatedAt,
    SyncState? syncState,
  }) =>
      StageRecord(
        stageKey: stageKey,
        status: status ?? this.status,
        values: values ?? this.values,
        subRecords: subRecords ?? this.subRecords,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        updatedBy: updatedBy ?? this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
        syncState: syncState ?? this.syncState,
      );
}

/// State of one parallel activity inside a stage, such as welding.
class SubRecordState {
  const SubRecordState({
    required this.key,
    required this.status,
    this.values = const {},
  });

  final String key;
  final String status;
  final Map<String, Object?> values;

  SubRecordState copyWith({String? status, Map<String, Object?>? values}) =>
      SubRecordState(
        key: key,
        status: status ?? this.status,
        values: values ?? this.values,
      );
}

/// One row of the mandatory quality checklist, as recorded against an order.
class QualityTestRecord {
  const QualityTestRecord({
    required this.definition,
    this.result = TestResult.pending,
    this.status = TestStatus.notTested,
    this.testedBy,
    this.testedAt,
    this.notes,
    this.attachmentLabel,
    this.history = const [],
  });

  final QualityTestDefinition definition;
  final TestResult result;
  final TestStatus status;
  final String? testedBy;
  final DateTime? testedAt;
  final String? notes;
  final String? attachmentLabel;

  /// Earlier attempts. A re-test appends rather than overwriting, so the
  /// blueprint's question "which tests passed or failed" stays answerable.
  final List<QualityTestAttempt> history;

  String get name => definition.name;
  bool get isRequired => definition.required;

  /// A required check that has not yet passed blocks the order.
  bool get blocksProgress => isRequired && status != TestStatus.passed;

  StatusFamily get family => qualityTestFamily(status);

  QualityTestRecord copyWith({
    TestResult? result,
    TestStatus? status,
    String? testedBy,
    DateTime? testedAt,
    String? notes,
    String? attachmentLabel,
    List<QualityTestAttempt>? history,
  }) =>
      QualityTestRecord(
        definition: definition,
        result: result ?? this.result,
        status: status ?? this.status,
        testedBy: testedBy ?? this.testedBy,
        testedAt: testedAt ?? this.testedAt,
        notes: notes ?? this.notes,
        attachmentLabel: attachmentLabel ?? this.attachmentLabel,
        history: history ?? this.history,
      );
}

class QualityTestAttempt {
  const QualityTestAttempt({
    required this.result,
    required this.testedBy,
    required this.testedAt,
    this.notes,
  });

  final TestResult result;
  final String testedBy;
  final DateTime testedAt;
  final String? notes;
}

/// Logistics captured when the order leaves the plant.
class DispatchRecord {
  const DispatchRecord({
    this.notDispatchedReason,
    this.notDispatchedDetail,
  });

  /// Set only when the dispatch status is Not Dispatched.
  final NotDispatchedReason? notDispatchedReason;

  /// Free text, mandatory when the reason is Other.
  final String? notDispatchedDetail;

  /// The reason as shown to the user, including the detail when present.
  String? get reasonLabel {
    final reason = notDispatchedReason;
    if (reason == null) return null;
    if (reason.requiresDetail && (notDispatchedDetail?.isNotEmpty ?? false)) {
      return notDispatchedDetail;
    }
    return reason.label;
  }
}

/// What happened to an order, and when. Emitted by the domain layer only.
enum TimelineEventType {
  stageStarted,
  stageCompleted,
  statusChanged,
  qualityRecorded,
  blocked,
  overridden,
  fieldEdited,
  acknowledged,
  dispatched,
  delivered,
  orderCreated,
}

enum EventSeverity { normal, warning, critical }

class TimelineEvent {
  const TimelineEvent({
    required this.orderId,
    required this.type,
    required this.actor,
    required this.at,
    required this.summary,
    this.stageKey,
    this.detail,
    this.severity = EventSeverity.normal,
  });

  final String orderId;
  final StageKey? stageKey;
  final TimelineEventType type;
  final String actor;
  final DateTime at;
  final String summary;
  final String? detail;
  final EventSeverity severity;
}

/// The primary object. An order carries one record per stage.
class Order {
  const Order({
    required this.id,
    required this.orderNo,
    required this.customer,
    required this.product,
    required this.quantity,
    required this.priority,
    required this.receivedAt,
    required this.dueAt,
    required this.stages,
    required this.qualityTests,
    this.dispatch = const DispatchRecord(),
    this.isCancelled = false,
    this.notes,
  });

  final String id;
  final String orderNo;
  final String customer;
  final String product;
  final int quantity;
  final Priority priority;
  final DateTime receivedAt;
  final DateTime dueAt;

  final Map<StageKey, StageRecord> stages;
  final List<QualityTestRecord> qualityTests;
  final DispatchRecord dispatch;
  final bool isCancelled;
  final String? notes;

  StageRecord stage(StageKey key) => stages[key]!;

  /// The stage the order is sitting at: the first that is not complete, or
  /// the last stage once everything is done.
  StageKey get currentStageKey {
    for (final key in StageKey.ordered) {
      if (!stage(key).isComplete) return key;
    }
    return StageKey.delivery;
  }

  StageRecord get currentStage => stage(currentStageKey);

  int get completedStageCount =>
      StageKey.ordered.where((k) => stage(k).isComplete).length;

  bool get isFinished => completedStageCount == StageKey.ordered.length;

  double get progress => completedStageCount / StageKey.ordered.length;

  /// Quality checks that have not yet passed. Empty means the gate is open.
  List<QualityTestRecord> get blockingTests =>
      [for (final t in qualityTests) if (t.blocksProgress) t];

  List<QualityTestRecord> get failedTests => [
        for (final t in qualityTests)
          if (t.status == TestStatus.failed ||
              t.status == TestStatus.reTestRequired)
            t,
      ];

  bool get hasQualityFailure => failedTests.isNotEmpty;

  /// Stages currently demanding attention, in production order.
  List<StageRecord> get stagesNeedingAttention =>
      [for (final k in StageKey.ordered) if (stage(k).needsAttention) stage(k)];

  bool get needsAttention =>
      stagesNeedingAttention.isNotEmpty || hasQualityFailure;

  bool isOverdue(DateTime now) => !isFinished && dueAt.isBefore(now);

  int daysUntilDue(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
    return due.difference(today).inDays;
  }

  bool get hasPendingSync =>
      stages.values.any((s) => s.syncState != SyncState.synced);

  Order copyWith({
    Map<StageKey, StageRecord>? stages,
    List<QualityTestRecord>? qualityTests,
    DispatchRecord? dispatch,
    bool? isCancelled,
    String? notes,
  }) =>
      Order(
        id: id,
        orderNo: orderNo,
        customer: customer,
        product: product,
        quantity: quantity,
        priority: priority,
        receivedAt: receivedAt,
        dueAt: dueAt,
        stages: stages ?? this.stages,
        qualityTests: qualityTests ?? this.qualityTests,
        dispatch: dispatch ?? this.dispatch,
        isCancelled: isCancelled ?? this.isCancelled,
        notes: notes ?? this.notes,
      );

  /// Replaces one stage record, leaving the rest untouched.
  Order withStage(StageRecord record) => copyWith(
        stages: {...stages, record.stageKey: record},
      );
}

/// An item on the alerts screen, derived from order state rather than stored.
class Alert {
  const Alert({
    required this.id,
    required this.orderId,
    required this.orderNo,
    required this.title,
    required this.detail,
    required this.severity,
    required this.raisedAt,
    this.stageKey,
    this.acknowledged = false,
  });

  final String id;
  final String orderId;
  final String orderNo;
  final String title;
  final String detail;
  final EventSeverity severity;
  final DateTime raisedAt;
  final StageKey? stageKey;
  final bool acknowledged;

  Alert copyWith({bool? acknowledged}) => Alert(
        id: id,
        orderId: orderId,
        orderNo: orderNo,
        title: title,
        detail: detail,
        severity: severity,
        raisedAt: raisedAt,
        stageKey: stageKey,
        acknowledged: acknowledged ?? this.acknowledged,
      );
}
