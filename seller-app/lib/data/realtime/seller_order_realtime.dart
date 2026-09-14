import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../domain/models/models.dart';

/// LiveDrop Seller Mobile App — Realtime Order Subscription Manager
///
/// Subscribes to real-time order creations and transitions for an active drop
/// per docs/14-realtime-contract.md.
class SellerOrderRealtimeSubscription {
  final SupabaseClient _client;
  final String dropId;
  final void Function(SellerOrder order) onOrderCreated;
  final void Function(SellerOrder order) onOrderUpdated;
  final void Function(String status)? onStatusChanged;

  RealtimeChannel? _channel;

  SellerOrderRealtimeSubscription({
    SupabaseClient? client,
    required this.dropId,
    required this.onOrderCreated,
    required this.onOrderUpdated,
    this.onStatusChanged,
  }) : _client = client ??
            (SupabaseService.instance.isInitialized
                ? SupabaseService.instance.client
                : throw StateError(
                    'SellerOrderRealtimeSubscription cannot be instantiated before SupabaseService is initialized. '
                    'Initialize SupabaseService first or provide an explicit SupabaseClient.',
                  ));

  /// Subscribes to postgres_changes for orders matching the specified dropId.
  RealtimeChannel subscribe() {
    if (_channel != null) {
      return _channel!;
    }

    final channelName = 'seller-orders-$dropId';

    _channel = _client.channel(channelName);

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'drop_id',
        value: dropId,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        if (record.isNotEmpty) {
          try {
            final order = SellerOrder.fromJson(record);
            onOrderCreated(order);
          } catch (_) {
            // Handled gracefully without crash
          }
        }
      },
    );

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'drop_id',
        value: dropId,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        if (record.isNotEmpty) {
          try {
            final order = SellerOrder.fromJson(record);
            onOrderUpdated(order);
          } catch (_) {
            // Handled gracefully without crash
          }
        }
      },
    );

    _channel!.subscribe((status, [error]) {
      onStatusChanged?.call(status.name);
    });

    return _channel!;
  }

  /// Cancels and removes the realtime channel subscription.
  Future<void> unsubscribe() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
  }
}
