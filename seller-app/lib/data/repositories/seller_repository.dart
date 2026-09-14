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

  /// [DEPRECATED — F-01 Audit Remediation]
  /// `mark_order_paid` is now restricted to `service_role` only.
  /// Payment confirmation must go through the backend payment verification
  /// service, not the authenticated Dart client.
  ///
  /// This method is intentionally preserved (not deleted) so that call sites
  /// produce a clear compile-time reference and a runtime error, rather than
  /// silently failing with a PostgreSQL permission denied error.
  @Deprecated('mark_order_paid is now service_role only. Use backend payment verification.')
  Future<bool> markOrderPaid(String orderId) async {
    throw UnsupportedError(
      'markOrderPaid is no longer available from the seller client. '
      'Payment confirmation must go through the backend payment verification service '
      '(service_role only). See F-01 in the TASK-2.4A.1 audit report.',
    );
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

  /// Updates seller-level UPI settings.
  Future<void> updateUpiSettings({
    required bool upiEnabled,
    required String upiVpa,
    String? upiDisplayName,
    String? paymentInstructions,
  }) async {
    final sellerId = _requireSellerId();

    try {
      await _client.from('profiles').update({
        'upi_enabled': upiEnabled,
        'upi_vpa': upiVpa,
        'upi_id': upiVpa,
        'upi_display_name': upiDisplayName,
        'payment_instructions': paymentInstructions,
      }).eq('id', sellerId);
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Fetches pending payment attempts awaiting manual verification by this seller.
  Future<List<PaymentAttempt>> getPendingVerifications() async {
    _requireSellerId();

    try {
      final response = await _client
          .from('payment_attempts')
          .select('''
            id,
            order_id,
            payment_type,
            payment_method,
            expected_amount_paisa,
            payee_vpa_snapshot,
            payee_display_name_snapshot,
            transaction_reference,
            status,
            buyer_claimed_at,
            buyer_submitted_utr,
            seller_verified_at,
            verified_by,
            rejection_reason,
            expires_at,
            created_at,
            orders!inner (
              order_code,
              buyer_name
            )
          ''')
          .inFilter('status', ['buyer_claimed', 'awaiting_seller_verification'])
          .order('buyer_claimed_at', ascending: true);

      return (response as List<dynamic>)
          .map((e) => PaymentAttempt.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Fetches all payment attempts associated with a specific order.
  Future<List<PaymentAttempt>> getPaymentAttemptsForOrder(String orderId) async {
    _requireSellerId();

    try {
      final response = await _client
          .from('payment_attempts')
          .select('''
            id,
            order_id,
            payment_type,
            payment_method,
            expected_amount_paisa,
            payee_vpa_snapshot,
            payee_display_name_snapshot,
            transaction_reference,
            status,
            buyer_claimed_at,
            buyer_submitted_utr,
            seller_verified_at,
            verified_by,
            rejection_reason,
            expires_at,
            created_at
          ''')
          .eq('order_id', orderId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((e) => PaymentAttempt.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Verifies a manual direct UPI payment attempt via `verify_manual_upi_payment` RPC.
  Future<Map<String, dynamic>> verifyManualUpiPayment(
    String paymentAttemptId, [
    String? overrideReference,
  ]) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'verify_manual_upi_payment',
        params: {
          'p_payment_attempt_id': paymentAttemptId,
          if (overrideReference != null) 'p_override_reference': overrideReference,
        },
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'VERIFICATION_FAILED';
        throw LiveDropException(map['message'] as String? ?? error, code: error);
      }

      return map;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Rejects an unverified manual payment claim via `reject_manual_upi_payment` RPC.
  Future<Map<String, dynamic>> rejectManualUpiPayment(
    String paymentAttemptId,
    String rejectionReason,
  ) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'reject_manual_upi_payment',
        params: {
          'p_payment_attempt_id': paymentAttemptId,
          'p_rejection_reason': rejectionReason,
        },
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'REJECTION_FAILED';
        throw LiveDropException(map['message'] as String? ?? error, code: error);
      }

      return map;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }
}
