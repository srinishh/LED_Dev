import 'dart:async';

import '../domain/models/models.dart';
import '../domain/rules.dart';
import '../domain/stage_schema.dart';
import 'order_repository.dart';
import 'seed_data.dart';

/// In-memory repository backed by the seeded order book.
///
/// It exists to make the product reviewable end to end without a server, and
/// to make every specified screen state reachable through [setMode]. Swapping
/// in an HTTP implementation replaces this file alone; no screen imports it.
class MockOrderRepository implements OrderRepository {
  MockOrderRepository({DateTime? now, this.latency = Duration.zero})
      : _clock = now ?? kSeedNow {
    _load();
  }

  final DateTime _clock;

  /// Artificial delay, so skeleton states can be seen rather than assumed.
  Duration latency;

  late List<Order> _orders;
  late Map<String, List<TimelineEvent>> _timelines;
  late List<Alert> _alerts;

  final _controller = StreamController<List<Order>>.broadcast();
  final List<PendingWrite> _pending = [];

  RepositoryMode _mode = RepositoryMode.normal;
  DateTime? _lastSyncedAt;
  var _writeCounter = 0;

  void _load() {
    final seed = buildSeed();
    _orders = [...seed.orders];
    _timelines = {...seed.timelines};
    _alerts = deriveAlerts(_orders, _clock);
    _lastSyncedAt = _clock;
  }

  // ---------------------------------------------------------------------
  // Mode control, used by the dev panel
  // ---------------------------------------------------------------------

  @override
  RepositoryMode get mode => _mode;

  void setMode(RepositoryMode mode) {
    _mode = mode;
    if (mode == RepositoryMode.partialSync) {
      // Data is readable but no longer known to be current.
      _lastSyncedAt = _clock.subtract(const Duration(minutes: 47));
    } else if (mode == RepositoryMode.normal) {
      _lastSyncedAt = DateTime.now();
    }
    _emit();
  }

  /// Returns the seed to its original state, discarding local edits.
  void reset() {
    _pending.clear();
    _mode = RepositoryMode.normal;
    _load();
    _emit();
  }

  bool get isOffline => _mode == RepositoryMode.offline;

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_orders));
  }

  /// Applies the current mode to a read, so every screen exercises the same
  /// failure paths.
  Future<void> _guardRead() async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    switch (_mode) {
      case RepositoryMode.loading:
        // Never completes: the caller stays in its skeleton state.
        await Completer<void>().future;
      case RepositoryMode.error:
        throw const RepositoryFailure(
          'Could not reach the plant server. Check the connection and try '
          'again.',
        );
      case RepositoryMode.permissionDenied:
        throw const PermissionFailure(
          'Your account does not have access to this information. Ask a '
          'supervisor to grant the production role.',
        );
      case RepositoryMode.normal:
      case RepositoryMode.empty:
      case RepositoryMode.offline:
      case RepositoryMode.partialSync:
        return;
    }
  }

  List<Order> get _visibleOrders =>
      _mode == RepositoryMode.empty ? const [] : _orders;

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  @override
  Stream<List<Order>> watchOrders() => _controller.stream;

  @override
  Future<List<Order>> fetchOrders() async {
    await _guardRead();
    return List.unmodifiable(_visibleOrders);
  }

  @override
  Future<Order> fetchOrder(String id) async {
    await _guardRead();
    final order = _orders.where((o) => o.id == id).firstOrNull;
    if (order == null) {
      throw const RepositoryFailure(
        'That order could not be found. It may have been cancelled.',
        canRetry: false,
      );
    }
    return order;
  }

  @override
  Future<List<TimelineEvent>> fetchTimeline(String orderId) async {
    await _guardRead();
    return List.unmodifiable(_timelines[orderId] ?? const <TimelineEvent>[]);
  }

  @override
  Future<List<Alert>> fetchAlerts() async {
    await _guardRead();
    if (_mode == RepositoryMode.empty) return const [];
    return List.unmodifiable(_alerts);
  }

  @override
  MasterData get masters => kMasterData;

  @override
  DateTime? get lastSyncedAt => _lastSyncedAt;

  @override
  List<PendingWrite> get pendingWrites => List.unmodifiable(_pending);

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  Order _orderById(String id) => _orders.firstWhere((o) => o.id == id);

  void _replace(Order updated) {
    final index = _orders.indexWhere((o) => o.id == updated.id);
    _orders[index] = updated;
    _alerts = _mergeAcknowledgements(deriveAlerts(_orders, DateTime.now()));
    _emit();
  }

  /// Keeps acknowledgements across a rebuild of the derived alert list.
  List<Alert> _mergeAcknowledgements(List<Alert> fresh) {
    final acknowledged = {
      for (final a in _alerts)
        if (a.acknowledged) a.id,
    };
    return [
      for (final a in fresh)
        acknowledged.contains(a.id) ? a.copyWith(acknowledged: true) : a,
    ];
  }

  /// Records what happened. The UI never writes a timeline entry itself, so
  /// history cannot disagree with state.
  void _log(TimelineEvent event) {
    final list = _timelines.putIfAbsent(event.orderId, () => []);
    list.add(event);
    list.sort((a, b) => a.at.compareTo(b.at));
  }

  /// Marks a write as queued when the device is offline, so the row can show
  /// a pending badge and the change is not silently lost.
  SyncState _queueIfOffline({
    required Order order,
    required StageKey? stageKey,
    required String description,
  }) {
    if (!isOffline) return SyncState.synced;
    _pending.add(PendingWrite(
      id: 'write-${++_writeCounter}',
      orderId: order.id,
      orderNo: order.orderNo,
      stageKey: stageKey,
      description: description,
      queuedAt: DateTime.now(),
    ));
    return SyncState.pending;
  }

  @override
  Future<Order> saveStage({
    required String orderId,
    required StageRecord record,
    required User actor,
    String? summary,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    if (_mode == RepositoryMode.error) {
      throw const RepositoryFailure(
        'The change could not be saved. Your entry has been kept, so you can '
        'try again.',
      );
    }

    final order = _orderById(orderId);
    final permission = Rules.canExecuteStage(actor, order, record.stageKey);
    if (permission.blocked) {
      throw PermissionFailure(permission.reason!);
    }

    final schema = schemaFor(record.stageKey);
    final now = DateTime.now();
    final previous = order.stage(record.stageKey);

    // Derived statuses are computed here rather than trusted from the caller,
    // so the two-part stages cannot be marked complete by a stale form.
    final status = switch (record.stageKey) {
      StageKey.weldingGrinding =>
        Rules.deriveWeldingGrindingStatus(record.subRecords),
      StageKey.wiringAssembly =>
        Rules.deriveWiringAssemblyStatus(record.values),
      _ => record.status,
    };

    final syncState = _queueIfOffline(
      order: order,
      stageKey: record.stageKey,
      description: summary ?? '${schema.name} updated',
    );

    final saved = record.copyWith(
      status: status,
      updatedBy: actor.name,
      updatedAt: now,
      syncState: syncState,
      startedAt: record.startedAt ?? previous.startedAt,
    );

    final updated = order.withStage(saved);
    _replace(updated);

    if (previous.status != status) {
      _log(TimelineEvent(
        orderId: orderId,
        stageKey: record.stageKey,
        type: saved.isComplete
            ? TimelineEventType.stageCompleted
            : previous.isNotStarted
                ? TimelineEventType.stageStarted
                : TimelineEventType.statusChanged,
        actor: actor.name,
        at: now,
        summary: summary ?? '${schema.name} moved to $status',
        severity: saved.needsAttention
            ? EventSeverity.warning
            : EventSeverity.normal,
      ));
    } else {
      _log(TimelineEvent(
        orderId: orderId,
        stageKey: record.stageKey,
        type: TimelineEventType.fieldEdited,
        actor: actor.name,
        at: now,
        summary: '${schema.name} details updated',
      ));
    }

    return updated;
  }

  @override
  Future<Order> saveQualityTest({
    required String orderId,
    required String testKey,
    required TestResult result,
    required TestStatus status,
    required User actor,
    String? notes,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);

    final order = _orderById(orderId);
    final permission =
        Rules.canExecuteStage(actor, order, StageKey.qualityTesting);
    if (permission.blocked) throw PermissionFailure(permission.reason!);

    final now = DateTime.now();
    final tests = [
      for (final t in order.qualityTests)
        if (t.definition.key != testKey)
          t
        else
          t.copyWith(
            result: result,
            status: status,
            testedBy: actor.name,
            testedAt: now,
            notes: notes,
            // A re-test appends rather than overwriting, so the blueprint's
            // question about which checks passed stays answerable.
            history: [
              ...t.history,
              if (t.testedBy != null && t.testedAt != null)
                QualityTestAttempt(
                  result: t.result,
                  testedBy: t.testedBy!,
                  testedAt: t.testedAt!,
                  notes: t.notes,
                ),
            ],
          ),
    ];

    final test = tests.firstWhere((t) => t.definition.key == testKey);
    var updated = order.copyWith(qualityTests: tests);

    // The stage status follows the checklist as a whole.
    final stageStatus = updated.blockingTests.isEmpty
        ? 'Passed'
        : updated.failedTests.isNotEmpty
            ? 'Failed'
            : 'In Testing';
    updated = updated.withStage(
      updated.stage(StageKey.qualityTesting).copyWith(
            status: stageStatus,
            startedAt:
                updated.stage(StageKey.qualityTesting).startedAt ?? now,
            updatedBy: actor.name,
            updatedAt: now,
            syncState: _queueIfOffline(
              order: order,
              stageKey: StageKey.qualityTesting,
              description: '${test.name} recorded',
            ),
          ),
    );

    _replace(updated);

    _log(TimelineEvent(
      orderId: orderId,
      stageKey: StageKey.qualityTesting,
      type: TimelineEventType.qualityRecorded,
      actor: actor.name,
      at: now,
      summary: '${test.name} ${switch (status) {
        TestStatus.passed => 'passed',
        TestStatus.failed => 'failed',
        _ => status.label.toLowerCase(),
      }}',
      detail: notes,
      severity: status == TestStatus.failed
          ? EventSeverity.critical
          : EventSeverity.normal,
    ));

    if (status == TestStatus.failed) {
      _log(TimelineEvent(
        orderId: orderId,
        stageKey: StageKey.qualityTesting,
        type: TimelineEventType.blocked,
        actor: 'System',
        at: now.add(const Duration(seconds: 1)),
        summary: 'Order held at Quality Testing',
        detail: Rules.qualityGate(updated).reason,
        severity: EventSeverity.critical,
      ));
    }

    return updated;
  }

  @override
  Future<Order> saveDispatch({
    required String orderId,
    required String status,
    required Map<String, Object?> values,
    required User actor,
    NotDispatchedReason? reason,
    String? reasonDetail,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);

    final order = _orderById(orderId);
    final permission =
        Rules.canExecuteStage(actor, order, StageKey.dispatch);
    if (permission.blocked) throw PermissionFailure(permission.reason!);

    // Re-checked here so the rule holds even if a caller skipped it.
    final violation = Rules.canSaveDispatch(
      status: status,
      reason: reason,
      detail: reasonDetail,
    );
    if (violation.blocked) throw RepositoryFailure(violation.reason!);

    final now = DateTime.now();
    var updated = order.copyWith(
      dispatch: DispatchRecord(
        notDispatchedReason: status == 'Not Dispatched' ? reason : null,
        notDispatchedDetail: status == 'Not Dispatched' ? reasonDetail : null,
      ),
    );

    updated = updated.withStage(
      updated.stage(StageKey.dispatch).copyWith(
            status: status,
            values: values,
            startedAt: updated.stage(StageKey.dispatch).startedAt ?? now,
            completedAt: status == 'Dispatched' ? now : null,
            updatedBy: actor.name,
            updatedAt: now,
            syncState: _queueIfOffline(
              order: order,
              stageKey: StageKey.dispatch,
              description: 'Dispatch record saved',
            ),
          ),
    );

    _replace(updated);

    _log(TimelineEvent(
      orderId: orderId,
      stageKey: StageKey.dispatch,
      type: status == 'Dispatched'
          ? TimelineEventType.dispatched
          : TimelineEventType.statusChanged,
      actor: actor.name,
      at: now,
      summary: status == 'Not Dispatched'
          ? 'Not dispatched'
          : 'Dispatch recorded as ${status.toLowerCase()}',
      detail: status == 'Not Dispatched'
          ? updated.dispatch.reasonLabel
          : values['invoiceNumber'] as String?,
      severity: status == 'Not Dispatched'
          ? EventSeverity.warning
          : EventSeverity.normal,
    ));

    return updated;
  }

  @override
  Future<Order> advanceStage({
    required String orderId,
    required User actor,
    String? overrideReason,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);

    final order = _orderById(orderId);
    final blockers = Rules.canAdvance(order, actor, now: DateTime.now());

    // An override is only accepted from a manager, and only with a reason.
    final overriding = overrideReason != null && overrideReason.trim().isNotEmpty;
    if (blockers.blocked && !overriding) {
      throw RepositoryFailure(blockers.reason!, canRetry: false);
    }
    if (overriding && Rules.canOverrideQualityGate(actor).blocked) {
      throw PermissionFailure(Rules.canOverrideQualityGate(actor).reason!);
    }

    final now = DateTime.now();
    final currentKey = order.currentStageKey;
    final schema = schemaFor(currentKey);

    var updated = order.withStage(
      order.stage(currentKey).copyWith(
            status: schema.terminalStatus,
            completedAt: now,
            updatedBy: actor.name,
            updatedAt: now,
            syncState: _queueIfOffline(
              order: order,
              stageKey: currentKey,
              description: '${schema.name} completed',
            ),
          ),
    );

    final nextKey = currentKey.next;
    if (nextKey != null) {
      updated = updated.withStage(
        updated.stage(nextKey).copyWith(
              startedAt: now,
              updatedAt: now,
              updatedBy: actor.name,
            ),
      );
    }

    _replace(updated);

    if (overriding) {
      _log(TimelineEvent(
        orderId: orderId,
        stageKey: currentKey,
        type: TimelineEventType.overridden,
        actor: actor.name,
        at: now,
        summary: 'Released past ${schema.name} by override',
        detail: overrideReason,
        severity: EventSeverity.critical,
      ));
    }

    _log(TimelineEvent(
      orderId: orderId,
      stageKey: currentKey,
      type: TimelineEventType.stageCompleted,
      actor: actor.name,
      at: now,
      summary: '${schema.name} completed',
    ));

    if (nextKey != null) {
      _log(TimelineEvent(
        orderId: orderId,
        stageKey: nextKey,
        type: TimelineEventType.stageStarted,
        actor: actor.name,
        at: now.add(const Duration(seconds: 1)),
        summary: '${schemaFor(nextKey).name} started',
      ));
    }

    return updated;
  }

  // ---------------------------------------------------------------------
  // Jobsheets
  // ---------------------------------------------------------------------

  /// The next order number in the plant's sequence, so the planner does not
  /// have to invent one or risk a duplicate.
  String _nextOrderNo() {
    var highest = 0;
    for (final order in _orders) {
      final digits = order.orderNo.replaceAll(RegExp(r'[^0-9]'), '');
      final value = int.tryParse(digits) ?? 0;
      if (value > highest) highest = value;
    }
    return 'ORD-${(highest + 1).toString().padLeft(4, '0')}';
  }

  @override
  Future<Order> createOrder({
    required NewOrderDraft draft,
    required User actor,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    if (_mode == RepositoryMode.error) {
      throw const RepositoryFailure(
        'The jobsheet could not be saved. Your entry has been kept, so you '
        'can try again.',
      );
    }
    if (!actor.isManager) {
      throw const PermissionFailure(
        'Only a manager can raise a new jobsheet.',
      );
    }
    if (!draft.isComplete) {
      throw RepositoryFailure(draft.missing.first, canRetry: false);
    }

    final now = DateTime.now();
    final orderNo = draft.orderNo?.trim().isNotEmpty ?? false
        ? draft.orderNo!.trim()
        : _nextOrderNo();

    if (_orders.any((o) => o.orderNo == orderNo)) {
      throw RepositoryFailure(
        'Order $orderNo already exists. Choose a different number.',
        canRetry: false,
      );
    }

    // Every stage exists from the outset, so the order can be tracked from
    // the moment it is raised rather than gaining structure as it goes.
    final stages = <StageKey, StageRecord>{
      for (final key in StageKey.ordered)
        key: StageRecord(stageKey: key, status: schemaFor(key).initialStatus),
    };

    // What the planner already knows is written into the material stage, so
    // the floor is not asked to retype it.
    stages[StageKey.rawMaterial] = StageRecord(
      stageKey: StageKey.rawMaterial,
      status: schemaFor(StageKey.rawMaterial).initialStatus,
      values: {
        'materialName': draft.materialName,
        'materialCode': draft.materialCode,
        'requiredQuantity': draft.quantity,
        'availableQuantity': 0,
        'supplier': draft.supplier,
        'purchaseOrderNumber': draft.purchaseOrderNumber,
      },
    );

    final order = Order(
      id: 'order-$orderNo',
      orderNo: orderNo,
      customer: draft.customer!.trim(),
      product: draft.product!.trim(),
      quantity: draft.quantity!,
      priority: draft.priority,
      receivedAt: now,
      dueAt: draft.dueAt!,
      stages: stages,
      qualityTests: [
        for (final definition in kQualityTests)
          QualityTestRecord(definition: definition),
      ],
      notes: draft.notes,
    );

    _orders.add(order);
    _alerts = _mergeAcknowledgements(deriveAlerts(_orders, DateTime.now()));
    _emit();

    _log(TimelineEvent(
      orderId: order.id,
      type: TimelineEventType.orderCreated,
      actor: actor.name,
      at: now,
      summary: 'Jobsheet raised for ${order.customer}',
      detail: '${order.quantity} units of ${order.product}',
    ));

    return order;
  }

  @override
  Future<Order> updateOrderDetails({
    required String orderId,
    required NewOrderDraft draft,
    required User actor,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    if (!actor.isManager) {
      throw const PermissionFailure(
        'Only a manager can change a jobsheet.',
      );
    }
    if (!draft.isComplete) {
      throw RepositoryFailure(draft.missing.first, canRetry: false);
    }

    final existing = _orderById(orderId);
    final now = DateTime.now();

    // The material stage keeps whatever the floor has already recorded; only
    // the planner's own fields are revised.
    final material = existing.stage(StageKey.rawMaterial);
    final updated = Order(
      id: existing.id,
      orderNo: existing.orderNo,
      customer: draft.customer!.trim(),
      product: draft.product!.trim(),
      quantity: draft.quantity!,
      priority: draft.priority,
      receivedAt: existing.receivedAt,
      dueAt: draft.dueAt!,
      isCancelled: existing.isCancelled,
      notes: draft.notes,
      dispatch: existing.dispatch,
      qualityTests: existing.qualityTests,
      stages: {
        ...existing.stages,
        StageKey.rawMaterial: material.copyWith(
          values: {
            ...material.values,
            'materialName': draft.materialName,
            'materialCode': draft.materialCode,
            'requiredQuantity': draft.quantity,
            'supplier': draft.supplier,
            'purchaseOrderNumber': draft.purchaseOrderNumber,
          },
          updatedBy: actor.name,
          updatedAt: now,
        ),
      },
    );

    _replace(updated);

    // Changes to a live jobsheet are recorded, because the floor may already
    // be working to the old numbers.
    final changes = <String>[
      if (existing.quantity != updated.quantity)
        'quantity ${existing.quantity} to ${updated.quantity}',
      if (!existing.dueAt.isAtSameMomentAs(updated.dueAt)) 'due date',
      if (existing.customer != updated.customer) 'customer',
      if (existing.product != updated.product) 'product',
      if (existing.priority != updated.priority)
        'priority to ${updated.priority.label.toLowerCase()}',
    ];

    if (changes.isNotEmpty) {
      _log(TimelineEvent(
        orderId: orderId,
        type: TimelineEventType.fieldEdited,
        actor: actor.name,
        at: now,
        summary: 'Jobsheet revised',
        detail: 'Changed ${changes.join(', ')}.',
        severity: EventSeverity.warning,
      ));
    }

    return updated;
  }

  // ---------------------------------------------------------------------
  // Alerts
  // ---------------------------------------------------------------------

  @override
  Future<void> acknowledgeAlert(String alertId) async {
    _setAcknowledged(alertId, true);
  }

  @override
  Future<void> unacknowledgeAlert(String alertId) async {
    _setAcknowledged(alertId, false);
  }

  void _setAcknowledged(String alertId, bool value) {
    _alerts = [
      for (final a in _alerts)
        a.id == alertId ? a.copyWith(acknowledged: value) : a,
    ];
    _emit();
  }

  // ---------------------------------------------------------------------
  // Sync queue
  // ---------------------------------------------------------------------

  @override
  Future<int> flushPendingWrites() async {
    if (isOffline) return 0;
    final count = _pending.length;
    _pending.clear();

    _orders = [
      for (final order in _orders)
        order.copyWith(
          stages: {
            for (final entry in order.stages.entries)
              entry.key: entry.value.syncState == SyncState.pending
                  ? entry.value.copyWith(syncState: SyncState.synced)
                  : entry.value,
          },
        ),
    ];
    _lastSyncedAt = DateTime.now();
    _emit();
    return count;
  }

  @override
  void discardPendingWrite(String id) {
    _pending.removeWhere((w) => w.id == id);
    _emit();
  }

  void dispose() => _controller.close();
}
