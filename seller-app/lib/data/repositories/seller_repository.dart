import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/supabase_service.dart';
import '../../core/validation/product_rules.dart';
import '../../domain/models/models.dart';

/// LiveDrop Seller Mobile App — Application Data Access Repository
///
/// Encapsulates all seller-specific database and RPC interactions.
/// All queries are secured server-side by PostgreSQL Row-Level Security (`auth.uid() = seller_id`).
///
/// Under no circumstances may `release_expired_holds()` be exposed here;
/// that routine is strictly reserved for service_role background execution.
/// Error codes that database triggers put in the HINT field (migration 039),
/// because a trigger cannot return a JSON error like an RPC does.
const Set<String> _triggerHintCodes = {
  'DROP_TRANSITION_FORBIDDEN',
  'DROP_SLUG_LOCKED',
  'REAUTH_REQUIRED',
};

/// Converts a PostgREST error into a [LiveDropException], preferring the
/// machine-readable code a trigger put in the hint.
LiveDropException liveDropExceptionFrom(PostgrestException e) {
  final hint = e.hint;
  final code = hint != null && _triggerHintCodes.contains(hint) ? hint : (e.code ?? 'POSTGREST_ERROR');
  return LiveDropException(e.message, code: code);
}

class SellerRepository {
  final SupabaseClient _client;

  SellerRepository({SupabaseClient? client})
    : _client =
          client ??
          (SupabaseService.instance.isInitialized
              ? SupabaseService.instance.client
              : throw StateError(
                  'SellerRepository cannot be instantiated before SupabaseService is initialized. '
                  'Initialize SupabaseService first or provide an explicit SupabaseClient.',
                ));

  String _requireSellerId() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const UnauthorizedException(
        'Seller authentication required. No active session found.',
      );
    }
    return uid;
  }

  /// Normalises an RPC `jsonb` response (map or JSON string) to a map.
  static Map<String, dynamic> _rpcMap(dynamic response) {
    if (response is String) {
      return (jsonDecode(response) as Map).cast<String, dynamic>();
    }
    if (response is Map) {
      return response.cast<String, dynamic>();
    }
    throw const LiveDropException(
      'Unexpected response from the server.',
      code: 'INVALID_RESPONSE',
    );
  }

  /// Columns for the "Refunds owed" list (contract §11).
  static const String refundsOwedColumns =
      'id, drop_id, order_code, buyer_name, buyer_phone, status, total_paisa, '
      'total_paid_paisa, payment_status, refund_status, refund_amount_paisa, '
      'refund_reason, refund_required_at, refund_reference, refunded_at, created_at';

  /// Same rule as `record_refund`: trimmed, 4–64 characters of
  /// letters, digits, space, `_`, `.`, `/` or `-`.
  static final RegExp refundReferencePattern = RegExp(r'^[A-Za-z0-9_./ -]+$');

  /// Returns `null` when [raw] is an acceptable refund reference.
  static String? validateRefundReference(String raw) {
    final reference = raw.trim();
    if (reference.length < 4 || reference.length > 64) {
      return 'Enter 4–64 characters (the UPI reference / UTR of your refund).';
    }
    if (!refundReferencePattern.hasMatch(reference)) {
      return 'Use only letters, digits, spaces and . _ / -';
    }
    return null;
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
      throw liveDropExceptionFrom(e);
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
      throw liveDropExceptionFrom(e);
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
      throw liveDropExceptionFrom(e);
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
            order_token,
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
            ),
            payment_attempts (
              id,
              status,
              buyer_submitted_utr
            )
          ''')
          .eq('drop_id', dropId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((e) => SellerOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
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
  @Deprecated(
    'mark_order_paid is now service_role only. Use backend payment verification.',
  )
  Future<bool> markOrderPaid(String orderId) async {
    throw UnsupportedError(
      'markOrderPaid is no longer available from the seller client. '
      'Payment confirmation must go through the backend payment verification service '
      '(service_role only). See F-01 in the TASK-2.4A.1 audit report.',
    );
  }

  /// Forces manual release of a reserved hold via the `force_release_hold` RPC.
  ///
  /// The server refuses with `PAYMENT_CLAIM_PENDING` while the buyer has a
  /// payment claim on the order (SA-PAY-005); the error code is preserved on
  /// the thrown [LiveDropException] so the UI can show a friendly message.
  Future<bool> forceReleaseHold(String orderId) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'force_release_hold',
        params: {'p_order_id': orderId},
      );

      final map = _rpcMap(response);
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'UNKNOWN_ERROR';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return true;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
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
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return true;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Puts a piece the seller marked sold offline back on sale, within 30
  /// minutes (ADR-014, `undo_mark_product_sold_offline`).
  Future<void> undoMarkProductSoldOffline(String productId) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'undo_mark_product_sold_offline',
        params: {'p_product_id': productId},
      );
      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'UNKNOWN_ERROR';
        throw LiveDropException(map['message'] as String? ?? error, code: error);
      }
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Confirms the signed-in seller's password by signing in again. The new
  /// session carries a fresh password time, which the database requires
  /// before the payee UPI ID or phone number can change (SA-AUTH-004).
  Future<void> reauthenticate(String password) async {
    _requireSellerId();
    final email = _client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw const LiveDropException('Sign in again to continue.', code: 'UNAUTHORIZED');
    }
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid')) {
        throw const LiveDropException('That password is not correct.', code: 'WRONG_PASSWORD');
      }
      throw LiveDropException(e.message, code: 'AUTH_ERROR');
    }
  }

  /// The seller's recent payee detail changes (UPI ID, display name, phone),
  /// newest first (SA-AUTH-004, table `payee_change_log`).
  Future<List<PayeeChange>> getPayeeChangeLog({int limit = 10}) async {
    _requireSellerId();
    try {
      final response = await _client
          .from('payee_change_log')
          .select('field, old_value, new_value, changed_at, changed_by_role')
          .order('changed_at', ascending: false)
          .limit(limit);
      return (response as List<dynamic>)
          .map((row) => PayeeChange.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Updates core boutique profile fields (store name, phone, return address, default shipping fee, advance rules).
  ///
  /// [freeShippingThresholdPaisa] sets the shop's free-shipping threshold;
  /// pass [clearFreeShippingThreshold] = true to remove it (no free shipping
  /// unless a drop sets its own threshold — SA-PAY-008).
  Future<SellerProfile> updateProfile({
    String? storeName,
    String? phoneNumber,
    String? returnAddress,
    int? defaultShippingFeePaisa,
    int? freeShippingThresholdPaisa,
    bool clearFreeShippingThreshold = false,
    bool? advanceConfirmationEnabled,
    int? advanceAmountPaisa,
    int? holdDurationDays,
    String? upiId,
  }) async {
    final sellerId = _requireSellerId();

    final updates = <String, dynamic>{};
    if (storeName != null && storeName.trim().isNotEmpty) {
      updates['store_name'] = storeName.trim();
    }
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      updates['phone_number'] = phoneNumber.trim();
    }
    if (returnAddress != null && returnAddress.trim().isNotEmpty) {
      updates['return_address'] = returnAddress.trim();
    }
    if (defaultShippingFeePaisa != null) {
      updates['default_shipping_fee_paisa'] = defaultShippingFeePaisa;
    }
    if (clearFreeShippingThreshold) {
      updates['free_shipping_threshold_paisa'] = null;
    } else if (freeShippingThresholdPaisa != null) {
      if (freeShippingThresholdPaisa <= 0) {
        throw const LiveDropException(
          'Free-shipping threshold must be more than ₹0.',
          code: 'INVALID_FREE_SHIPPING_THRESHOLD',
        );
      }
      updates['free_shipping_threshold_paisa'] = freeShippingThresholdPaisa;
    }
    if (advanceConfirmationEnabled != null) {
      updates['advance_confirmation_enabled'] = advanceConfirmationEnabled;
    }
    if (advanceAmountPaisa != null) {
      updates['advance_amount_paisa'] = advanceAmountPaisa;
    }
    if (holdDurationDays != null) {
      updates['hold_duration_days'] = holdDurationDays;
    }
    if (upiId != null && upiId.trim().isNotEmpty) {
      updates['upi_id'] = upiId.trim();
      updates['upi_vpa'] = upiId.trim();
    }

    if (updates.isEmpty) {
      return getProfile();
    }

    try {
      final response = await _client
          .from('profiles')
          .update(updates)
          .eq('id', sellerId)
          .select()
          .single();

      return SellerProfile.fromJson(response);
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
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
      await _client
          .from('profiles')
          .update({
            'upi_enabled': upiEnabled,
            'upi_vpa': upiVpa,
            'upi_id': upiVpa,
            'upi_display_name': upiDisplayName,
            'payment_instructions': paymentInstructions,
          })
          .eq('id', sellerId);
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
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
            verification_expires_at,
            expires_at,
            created_at,
            orders!inner (
              order_code,
              buyer_name,
              buyer_phone,
              order_token,
              status,
              total_paisa,
              order_items (
                products (
                  code,
                  title,
                  image_url,
                  status,
                  reserved_by_order_id
                )
              )
            )
          ''')
          .inFilter('status', ['buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review'])
          .order('buyer_claimed_at', ascending: true);

      return (response as List<dynamic>)
          .map((e) => PaymentAttempt.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Fetches all payment attempts associated with a specific order.
  Future<List<PaymentAttempt>> getPaymentAttemptsForOrder(
    String orderId,
  ) async {
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
            verification_expires_at,
            expires_at,
            created_at
          ''')
          .eq('order_id', orderId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((e) => PaymentAttempt.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Verifies a manual direct UPI payment attempt via `verify_manual_upi_payment` RPC.
  ///
  /// The returned map carries `refund_required`, `refund_amount_paisa`,
  /// `is_late_claim` and `inventory_available` (contract §5): when
  /// `refund_required` is true the money was recorded but the piece had been
  /// resold, and the seller owes the buyer a refund (SA-PAY-004).
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
          'p_utr': ?overrideReference,
        },
      );

      final map = _rpcMap(response);
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'VERIFICATION_FAILED';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return map;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Dispatches an order and records courier tracking via `mark_order_shipped` RPC.
  Future<Map<String, dynamic>> markOrderShipped({
    required String orderId,
    required String trackingNumber,
    required String courierPartner,
    String? notes,
  }) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'mark_order_shipped',
        params: {
          'p_order_id': orderId,
          'p_tracking_number': trackingNumber,
          'p_courier_partner': courierPartner,
          'p_notes': ?notes,
        },
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'SHIPPING_FAILED';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return map;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Authoritatively transitions an order from 'not_ready' to 'ready_to_ship'
  /// and records packing timestamp (`packed_at`).
  Future<Map<String, dynamic>> markOrderReadyToShip(String orderId) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'mark_order_ready_to_ship',
        params: {'p_order_id': orderId},
      );

      final map = response is String
          ? jsonDecode(response) as Map<String, dynamic>
          : (response as Map).cast<String, dynamic>();

      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'READY_TO_SHIP_FAILED';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return map;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Rejects an unverified manual payment claim via `reject_manual_upi_payment` RPC.
  Future<Map<String, dynamic>> rejectManualUpiPayment(
    String paymentAttemptId,
    String rejectionReason, {
    bool releaseHold = true,
  }) async {
    _requireSellerId();

    try {
      final response = await _client.rpc<dynamic>(
        'reject_manual_upi_payment',
        params: {
          'p_payment_attempt_id': paymentAttemptId,
          'p_rejection_reason': rejectionReason,
          'p_release_hold': releaseHold,
        },
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'REJECTION_FAILED';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return map;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Orders on which this seller owes the buyer a refund (`refund_status =
  /// 'required'`), oldest obligation first. RLS scopes the rows to the seller.
  Future<List<OwedRefund>> getRefundsOwed() async {
    _requireSellerId();

    try {
      final response = await _client
          .from('orders')
          .select(refundsOwedColumns)
          .eq('refund_status', 'required')
          .order('refund_required_at', ascending: true);

      return (response as List<dynamic>)
          .map((e) => OwedRefund.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Records that the seller has refunded the buyer via the `record_refund`
  /// RPC (contract §10). The reference is validated locally with the same
  /// rule as the server, which stays authoritative.
  Future<Map<String, dynamic>> recordRefund(
    String orderId,
    String refundReference, {
    String? note,
  }) async {
    _requireSellerId();

    final reference = refundReference.trim();
    final referenceError = validateRefundReference(reference);
    if (referenceError != null) {
      throw LiveDropException(referenceError, code: 'INVALID_REFUND_REFERENCE');
    }
    final cleanNote = note?.trim();

    try {
      final response = await _client.rpc<dynamic>(
        'record_refund',
        params: {
          'p_order_id': orderId,
          'p_refund_reference': reference,
          if (cleanNote != null && cleanNote.isNotEmpty) 'p_note': cleanNote,
        },
      );

      final map = _rpcMap(response);
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'REFUND_FAILED';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return map;
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Looks up the product with [code] in [dropId] (UNIQUE(drop_id, code)).
  /// Used by the intake queue to recognise a create whose response was lost.
  Future<SellerProduct?> findProductByCode({
    required String dropId,
    required String code,
  }) async {
    _requireSellerId();

    try {
      final response = await _client
          .from('products')
          .select()
          .eq('drop_id', dropId)
          .eq('code', code)
          .maybeSingle();

      return response == null ? null : SellerProduct.fromJson(response);
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Creates a new drop in draft status.
  Future<SellerDrop> createDrop({
    required String title,
    required String slug,
    required int shippingFeePaisa,
    int? freeShippingThresholdPaisa,
    String? streamUrl,
  }) async {
    final sellerId = _requireSellerId();

    try {
      final payload = <String, dynamic>{
        'seller_id': sellerId,
        'title': title.trim(),
        'slug': slug.trim().toLowerCase(),
        'status': 'draft',
        'shipping_fee_paisa': shippingFeePaisa,
        'free_shipping_threshold_paisa': freeShippingThresholdPaisa,
      };
      if (streamUrl != null && streamUrl.trim().isNotEmpty) {
        payload['stream_url'] = streamUrl.trim();
      }

      final response = await _client
          .from('drops')
          .insert(payload)
          .select()
          .single();

      return SellerDrop.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const LiveDropException(
          'A drop with this slug already exists. Please choose another unique slug.',
          code: 'SLUG_TAKEN',
        );
      }
      throw liveDropExceptionFrom(e);
    }
  }

  /// Updates drop details (title, slug, shipping parameters, stream_url).
  Future<SellerDrop> updateDrop({
    required String dropId,
    required String title,
    required String slug,
    required int shippingFeePaisa,
    int? freeShippingThresholdPaisa,
    String? streamUrl,
  }) async {
    _requireSellerId();

    try {
      final updateData = <String, dynamic>{
        'title': title.trim(),
        'slug': slug.trim().toLowerCase(),
        'shipping_fee_paisa': shippingFeePaisa,
        'free_shipping_threshold_paisa': freeShippingThresholdPaisa,
        'stream_url': (streamUrl != null && streamUrl.trim().isNotEmpty)
            ? streamUrl.trim()
            : null,
      };

      final response = await _client
          .from('drops')
          .update(updateData)
          .eq('id', dropId)
          .select()
          .single();

      return SellerDrop.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const LiveDropException(
          'A drop with this slug already exists. Please choose another unique slug.',
          code: 'SLUG_TAKEN',
        );
      }
      throw liveDropExceptionFrom(e);
    }
  }

  /// Transitions drop status (draft -> live -> closed).
  /// Enforces RULE-DRP-03: Only 1 live drop per seller at a time.
  /// Uses atomic close_drop RPC when transitioning to closed.
  Future<SellerDrop> updateDropStatus({
    required String dropId,
    required DropStatus status,
  }) async {
    _requireSellerId();

    try {
      if (status == DropStatus.closed) {
        await _client.rpc<void>('close_drop', params: {'p_drop_id': dropId});
        final response = await _client
            .from('drops')
            .select()
            .eq('id', dropId)
            .single();
        return SellerDrop.fromJson(response);
      }

      final updateData = <String, dynamic>{'status': status.toDbValue()};
      if (status == DropStatus.live) {
        updateData['live_started_at'] = DateTime.now()
            .toUtc()
            .toIso8601String();
      }

      final response = await _client
          .from('drops')
          .update(updateData)
          .eq('id', dropId)
          .select()
          .single();

      return SellerDrop.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505' ||
          e.message.contains('idx_drops_one_live_per_seller')) {
        throw const LiveDropException(
          'Only one drop can be live at a time. Please close your currently live drop before taking this one live.',
          code: 'MULTIPLE_LIVE_DROPS',
        );
      }
      throw liveDropExceptionFrom(e);
    }
  }

  /// Closes an active live drop safely via the atomic `close_drop` RPC.
  /// Gracefully unfreezes unclaimed reservations and preserves confirmed holds.
  Future<SellerDrop> closeDrop(String dropId) async {
    return updateDropStatus(dropId: dropId, status: DropStatus.closed);
  }

  /// Creates a new product for a drop.
  Future<SellerProduct> createProduct({
    required String dropId,
    required String code,
    required String title,
    required int pricePaisa,
    required String size,
    required String imageUrl,
    List<String>? imageUrls,
  }) async {
    _requireSellerId();

    final allImageUrls = (imageUrls != null && imageUrls.isNotEmpty)
        ? imageUrls
        : [imageUrl.trim()];

    try {
      final response = await _client
          .from('products')
          .insert({
            'drop_id': dropId,
            'code': ProductRules.normalizeCode(code),
            'title': title.trim(),
            'price_paisa': pricePaisa,
            'size': size.trim(),
            'image_url': imageUrl.trim(),
            'image_urls': allImageUrls,
            'status': 'available',
          })
          .select()
          .single();

      return SellerProduct.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw LiveDropException(
          'Product flash code "${ProductRules.normalizeCode(code)}" is already taken in this drop. Codes must be unique within a drop.',
          code: 'DUPLICATE_PRODUCT_CODE',
        );
      }
      throw liveDropExceptionFrom(e);
    }
  }

  /// Authoritatively updates product attributes (title, price in Paisa, size)
  /// using the PostgreSQL `update_product` RPC.
  /// Rejects modifications on reserved or sold items.
  Future<SellerProduct> updateProduct({
    required String productId,
    required String title,
    required int pricePaisa,
    required String size,
  }) async {
    _requireSellerId();

    try {
      final dynamic response = await _client.rpc<dynamic>(
        'update_product',
        params: {
          'p_product_id': productId,
          'p_title': title.trim(),
          'p_price_paisa': pricePaisa,
          'p_size': size.trim(),
        },
      );

      final Map<String, dynamic> result = response is String
          ? jsonDecode(response) as Map<String, dynamic>
          : (response as Map<dynamic, dynamic>).cast<String, dynamic>();

      if (result['success'] != true) {
        throw LiveDropException(
          result['message'] as String? ?? 'Failed to update product',
          code: result['error'] as String? ?? 'UPDATE_FAILED',
        );
      }

      final productJson = (result['product'] as Map).cast<String, dynamic>();
      return SellerProduct.fromJson(productJson);
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Uploads a compressed boutique garment image to Supabase Storage.
  /// Object path follows: {seller_id}/{drop_id}/{filename} satisfying RLS policy.
  Future<String> uploadProductImage({
    required String dropId,
    required String fileName,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    final sellerId = _requireSellerId();
    final cleanFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = '$sellerId/$dropId/$cleanFileName';

    try {
      await _client.storage
          .from('product-images')
          .uploadBinary(
            storagePath,
            imageBytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );

      final publicUrl = _client.storage
          .from('product-images')
          .getPublicUrl(storagePath);
      return publicUrl;
    } on StorageException catch (e) {
      throw LiveDropException(e.message, code: e.statusCode ?? 'STORAGE_ERROR');
    }
  }

  /// Fetches all orders across all drops or filtered by drop / status.
  /// Most orders one list asks for (SA-PERF-001). A drop has far fewer; across
  /// all drops the newest ones are the ones that still need work.
  static const int ordersPageLimit = 300;

  Future<List<SellerOrder>> getAllOrders({
    String? dropId,
    String? status,
    int limit = ordersPageLimit,
  }) async {
    _requireSellerId();

    try {
      var query = _client.from('orders').select('''
        id,
        drop_id,
        order_code,
        order_token,
        buyer_name,
        buyer_phone,
        shipping_address,
        pincode,
        subtotal_paisa,
        shipping_paisa,
        total_paisa,
        status,
        confirmation_mode,
        advance_required_paisa,
        advance_paid_paisa,
        total_paid_paisa,
        balance_due_paisa,
        payment_status,
        fulfilment_status,
        advance_paid_at,
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
        ),
        payment_attempts (
          id,
          status,
          buyer_submitted_utr
        )
      ''');

      if (dropId != null) {
        query = query.eq('drop_id', dropId);
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false).limit(limit);
      return (response as List<dynamic>)
          .map((e) => SellerOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }

  /// Fetches recent seller activity across payment claims and orders.
  Future<List<SellerActivityItem>> getRecentActivity({
    String? dropId,
    int limit = 5,
  }) async {
    _requireSellerId();

    try {
      final items = <SellerActivityItem>[];

      // 1. Fetch pending verification claims
      final claims = await getPendingVerifications();
      for (final claim in claims) {
        items.add(
          SellerActivityItem(
            id: 'claim_${claim.id}',
            title: 'New payment claim #${claim.orderCode ?? (claim.transactionReference.length > 8 ? claim.transactionReference.substring(0, 8) : claim.transactionReference)}',
            subtitle: '₹${(claim.expectedAmountPaisa / 100).toStringAsFixed(0)} claimed via ${claim.paymentMethod.toUpperCase()}',
            timestamp: claim.buyerClaimedAt ?? claim.createdAt,
            type: 'payment_claim',
          ),
        );
      }

      // 2. Fetch latest orders (only a few are shown)
      final orders = await getAllOrders(dropId: dropId, limit: 20);
      for (final order in orders) {
        if (order.status == OrderStatus.shipped) {
          items.add(
            SellerActivityItem(
              id: 'order_shipped_${order.id}',
              title: 'Order #${order.orderCode} dispatched',
              subtitle: '${order.courierPartner ?? "Courier"} tracking: ${order.trackingNumber ?? "N/A"}',
              timestamp: order.shippedAt ?? order.createdAt,
              type: 'order_shipped',
            ),
          );
        } else if (order.status == OrderStatus.paid) {
          items.add(
            SellerActivityItem(
              id: 'order_paid_${order.id}',
              title: 'Order #${order.orderCode} payment confirmed',
              subtitle: '₹${(order.totalPaidPaisa / 100).toStringAsFixed(0)} • Ready to pack',
              timestamp: order.paidAt ?? order.createdAt,
              type: 'order_paid',
            ),
          );
        } else {
          items.add(
            SellerActivityItem(
              id: 'order_held_${order.id}',
              title: 'Order #${order.orderCode} reserved',
              subtitle: '${order.items.length} item(s) on hold',
              timestamp: order.createdAt,
              type: 'order_placed',
            ),
          );
        }
      }

      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  /// `seller_sales_summary` result, or `null` when the function is not
  /// deployed yet (PostgREST PGRST202 / SQLSTATE 42883).
  Future<Map<String, dynamic>?> _salesSummary(DateTime from, int utcOffsetMinutes) async {
    try {
      final response = await _client.rpc<dynamic>('seller_sales_summary', params: {
        'p_from': from.toUtc().toIso8601String(),
        'p_utc_offset_minutes': utcOffsetMinutes,
      });
      if (response is Map) return response.cast<String, dynamic>();
      if (response is String) return jsonDecode(response) as Map<String, dynamic>;
      return null;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  /// Computes real analytics from database orders, products, and payment claims.
  /// Range can be: 'Today', 'Last 7 days', 'Last 30 days', 'This Month'.
  Future<SellerAnalytics> getSellerAnalytics({String? range}) async {
    _requireSellerId();

    try {
      // Day boundaries follow the seller's local calendar (IST on Indian
      // devices), not UTC midnight (SA-ORD-001).
      final now = DateTime.now();
      DateTime startDate;

      switch (range) {
        case 'Today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'Last 30 days':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case 'This Month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        case 'Last 7 days':
        default:
          startDate = now.subtract(const Duration(days: 7));
          break;
      }

      final pendingClaims = await getPendingVerifications();

      // SA-PERF-001: figures come from seller_sales_summary (migration 040),
      // a few hundred bytes instead of every order. Until 040 is deployed the
      // previous local computation is used.
      final summary = await _salesSummary(startDate, now.timeZoneOffset.inMinutes);
      if (summary != null) {
        return SellerAnalytics.fromSummary(summary, paymentClaimsCount: pendingClaims.length);
      }

      final allOrders = await getAllOrders(limit: 2000);

      int totalRevenuePaisa = 0;
      int itemsSoldCount = 0;
      int activeHoldsCount = 0;

      final Map<String, _AggregatedProduct> productStats = {};

      for (final order in allOrders) {
        final isPaidOrShipped = order.status == OrderStatus.paid || order.status == OrderStatus.shipped;
        final isInRange = order.createdAt.isAfter(startDate) || order.createdAt.isAtSameMomentAs(startDate);

        if (order.status == OrderStatus.pending || order.status == OrderStatus.confirmed) {
          activeHoldsCount += order.items.length;
        }

        if (isPaidOrShipped && isInRange) {
          final paidAmount = order.totalPaidPaisa > 0 ? order.totalPaidPaisa : order.totalPaisa;
          totalRevenuePaisa += paidAmount;
          itemsSoldCount += order.items.length;

          for (final item in order.items) {
            final code = item.productCode ?? 'Piece';
            final title = item.productTitle ?? code;
            final existing = productStats[code];
            if (existing == null) {
              productStats[code] = _AggregatedProduct(
                code: code,
                title: title,
                count: 1,
                revenuePaisa: item.priceAtPurchasePaisa,
                imageUrl: item.productImageUrl,
              );
            } else {
              existing.count += 1;
              existing.revenuePaisa += item.priceAtPurchasePaisa;
            }
          }
        }
      }

      // Daily Sales for the past 7 days
      final List<DailySalesStat> dailySales = [];
      int peakRevenuePaisa = 0;
      const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      for (int i = 6; i >= 0; i--) {
        final dayDate = DateTime(now.year, now.month, now.day - i);
        final nextDay = DateTime(now.year, now.month, now.day - i + 1);

        int dayTotalPaisa = 0;
        for (final order in allOrders) {
          final isPaidOrShipped = order.status == OrderStatus.paid || order.status == OrderStatus.shipped;
          if (isPaidOrShipped) {
            final orderDate = order.paidAt ?? order.createdAt;
            if ((orderDate.isAfter(dayDate) || orderDate.isAtSameMomentAs(dayDate)) &&
                orderDate.isBefore(nextDay)) {
              dayTotalPaisa += (order.totalPaidPaisa > 0 ? order.totalPaidPaisa : order.totalPaisa);
            }
          }
        }

        if (dayTotalPaisa > peakRevenuePaisa) {
          peakRevenuePaisa = dayTotalPaisa;
        }

        dailySales.add(
          DailySalesStat(
            date: dayDate,
            dayLabel: dayNames[dayDate.weekday - 1],
            totalPaisa: dayTotalPaisa,
          ),
        );
      }

      // Sort top products
      final topProductsList = productStats.values.map((p) {
        return TopProductStat(
          productCode: p.code,
          title: p.title,
          soldCount: p.count,
          revenuePaisa: p.revenuePaisa,
          imageUrl: p.imageUrl,
        );
      }).toList()
        ..sort((a, b) => b.soldCount.compareTo(a.soldCount));

      return SellerAnalytics(
        totalRevenuePaisa: totalRevenuePaisa,
        itemsSoldCount: itemsSoldCount,
        activeHoldsCount: activeHoldsCount,
        paymentClaimsCount: pendingClaims.length,
        peakRevenuePaisa: peakRevenuePaisa,
        dailySales: dailySales,
        topProducts: topProductsList.take(5).toList(),
      );
    } on PostgrestException catch (e) {
      throw liveDropExceptionFrom(e);
    }
  }
}

class _AggregatedProduct {
  final String code;
  final String title;
  int count;
  int revenuePaisa;
  final String? imageUrl;

  _AggregatedProduct({
    required this.code,
    required this.title,
    required this.count,
    required this.revenuePaisa,
    this.imageUrl,
  });
}
