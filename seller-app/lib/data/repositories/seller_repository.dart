import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/models/models.dart';

/// LiveDrop Seller Mobile App — Application Data Access Repository
///
/// Encapsulates all seller-specific database and RPC interactions.
/// All queries are secured server-side by PostgreSQL Row-Level Security (`auth.uid() = seller_id`).
///
/// Under no circumstances may `release_expired_holds()` be exposed here;
/// that routine is strictly reserved for service_role background execution.
class SellerRepository {
  final SupabaseClient _client;

  SellerRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String _requireSellerId() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const UnauthorizedException(
        'Seller authentication required. No active session found.',
      );
    }
    return uid;
  }

  /// Fetches the profile for the currently authenticated seller.
  Future<SellerProfile> getProfile() async {
    final sellerId = _requireSellerId();

    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', sellerId)
          .maybeSingle();

      if (response == null) {
        throw const LiveDropException(
          'Seller profile not found.',
          code: 'PROFILE_NOT_FOUND',
        );
      }

      return SellerProfile.fromJson(response);
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Fetches all drops created by the authenticated seller.
  Future<List<SellerDrop>> getDrops() async {
    final sellerId = _requireSellerId();

    try {
      final response = await _client
          .from('drops')
          .select()
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((e) => SellerDrop.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Fetches all products associated with a specific drop.
  Future<List<SellerProduct>> getProducts(String dropId) async {
    _requireSellerId();

    try {
      final response = await _client
          .from('products')
          .select()
          .eq('drop_id', dropId)
          .order('code', ascending: true);

      return (response as List<dynamic>)
          .map((e) => SellerProduct.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Fetches all orders for a specific drop with associated line items and products.
  Future<List<SellerOrder>> getOrders(String dropId) async {
    _requireSellerId();

    try {
      final response = await _client
          .from('orders')
          .select('''
            id,
            drop_id,
            order_code,
            buyer_name,
            buyer_phone,
            shipping_address,
            pincode,
            subtotal_paisa,
            shipping_paisa,
            total_paisa,
            status,
            hold_expires_at,
            paid_at,
            shipped_at,
            tracking_number,
            courier_partner,
            created_at,
            order_items (
              id,
              order_id,
              product_id,
              price_at_purchase_paisa,
              products (
                code,
                title,
                image_url
              )
            )
          ''')
          .eq('drop_id', dropId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((e) => SellerOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Confirms buyer payment via the `mark_order_paid` atomic RPC.
  Future<bool> markOrderPaid(String orderId) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'mark_order_paid',
        params: {'p_order_id': orderId},
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'UNKNOWN_ERROR';
        if (error == 'PRODUCT_ALREADY_RECLAIMED') {
          throw ProductReclaimedException(
            map['message'] as String? ??
                'One or more items in this order were claimed by another buyer after the hold expired.',
          );
        }
        throw LiveDropException(map['message'] as String? ?? error, code: error);
      }

      return true;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Forces manual release of a reserved hold via the `force_release_hold` RPC.
  Future<bool> forceReleaseHold(String orderId) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'force_release_hold',
        params: {'p_order_id': orderId},
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'UNKNOWN_ERROR';
        throw LiveDropException(map['message'] as String? ?? error, code: error);
      }

      return true;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Marks a piece as sold offline via the `mark_product_sold_offline` RPC.
  Future<bool> markProductSoldOffline(String productId) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'mark_product_sold_offline',
        params: {'p_product_id': productId},
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'UNKNOWN_ERROR';
        throw LiveDropException(map['message'] as String? ?? error, code: error);
      }

      return true;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }
}
