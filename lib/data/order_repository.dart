import '../domain/models/models.dart';
import '../domain/stage_schema.dart';

/// How the repository is behaving. The dev panel drives this so every state
/// specified for a screen can actually be produced and reviewed, rather than
/// only described.
enum RepositoryMode {
  normal,
  loading,
  empty,
  error,
  offline,
  partialSync,
  permissionDenied,
}

/// Raised when a read or write cannot complete. Carries copy the UI shows
/// directly, with a recovery path rather than a bare failure.
class RepositoryFailure implements Exception {
  const RepositoryFailure(this.message, {this.canRetry = true});

  final String message;
  final bool canRetry;

  @override
  String toString() => message;
}

/// Raised when the signed-in role may not see or change something.
class PermissionFailure implements Exception {
  const PermissionFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Master data the forms select from, so operators pick rather than type.
class MasterData {
  const MasterData({
    required this.suppliers,
    required this.machines,
    required this.operators,
    required this.paintTypes,
    required this.paintColours,
    required this.paintCodes,
    required this.paintingMethods,
    required this.packingTypes,
    required this.transporters,
    required this.components,
    required this.workStatuses,
    required this.customers,
    required this.products,
  });

  final List<String> suppliers;
  final List<String> machines;
  final List<String> operators;
  final List<String> paintTypes;
  final List<String> paintColours;

  /// Paint code for a colour, so the code field fills itself.
  final Map<String, String> paintCodes;
  final List<String> paintingMethods;
  final List<String> packingTypes;
  final List<String> transporters;
  final List<String> components;
  final List<String> workStatuses;

  /// Known customers and the catalogue of products, so raising a jobsheet is
  /// mostly picking rather than typing.
  final List<String> customers;
  final List<String> products;

  List<String> optionsFor(String key) => switch (key) {
        'suppliers' => suppliers,
        'machines' => machines,
        'operators' => operators,
        'paintTypes' => paintTypes,
        'paintColours' => paintColours,
        'paintingMethods' => paintingMethods,
        'packingTypes' => packingTypes,
        'transporters' => transporters,
        'components' => components,
        'workStatuses' => workStatuses,
        'customers' => customers,
        'products' => products,
        _ => const [],
      };
}

/// A queued local change that has not reached the server.
class PendingWrite {
  const PendingWrite({
    required this.id,
    required this.orderId,
    required this.orderNo,
    required this.stageKey,
    required this.description,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String orderId;
  final String orderNo;
  final StageKey? stageKey;
  final String description;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;

  PendingWrite copyWith({int? attempts, String? lastError}) => PendingWrite(
        id: id,
        orderId: orderId,
        orderNo: orderNo,
        stageKey: stageKey,
        description: description,
        queuedAt: queuedAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );
}

/// What a planner fills in to raise or correct a jobsheet.
///
/// Deliberately small: the identity of the order and what material it needs.
/// Everything else on the order is recorded by the floor as the work happens.
class NewOrderDraft {
  const NewOrderDraft({
    this.orderNo,
    this.customer,
    this.product,
    this.quantity,
    this.priority = Priority.standard,
    this.dueAt,
    this.materialName,
    this.materialCode,
    this.supplier,
    this.purchaseOrderNumber,
    this.notes,
  });

  final String? orderNo;
  final String? customer;
  final String? product;
  final int? quantity;
  final Priority priority;
  final DateTime? dueAt;

  final String? materialName;
  final String? materialCode;
  final String? supplier;
  final String? purchaseOrderNumber;
  final String? notes;

  NewOrderDraft copyWith({
    String? orderNo,
    String? customer,
    String? product,
    int? quantity,
    Priority? priority,
    DateTime? dueAt,
    String? materialName,
    String? materialCode,
    String? supplier,
    String? purchaseOrderNumber,
    String? notes,
  }) =>
      NewOrderDraft(
        orderNo: orderNo ?? this.orderNo,
        customer: customer ?? this.customer,
        product: product ?? this.product,
        quantity: quantity ?? this.quantity,
        priority: priority ?? this.priority,
        dueAt: dueAt ?? this.dueAt,
        materialName: materialName ?? this.materialName,
        materialCode: materialCode ?? this.materialCode,
        supplier: supplier ?? this.supplier,
        purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
        notes: notes ?? this.notes,
      );

  /// Everything still missing, worded so the form can print it under the
  /// control it disabled.
  List<String> get missing => [
        if (_blank(customer)) 'Choose a customer.',
        if (_blank(product)) 'Choose a product.',
        if (quantity == null || quantity! <= 0) 'Enter how many are ordered.',
        if (dueAt == null) 'Choose the date it is due.',
        if (_blank(materialName)) 'Name the material this job needs.',
      ];

  bool get isComplete => missing.isEmpty;

  static bool _blank(String? v) => v == null || v.trim().isEmpty;
}

/// Data access. Screens depend on this interface only, so replacing the
/// in-memory implementation with an HTTP one touches a single file.
abstract interface class OrderRepository {
  /// Current behaviour, including whether the device is offline.
  RepositoryMode get mode;

  /// Emits whenever orders change, so every screen stays consistent.
  ///
  /// Changes only. The current list is not replayed on subscribe, because a
  /// listener that refreshes on each event would otherwise retrigger itself
  /// the moment it subscribed.
  Stream<List<Order>> watchOrders();

  Future<List<Order>> fetchOrders();

  Future<Order> fetchOrder(String id);

  /// Events for one order, newest last.
  Future<List<TimelineEvent>> fetchTimeline(String orderId);

  Future<List<Alert>> fetchAlerts();

  MasterData get masters;

  /// When the cached data was last known to be current. Screens show this
  /// when connectivity is partial so nobody acts on stale numbers.
  DateTime? get lastSyncedAt;

  List<PendingWrite> get pendingWrites;

  /// Saves a stage record. Offline, this queues the change and returns the
  /// optimistically updated order.
  Future<Order> saveStage({
    required String orderId,
    required StageRecord record,
    required User actor,
    String? summary,
  });

  /// Records one quality checklist result, appending to that row's history.
  Future<Order> saveQualityTest({
    required String orderId,
    required String testKey,
    required TestResult result,
    required TestStatus status,
    required User actor,
    String? notes,
  });

  /// Saves the dispatch record, including the reason when the order did not
  /// leave the plant.
  Future<Order> saveDispatch({
    required String orderId,
    required String status,
    required Map<String, Object?> values,
    required User actor,
    NotDispatchedReason? reason,
    String? reasonDetail,
  });

  /// Advances the order to the next stage. Callers check the rules first;
  /// the repository re-checks so the rule cannot be bypassed.
  Future<Order> advanceStage({
    required String orderId,
    required User actor,
    String? overrideReason,
  });

  /// Raises a new jobsheet. The order starts at Raw Material with whatever
  /// the planner already knows, so the floor is not asked to retype it.
  Future<Order> createOrder({
    required NewOrderDraft draft,
    required User actor,
  });

  /// Corrects the identity of an existing jobsheet. Quantities and dates get
  /// revised; the tracking history is not touched.
  Future<Order> updateOrderDetails({
    required String orderId,
    required NewOrderDraft draft,
    required User actor,
  });

  Future<void> acknowledgeAlert(String alertId);

  /// Restores an alert an operator dismissed by mistake.
  Future<void> unacknowledgeAlert(String alertId);

  /// Retries queued writes. Returns the number that succeeded.
  Future<int> flushPendingWrites();

  void discardPendingWrite(String id);
}
