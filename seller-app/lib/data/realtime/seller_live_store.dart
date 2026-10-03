import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';
import '../../domain/models/models.dart';
import '../repositories/seller_repository.dart';

/// LiveDrop Seller App — app-level live session store (SA-RT-001).
///
/// While a seller is signed in, one Realtime channel listens to
/// `postgres_changes` on `orders`, `payment_attempts` and `products`.
/// Bursts of events are debounced into a single [SellerLiveStore.revision]
/// bump; Home, Products, Orders and Payments reload when the revision changes.
/// The store also keeps the counts the shell shows as badges (pending payment
/// claims, overdue claims, refunds owed).
///
/// Realtime is only a latency optimisation (docs/14-realtime-contract.md):
/// after a reconnect or when the app resumes the store "catches up" by
/// bumping the revision and refetching counts from PostgREST, and while the
/// channel is down it polls at [SellerLiveStore.reconnectInterval].

enum SellerLiveChange { insert, update, delete }

/// One row change delivered by a [SellerLiveEventSource].
class SellerLiveEvent {
  final String table;
  final SellerLiveChange change;
  final Map<String, dynamic> newRecord;
  final Map<String, dynamic> oldRecord;

  const SellerLiveEvent({
    required this.table,
    required this.change,
    this.newRecord = const {},
    this.oldRecord = const {},
  });

  /// Drop the row belongs to (orders / products), when the payload carries it.
  String? get dropId {
    final value = newRecord['drop_id'] ?? oldRecord['drop_id'];
    return value is String ? value : null;
  }
}

/// Transport-level channel status (mirrors Supabase's RealtimeSubscribeStatus).
enum SellerLiveTransportStatus { subscribed, error, closed, timedOut }

typedef SellerLiveEventHandler = void Function(SellerLiveEvent event);
typedef SellerLiveStatusHandler = void Function(
  SellerLiveTransportStatus status,
  Object? error,
);

/// Realtime transport behind a small interface so tests can inject a fake.
abstract class SellerLiveEventSource {
  /// Opens (or re-opens) the subscription. Calling it again replaces the
  /// previous subscription.
  void open({
    required SellerLiveEventHandler onEvent,
    required SellerLiveStatusHandler onStatus,
  });

  /// Closes the subscription and releases the channel.
  Future<void> close();
}

/// Production transport: a single Supabase Realtime channel with three
/// `postgres_changes` bindings. RLS limits rows to the seller; the store
/// additionally filters orders/products by the seller's drop ids.
class SupabaseSellerLiveEventSource implements SellerLiveEventSource {
  SupabaseSellerLiveEventSource(this._client);

  static const List<String> tables = ['orders', 'payment_attempts', 'products'];

  final SupabaseClient _client;
  RealtimeChannel? _channel;
  int _sequence = 0;

  @override
  void open({
    required SellerLiveEventHandler onEvent,
    required SellerLiveStatusHandler onStatus,
  }) {
    _removeCurrentChannel();

    final sellerId = _client.auth.currentUser?.id ?? 'anonymous';
    final channel = _client.channel('seller:$sellerId:live:${++_sequence}');
    for (final table in tables) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) {
          onEvent(
            SellerLiveEvent(
              table: payload.table,
              change: _mapChange(payload.eventType),
              newRecord: payload.newRecord,
              oldRecord: payload.oldRecord,
            ),
          );
        },
      );
    }
    channel.subscribe((status, error) => onStatus(_mapStatus(status), error));
    _channel = channel;
  }

  @override
  Future<void> close() async {
    _removeCurrentChannel();
  }

  void _removeCurrentChannel() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(
        _client.removeChannel(channel).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  static SellerLiveChange _mapChange(PostgresChangeEvent event) {
    switch (event) {
      case PostgresChangeEvent.insert:
        return SellerLiveChange.insert;
      case PostgresChangeEvent.delete:
        return SellerLiveChange.delete;
      case PostgresChangeEvent.update:
      case PostgresChangeEvent.all:
        return SellerLiveChange.update;
    }
  }

  static SellerLiveTransportStatus _mapStatus(RealtimeSubscribeStatus status) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        return SellerLiveTransportStatus.subscribed;
      case RealtimeSubscribeStatus.channelError:
        return SellerLiveTransportStatus.error;
      case RealtimeSubscribeStatus.closed:
        return SellerLiveTransportStatus.closed;
      case RealtimeSubscribeStatus.timedOut:
        return SellerLiveTransportStatus.timedOut;
    }
  }
}

enum SellerLiveStatus {
  /// [SellerLiveStore.start] not called yet.
  idle,

  /// Waiting for the first subscription.
  connecting,

  /// Channel subscribed; changes arrive in real time.
  live,

  /// Channel dropped; reconnecting and polling meanwhile.
  reconnecting,

  /// No realtime transport (e.g. Supabase not configured, widget tests).
  unavailable,
}

/// Counts shown as badges / alerts across the app.
class SellerLiveCounts {
  final int pendingVerifications;
  final int refundsOwed;
  final int refundsOwedPaisa;

  /// Verification deadlines of the pending claims (to compute "overdue").
  final List<DateTime> claimDeadlines;

  const SellerLiveCounts({
    this.pendingVerifications = 0,
    this.refundsOwed = 0,
    this.refundsOwedPaisa = 0,
    this.claimDeadlines = const [],
  });

  int overdueClaims(DateTime now) =>
      claimDeadlines.where((deadline) => deadline.isBefore(now)).length;
}

class SellerLiveStore extends ChangeNotifier with WidgetsBindingObserver {
  SellerLiveStore({
    required SellerRepository repository,
    SellerLiveEventSource? source,
    this.debounce = const Duration(milliseconds: 400),
    this.reconnectInterval = const Duration(seconds: 30),
    bool observeAppLifecycle = true,
    DateTime Function()? clock,
  })  : _repository = repository,
        _source = source,
        _observeAppLifecycle = observeAppLifecycle,
        _clock = clock ?? DateTime.now;

  /// The production transport, or `null` when Supabase is not initialised.
  static SellerLiveEventSource? defaultSource() {
    final service = SupabaseService.instance;
    if (!service.isInitialized) return null;
    return SupabaseSellerLiveEventSource(service.client);
  }

  /// Window in which a burst of events is coalesced into one revision bump.
  final Duration debounce;

  /// While the channel is down: how often to re-subscribe and poll.
  final Duration reconnectInterval;

  final SellerRepository _repository;
  final SellerLiveEventSource? _source;
  final bool _observeAppLifecycle;
  final DateTime Function() _clock;

  int _revision = 0;
  SellerLiveStatus _status = SellerLiveStatus.idle;
  SellerLiveCounts _counts = const SellerLiveCounts();
  bool _countsLoaded = false;
  int _catchUps = 0;
  Object? _lastError;

  final Set<String> _ownDropIds = {};
  final Set<String> _foreignDropIds = {};
  final Set<String> _unresolvedDropIds = {};
  final List<SellerLiveEvent> _buffered = [];
  bool _dropsLoaded = false;
  bool _resolvingDrops = false;

  Timer? _debounceTimer;
  Timer? _reconnectTimer;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  bool _observing = false;
  Future<void>? _countsInFlight;
  bool _countsAgain = false;
  DateTime? _backgroundedAt;

  /// Increases every time screens should reload their data.
  int get revision => _revision;
  SellerLiveStatus get status => _status;
  bool get isLive => _status == SellerLiveStatus.live;
  SellerLiveCounts get counts => _counts;
  bool get countsLoaded => _countsLoaded;
  int get pendingVerifications => _counts.pendingVerifications;
  int get overdueClaims => _counts.overdueClaims(_clock());
  int get refundsOwed => _counts.refundsOwed;
  int get refundsOwedPaisa => _counts.refundsOwedPaisa;

  /// Badge on the Payments tab: claims to verify + refunds to send.
  int get paymentsBadgeCount => pendingVerifications + refundsOwed;
  Set<String> get ownDropIds => Set.unmodifiable(_ownDropIds);

  /// Number of catch-ups (reconnect / resume / polling) performed.
  int get catchUpCount => _catchUps;

  /// Last error seen while loading counts / drops or from the transport.
  Object? get lastError => _lastError;

  bool get isDisposed => _disposed;

  /// Subscribes and loads the initial drop ids and counts.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (_observeAppLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _openSource();
    await _loadDrops();
    if (_disposed) return;
    final buffered = List<SellerLiveEvent>.of(_buffered);
    _buffered.clear();
    for (final event in buffered) {
      _handleEvent(event);
    }
    await refreshCounts();
  }

  /// Asks every screen to reload (e.g. after a local mutation), debounced
  /// unless [immediate].
  void requestRefresh({bool immediate = false}) {
    if (_disposed) return;
    if (immediate) {
      _flush();
    } else {
      _markDirty();
    }
  }

  /// Authoritative resynchronisation: reload drop ids, bump the revision and
  /// refetch counts. Runs after a reconnect, on app resume and while polling.
  Future<void> catchUp() async {
    if (_disposed || !_started) return;
    _catchUps++;
    await _loadDrops();
    if (_disposed) return;
    _flush();
  }

  /// Refetches the badge counts (coalesces concurrent requests).
  Future<void> refreshCounts() {
    if (_disposed) return Future<void>.value();
    final inFlight = _countsInFlight;
    if (inFlight != null) {
      _countsAgain = true;
      return inFlight;
    }
    final future = _loadCounts().whenComplete(() {
      _countsInFlight = null;
      if (_countsAgain && !_disposed) {
        _countsAgain = false;
        unawaited(refreshCounts());
      }
    });
    _countsInFlight = future;
    return future;
  }

  /// While the channel stays live, a background stay shorter than this
  /// (permission dialog, image picker…) does not need a catch-up.
  static const Duration resumeCatchUpAfter = Duration(seconds: 3);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= _clock();
        break;
      case AppLifecycleState.resumed:
        handleAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// App came back to the foreground: re-subscribe if needed and catch up.
  void handleAppResumed() {
    if (_disposed || !_started) return;
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    final channelDown = _source != null && _status != SellerLiveStatus.live;
    if (channelDown) {
      _openSource();
    }
    // While the channel stayed live, only a real stay in the background
    // (paused/hidden for a few seconds) can have missed something.
    final awayLongEnough = backgroundedAt != null &&
        _clock().difference(backgroundedAt) >= resumeCatchUpAfter;
    if (!channelDown && !awayLongEnough) return;
    unawaited(catchUp());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _generation++;
    final source = _source;
    if (source != null) {
      unawaited(source.close().then<void>((_) {}, onError: (Object _) {}));
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------

  void _openSource() {
    final source = _source;
    if (source == null) {
      _setStatus(SellerLiveStatus.unavailable);
      return;
    }
    final generation = ++_generation;
    if (_status == SellerLiveStatus.idle || _status == SellerLiveStatus.unavailable) {
      _setStatus(SellerLiveStatus.connecting);
    }
    try {
      source.open(
        onEvent: (event) {
          if (generation == _generation) _handleEvent(event);
        },
        onStatus: (status, error) {
          if (generation == _generation) _onTransportStatus(status, error);
        },
      );
    } catch (error) {
      _onTransportStatus(SellerLiveTransportStatus.error, error);
    }
  }

  void _onTransportStatus(SellerLiveTransportStatus status, Object? error) {
    if (_disposed) return;
    if (status == SellerLiveTransportStatus.subscribed) {
      final recovering = _status == SellerLiveStatus.reconnecting;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _setStatus(SellerLiveStatus.live);
      if (recovering) {
        // Events may have been missed while the channel was down.
        unawaited(catchUp());
      }
      return;
    }
    if (error != null) _lastError = error;
    _setStatus(SellerLiveStatus.reconnecting);
    _reconnectTimer ??= Timer.periodic(reconnectInterval, (_) => _reconnectTick());
  }

  void _reconnectTick() {
    if (_disposed || _status == SellerLiveStatus.live) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }
    // REST fallback while realtime is down, then try a fresh channel.
    unawaited(catchUp());
    _openSource();
  }

  void _handleEvent(SellerLiveEvent event) {
    if (_disposed) return;
    if (!_dropsLoaded) {
      if (_buffered.length < 500) {
        _buffered.add(event);
      }
      return;
    }
    switch (event.table) {
      case 'payment_attempts':
        // RLS scopes INSERT/UPDATE events to the seller's own orders; DELETE
        // payloads carry only the primary key and cannot be attributed.
        if (event.change == SellerLiveChange.delete) return;
        _markDirty();
        return;
      case 'orders':
      case 'products':
        final dropId = event.dropId;
        if (dropId == null) return; // unattributable (e.g. DELETE without drop_id)
        if (_ownDropIds.contains(dropId)) {
          _markDirty();
          return;
        }
        if (_foreignDropIds.contains(dropId)) return; // another seller's drop
        _unresolvedDropIds.add(dropId);
        unawaited(_resolveUnknownDrops());
        return;
      default:
        return;
    }
  }

  /// An event for a drop id we do not know: either a drop created after the
  /// last refresh (ours → relevant) or someone else's (ignored from now on).
  Future<void> _resolveUnknownDrops() async {
    if (_resolvingDrops) return;
    _resolvingDrops = true;
    try {
      while (_unresolvedDropIds.isNotEmpty && !_disposed) {
        final batch = Set<String>.of(_unresolvedDropIds);
        _unresolvedDropIds.clear();
        final loaded = await _loadDrops();
        if (_disposed || !loaded) return;
        var relevant = false;
        for (final dropId in batch) {
          if (_ownDropIds.contains(dropId)) {
            relevant = true;
          } else {
            _foreignDropIds.add(dropId);
          }
        }
        if (relevant) _markDirty();
      }
    } finally {
      _resolvingDrops = false;
    }
  }

  void _markDirty() {
    if (_disposed) return;
    _debounceTimer ??= Timer(debounce, _flush);
  }

  void _flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_disposed) return;
    _revision++;
    notifyListeners();
    unawaited(refreshCounts());
  }

  Future<bool> _loadDrops() async {
    try {
      final drops = await _repository.getDrops();
      if (_disposed) return false;
      _ownDropIds
        ..clear()
        ..addAll(drops.map((drop) => drop.id));
      _foreignDropIds.removeAll(_ownDropIds);
      return true;
    } catch (error) {
      _lastError = error;
      return false;
    } finally {
      _dropsLoaded = true;
    }
  }

  Future<void> _loadCounts() async {
    List<PaymentAttempt>? claims;
    List<OwedRefund>? refunds;
    try {
      claims = await _repository.getPendingVerifications();
    } catch (error) {
      _lastError = error;
    }
    try {
      refunds = await _repository.getRefundsOwed();
    } catch (error) {
      _lastError = error;
    }
    if (_disposed || (claims == null && refunds == null)) return;

    final previous = _counts;
    _counts = SellerLiveCounts(
      pendingVerifications: claims?.length ?? previous.pendingVerifications,
      claimDeadlines: claims == null
          ? previous.claimDeadlines
          : [
              for (final claim in claims)
                if (claim.verificationDeadline != null) claim.verificationDeadline!,
            ],
      refundsOwed: refunds?.length ?? previous.refundsOwed,
      refundsOwedPaisa: refunds == null
          ? previous.refundsOwedPaisa
          : refunds.fold<int>(0, (sum, refund) => sum + refund.refundAmountPaisa),
    );
    _countsLoaded = true;
    notifyListeners();
  }

  void _setStatus(SellerLiveStatus status) {
    if (_status == status || _disposed) return;
    _status = status;
    notifyListeners();
  }
}
