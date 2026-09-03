import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_repository.dart';
import '../data/order_repository.dart';
import '../design/tokens.dart';
import '../domain/models/models.dart';
import '../domain/rules.dart';
import '../domain/stage_schema.dart';
import '../domain/status_projection.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final repositoryProvider = Provider<MockOrderRepository>((ref) {
  final repo = MockOrderRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Bumped whenever the repository changes in a way the derived providers must
/// notice, such as a mode switch from the dev panel.
class RepositoryRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final repositoryRevisionProvider =
    NotifierProvider<RepositoryRevision, int>(RepositoryRevision.new);

/// The order book. Every screen reads this rather than fetching its own copy,
/// so the whole app agrees on state at all times.
final ordersProvider = FutureProvider<List<Order>>((ref) async {
  ref.watch(repositoryRevisionProvider);
  final repo = ref.watch(repositoryProvider);
  final orders = await repo.fetchOrders();
  // Keep the list live as writes land.
  final sub = repo.watchOrders().listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return orders;
});

final orderProvider = Provider.family<Order?, String>((ref, id) {
  final orders = ref.watch(ordersProvider).value;
  if (orders == null) return null;
  for (final order in orders) {
    if (order.id == id) return order;
  }
  return null;
});

final timelineProvider =
    FutureProvider.family<List<TimelineEvent>, String>((ref, id) async {
  ref.watch(repositoryRevisionProvider);
  ref.watch(ordersProvider);
  return ref.watch(repositoryProvider).fetchTimeline(id);
});

final alertsProvider = FutureProvider<List<Alert>>((ref) async {
  ref.watch(repositoryRevisionProvider);
  ref.watch(ordersProvider);
  return ref.watch(repositoryProvider).fetchAlerts();
});

final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(alertsProvider).value ?? const [];
  return alerts.where((a) => !a.acknowledged).length;
});

final pendingWritesProvider = Provider<List<PendingWrite>>((ref) {
  ref.watch(repositoryRevisionProvider);
  ref.watch(ordersProvider);
  return ref.watch(repositoryProvider).pendingWrites;
});

/// Connectivity as the UI sees it: offline, stale, or current.
final connectivityProvider = Provider<Connectivity>((ref) {
  ref.watch(repositoryRevisionProvider);
  final repo = ref.watch(repositoryProvider);
  final synced = repo.lastSyncedAt;
  return Connectivity(
    offline: repo.mode == RepositoryMode.offline,
    stale: repo.mode == RepositoryMode.partialSync && synced != null
        ? DateTime.now().difference(synced)
        : null,
    queued: repo.pendingWrites.length,
  );
});

class Connectivity {
  const Connectivity({
    required this.offline,
    required this.queued,
    this.stale,
  });

  final bool offline;
  final int queued;

  /// How long ago the data was last known to be current.
  final Duration? stale;

  bool get isDegraded => offline || stale != null;
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// Who is signed in, and where. Switching role or station recomposes Today
/// and changes which actions are offered.
class Session {
  const Session({
    required this.user,
    required this.plant,
    required this.shift,
    required this.shiftHours,
  });

  final User user;
  final String plant;

  /// Short enough to sit on one line beside the plant.
  final String shift;

  /// Spelled out where there is room for it.
  final String shiftHours;

  Session copyWith({User? user}) => Session(
        user: user ?? this.user,
        plant: plant,
        shift: shift,
        shiftHours: shiftHours,
      );
}

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => const Session(
        user: User(
          id: 'u-102',
          name: 'Ramanathan Selvaraj',
          role: Role.operator,
          station: StageKey.laserCutting,
          machine: 'LC-02 Amada LCG',
        ),
        plant: 'Plant A',
        shift: 'Morning shift',
        shiftHours: '06:00 to 14:00',
      );

  static const _people = {
    Role.operator: ('u-102', 'Ramanathan Selvaraj'),
    Role.qualityInspector: ('u-118', 'Farhan Qureshi'),
    Role.dispatchClerk: ('u-131', 'Meenakshi Balan'),
    Role.manager: ('u-004', 'Devika Ranganathan'),
  };

  void switchRole(Role role) {
    final (id, name) = _people[role]!;
    state = state.copyWith(
      user: User(
        id: id,
        name: name,
        role: role,
        station: role == Role.operator ? state.user.station : null,
        machine: role == Role.operator ? state.user.machine : null,
      ),
    );
  }

  void switchStation(StageKey station) {
    state = state.copyWith(
      user: User(
        id: state.user.id,
        name: state.user.name,
        role: state.user.role,
        station: station,
        machine: state.user.machine,
      ),
    );
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

final currentUserProvider =
    Provider<User>((ref) => ref.watch(sessionProvider).user);

// ---------------------------------------------------------------------------
// Presentation preferences
// ---------------------------------------------------------------------------

class DensityNotifier extends Notifier<Density> {
  @override
  Density build() => Density.comfortable;

  void set(Density value) => state = value;
}

final densityProvider =
    NotifierProvider<DensityNotifier, Density>(DensityNotifier.new);

class BrightnessNotifier extends Notifier<Brightness> {
  @override
  Brightness build() => Brightness.light;

  void set(Brightness value) => state = value;
}

final themeModeProvider =
    NotifierProvider<BrightnessNotifier, Brightness>(BrightnessNotifier.new);

// ---------------------------------------------------------------------------
// Filtering and sorting
// ---------------------------------------------------------------------------

enum OrderSort {
  dueDate('Due date'),
  orderNumber('Order number'),
  timeInStage('Time in stage'),
  priority('Priority'),
  lastUpdated('Last updated');

  const OrderSort(this.label);
  final String label;
}

/// The full filter state for the order book. Held in one object so that
/// clearing everything is a single operation and the active-filter chips can
/// be derived rather than tracked separately.
@immutable
class OrderFilter {
  const OrderFilter({
    this.query = '',
    this.families = const {},
    this.stages = const {},
    this.customers = const {},
    this.priorities = const {},
    this.onlyQualityFailures = false,
    this.onlyOverdue = false,
    this.onlyNotDispatched = false,
    this.sort = OrderSort.dueDate,
  });

  final String query;
  final Set<StatusFamily> families;
  final Set<StageKey> stages;
  final Set<String> customers;
  final Set<Priority> priorities;
  final bool onlyQualityFailures;
  final bool onlyOverdue;
  final bool onlyNotDispatched;
  final OrderSort sort;

  bool get isEmpty =>
      query.isEmpty &&
      families.isEmpty &&
      stages.isEmpty &&
      customers.isEmpty &&
      priorities.isEmpty &&
      !onlyQualityFailures &&
      !onlyOverdue &&
      !onlyNotDispatched;

  /// Number of active constraints, shown on the Filters button so the user
  /// knows the list is narrowed even when the chips scroll out of view.
  int get activeCount =>
      (query.isEmpty ? 0 : 1) +
      families.length +
      stages.length +
      customers.length +
      priorities.length +
      (onlyQualityFailures ? 1 : 0) +
      (onlyOverdue ? 1 : 0) +
      (onlyNotDispatched ? 1 : 0);

  OrderFilter copyWith({
    String? query,
    Set<StatusFamily>? families,
    Set<StageKey>? stages,
    Set<String>? customers,
    Set<Priority>? priorities,
    bool? onlyQualityFailures,
    bool? onlyOverdue,
    bool? onlyNotDispatched,
    OrderSort? sort,
  }) =>
      OrderFilter(
        query: query ?? this.query,
        families: families ?? this.families,
        stages: stages ?? this.stages,
        customers: customers ?? this.customers,
        priorities: priorities ?? this.priorities,
        onlyQualityFailures: onlyQualityFailures ?? this.onlyQualityFailures,
        onlyOverdue: onlyOverdue ?? this.onlyOverdue,
        onlyNotDispatched: onlyNotDispatched ?? this.onlyNotDispatched,
        sort: sort ?? this.sort,
      );

  /// Clears the constraints but keeps the chosen sort, which is a preference
  /// rather than a filter.
  OrderFilter cleared() => OrderFilter(sort: sort);

  bool matches(Order order, DateTime now) {
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final haystack = '${order.orderNo} ${order.customer} ${order.product}'
          .toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    if (families.isNotEmpty &&
        !families.contains(order.currentStage.family)) {
      return false;
    }
    if (stages.isNotEmpty && !stages.contains(order.currentStageKey)) {
      return false;
    }
    if (customers.isNotEmpty && !customers.contains(order.customer)) {
      return false;
    }
    if (priorities.isNotEmpty && !priorities.contains(order.priority)) {
      return false;
    }
    if (onlyQualityFailures && !order.hasQualityFailure) return false;
    if (onlyOverdue && !order.isOverdue(now)) return false;
    if (onlyNotDispatched && order.dispatch.notDispatchedReason == null) {
      return false;
    }
    return true;
  }
}

class OrderFilterNotifier extends Notifier<OrderFilter> {
  @override
  OrderFilter build() => const OrderFilter();

  void set(OrderFilter value) => state = value;

  /// Clears every constraint while keeping the chosen sort.
  void clear() => state = state.cleared();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setSort(OrderSort sort) => state = state.copyWith(sort: sort);

  /// Narrows the list to one exception group, used by the dashboard banners.
  void showOnly({
    bool quality = false,
    bool overdue = false,
    bool notDispatched = false,
    Set<StatusFamily> families = const {},
  }) {
    state = OrderFilter(
      sort: state.sort,
      onlyQualityFailures: quality,
      onlyOverdue: overdue,
      onlyNotDispatched: notDispatched,
      families: families,
    );
  }
}

final orderFilterProvider =
    NotifierProvider<OrderFilterNotifier, OrderFilter>(
        OrderFilterNotifier.new);

/// Orders after filtering and sorting. The count shown on the Apply button in
/// the filter sheet comes from the same function, so the preview cannot
/// disagree with the result.
final filteredOrdersProvider = Provider<List<Order>>((ref) {
  final orders = ref.watch(ordersProvider).value ?? const [];
  final filter = ref.watch(orderFilterProvider);
  return applyFilter(orders, filter);
});

List<Order> applyFilter(List<Order> orders, OrderFilter filter) {
  final now = DateTime.now();
  final result = [
    for (final order in orders)
      if (filter.matches(order, now)) order,
  ];

  result.sort((a, b) => switch (filter.sort) {
        OrderSort.dueDate => a.dueAt.compareTo(b.dueAt),
        OrderSort.orderNumber => a.orderNo.compareTo(b.orderNo),
        OrderSort.priority =>
          b.priority.index.compareTo(a.priority.index),
        OrderSort.timeInStage => _stageAge(b, now).compareTo(_stageAge(a, now)),
        OrderSort.lastUpdated => (b.currentStage.updatedAt ?? b.receivedAt)
            .compareTo(a.currentStage.updatedAt ?? a.receivedAt),
      });
  return result;
}

Duration _stageAge(Order order, DateTime now) =>
    order.currentStage.elapsedAt(now) ?? Duration.zero;

// ---------------------------------------------------------------------------
// Dashboard derivations
// ---------------------------------------------------------------------------

/// The exception groups that lead the manager's home screen.
class ExceptionSummary {
  const ExceptionSummary({
    required this.qualityFailed,
    required this.onHold,
    required this.rework,
    required this.overdue,
    required this.notDispatched,
    required this.notDispatchedReason,
  });

  final List<Order> qualityFailed;
  final List<Order> onHold;
  final List<Order> rework;
  final List<Order> overdue;
  final List<Order> notDispatched;

  /// The most common reason among held-back orders, shown so the manager sees
  /// the cause without opening the list.
  final String? notDispatchedReason;

  int get total =>
      qualityFailed.length +
      onHold.length +
      rework.length +
      overdue.length +
      notDispatched.length;

  bool get isEmpty => total == 0;
}

final exceptionsProvider = Provider<ExceptionSummary>((ref) {
  final orders = ref.watch(ordersProvider).value ?? const [];
  final now = DateTime.now();

  final quality = <Order>[];
  final onHold = <Order>[];
  final rework = <Order>[];
  final overdue = <Order>[];
  final notDispatched = <Order>[];

  for (final order in orders) {
    if (order.hasQualityFailure) quality.add(order);
    if (order.isOverdue(now)) overdue.add(order);
    if (order.dispatch.notDispatchedReason != null) notDispatched.add(order);

    for (final stage in order.stagesNeedingAttention) {
      if (stage.status == 'On Hold') {
        onHold.add(order);
        break;
      }
      if (stage.status == 'Rework' || stage.status == 'Rework Required') {
        rework.add(order);
        break;
      }
    }
  }

  return ExceptionSummary(
    qualityFailed: quality,
    onHold: onHold,
    rework: rework,
    overdue: overdue,
    notDispatched: notDispatched,
    notDispatchedReason:
        notDispatched.isEmpty ? null : notDispatched.first.dispatch.reasonLabel,
  );
});

/// Work in progress at each stage, for the pipeline board and the manager
/// chart.
class StageLoad {
  const StageLoad({
    required this.stage,
    required this.wip,
    required this.needingAttention,
    required this.oldest,
  });

  final StageKey stage;
  final int wip;
  final int needingAttention;
  final Duration? oldest;
}

final stageLoadProvider = Provider<List<StageLoad>>((ref) {
  final orders = ref.watch(ordersProvider).value ?? const [];
  final now = DateTime.now();

  return [
    for (final stage in StageKey.ordered)
      () {
        final here = [
          for (final o in orders)
            if (o.currentStageKey == stage && !o.isFinished) o,
        ];
        final flagged = [
          for (final o in here)
            if (o.needsAttention) o,
        ];
        Duration? oldest;
        for (final o in here) {
          final age = o.currentStage.elapsedAt(now);
          if (age != null && (oldest == null || age > oldest)) oldest = age;
        }
        return StageLoad(
          stage: stage,
          wip: here.length,
          needingAttention: flagged.length,
          oldest: oldest,
        );
      }(),
  ];
});

/// The operator's queue: jobs waiting at their station, most urgent first.
final stationQueueProvider = Provider<StationQueue>((ref) {
  final orders = ref.watch(ordersProvider).value ?? const [];
  final user = ref.watch(currentUserProvider);
  final station = user.station;
  final now = DateTime.now();

  if (station == null) {
    return const StationQueue(active: [], onHold: [], rework: [], completed: 0);
  }

  final active = <Order>[];
  final onHold = <Order>[];
  final rework = <Order>[];
  var completed = 0;

  for (final order in orders) {
    final record = order.stage(station);
    if (record.isComplete) {
      // Counted towards the shift total when finished recently.
      if (record.completedAt != null &&
          now.difference(record.completedAt!).inHours < 24) {
        completed++;
      }
      continue;
    }
    if (order.currentStageKey != station) continue;

    switch (record.status) {
      case 'On Hold':
        onHold.add(order);
      case 'Rework':
      case 'Rework Required':
        rework.add(order);
      default:
        active.add(order);
    }
  }

  int urgency(Order o) =>
      (o.isOverdue(now) ? 0 : 1) * 10 - o.priority.index;
  active.sort((a, b) {
    final byUrgency = urgency(a).compareTo(urgency(b));
    if (byUrgency != 0) return byUrgency;
    return a.dueAt.compareTo(b.dueAt);
  });

  return StationQueue(
    active: active,
    onHold: onHold,
    rework: rework,
    completed: completed,
  );
});

class StationQueue {
  const StationQueue({
    required this.active,
    required this.onHold,
    required this.rework,
    required this.completed,
  });

  final List<Order> active;
  final List<Order> onHold;
  final List<Order> rework;

  /// Jobs this station finished in the last day, for the shift figure.
  final int completed;

  int get target => active.length + completed + onHold.length + rework.length;
  bool get isEmpty => active.isEmpty && onHold.isEmpty && rework.isEmpty;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Writes go through here so that every screen gets the same permission
/// checks, the same timeline logging and the same refresh behaviour.
class OrderActions {
  OrderActions(this._ref);

  final Ref _ref;

  MockOrderRepository get _repo => _ref.read(repositoryProvider);
  User get _actor => _ref.read(currentUserProvider);

  void _refresh() => _ref.read(repositoryRevisionProvider.notifier).bump();

  Future<Order> saveStage(String orderId, StageRecord record,
      {String? summary}) async {
    final result = await _repo.saveStage(
      orderId: orderId,
      record: record,
      actor: _actor,
      summary: summary,
    );
    _refresh();
    return result;
  }

  Future<Order> recordQualityTest({
    required String orderId,
    required String testKey,
    required TestResult result,
    required TestStatus status,
    String? notes,
  }) async {
    final order = await _repo.saveQualityTest(
      orderId: orderId,
      testKey: testKey,
      result: result,
      status: status,
      actor: _actor,
      notes: notes,
    );
    _refresh();
    return order;
  }

  Future<Order> saveDispatch({
    required String orderId,
    required String status,
    required Map<String, Object?> values,
    NotDispatchedReason? reason,
    String? reasonDetail,
  }) async {
    final order = await _repo.saveDispatch(
      orderId: orderId,
      status: status,
      values: values,
      actor: _actor,
      reason: reason,
      reasonDetail: reasonDetail,
    );
    _refresh();
    return order;
  }

  Future<Order> advance(String orderId, {String? overrideReason}) async {
    final order = await _repo.advanceStage(
      orderId: orderId,
      actor: _actor,
      overrideReason: overrideReason,
    );
    _refresh();
    return order;
  }

  Future<Order> createOrder(NewOrderDraft draft) async {
    final order = await _repo.createOrder(draft: draft, actor: _actor);
    _refresh();
    return order;
  }

  Future<Order> updateOrderDetails(String orderId, NewOrderDraft draft) async {
    final order = await _repo.updateOrderDetails(
      orderId: orderId,
      draft: draft,
      actor: _actor,
    );
    _refresh();
    return order;
  }

  Future<void> acknowledgeAlert(String id) async {
    await _repo.acknowledgeAlert(id);
    _refresh();
  }

  Future<void> undoAcknowledge(String id) async {
    await _repo.unacknowledgeAlert(id);
    _refresh();
  }

  Future<int> retryQueuedWrites() async {
    final count = await _repo.flushPendingWrites();
    _refresh();
    return count;
  }

  void discardQueuedWrite(String id) {
    _repo.discardPendingWrite(id);
    _refresh();
  }

  void setMode(RepositoryMode mode) {
    _repo.setMode(mode);
    _refresh();
  }

  void setLatency(Duration latency) {
    _repo.latency = latency;
    _refresh();
  }

  void resetData() {
    _repo.reset();
    _refresh();
  }
}

final orderActionsProvider = Provider<OrderActions>(OrderActions.new);

/// Everything blocking the current order from advancing, so the button and
/// the banner always read from the same source.
final advanceBlockersProvider =
    Provider.family<RuleResult, String>((ref, orderId) {
  final order = ref.watch(orderProvider(orderId));
  final user = ref.watch(currentUserProvider);
  if (order == null) return const [];
  return Rules.canAdvance(order, user);
});

/// Seven-day series used by the dashboard figures. Derived from the order
/// book rather than invented, so the trend matches the data on screen.
List<double> weeklySeries(List<Order> orders, bool Function(Order, DateTime) test) {
  final now = DateTime.now();
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final day = now.subtract(Duration(days: i));
        return orders.where((o) => test(o, day)).length.toDouble();
      }(),
  ];
}
