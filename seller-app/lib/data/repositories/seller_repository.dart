import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/supabase_service.dart';
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
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
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
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return true;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Updates core boutique profile fields (store name, phone, return address, default shipping fee, advance rules).
  Future<SellerProfile> updateProfile({
    String? storeName,
    String? phoneNumber,
    String? returnAddress,
    int? defaultShippingFeePaisa,
    int? freeShippingThresholdPaisa,
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
    if (freeShippingThresholdPaisa != null) {
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
          'p_override_reference': ?overrideReference,
        },
      );

      final map = response as Map<String, dynamic>;
      if (map['success'] != true) {
        final error = map['error'] as String? ?? 'VERIFICATION_FAILED';
        throw LiveDropException(
          map['message'] as String? ?? error,
          code: error,
        );
      }

      return map;
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
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
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
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
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Creates a new drop in draft status.
  Future<SellerDrop> createDrop({
    required String title,
    required String slug,
    required int shippingFeePaisa,
    int? freeShippingThresholdPaisa,
  }) async {
    final sellerId = _requireSellerId();

    try {
      final response = await _client
          .from('drops')
          .insert({
            'seller_id': sellerId,
            'title': title.trim(),
            'slug': slug.trim().toLowerCase(),
            'status': 'draft',
            'shipping_fee_paisa': shippingFeePaisa,
            'free_shipping_threshold_paisa': freeShippingThresholdPaisa,
          })
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
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Updates drop details (title, slug, shipping parameters).
  Future<SellerDrop> updateDrop({
    required String dropId,
    required String title,
    required String slug,
    required int shippingFeePaisa,
    int? freeShippingThresholdPaisa,
  }) async {
    _requireSellerId();

    try {
      final response = await _client
          .from('drops')
          .update({
            'title': title.trim(),
            'slug': slug.trim().toLowerCase(),
            'shipping_fee_paisa': shippingFeePaisa,
            'free_shipping_threshold_paisa': freeShippingThresholdPaisa,
          })
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
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Transitions drop status (draft -> live -> closed).
  /// Enforces RULE-DRP-03: Only 1 live drop per seller at a time.
  Future<SellerDrop> updateDropStatus({
    required String dropId,
    required DropStatus status,
  }) async {
    _requireSellerId();

    try {
      final updateData = <String, dynamic>{'status': status.toDbValue()};
      if (status == DropStatus.live) {
        updateData['live_started_at'] = DateTime.now()
            .toUtc()
            .toIso8601String();
      } else if (status == DropStatus.closed) {
        updateData['closed_at'] = DateTime.now().toUtc().toIso8601String();
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
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
    }
  }

  /// Creates a new product for a drop.
  Future<SellerProduct> createProduct({
    required String dropId,
    required String code,
    required String title,
    required int pricePaisa,
    required String size,
    required String imageUrl,
  }) async {
    _requireSellerId();

    try {
      final response = await _client
          .from('products')
          .insert({
            'drop_id': dropId,
            'code': code.trim().toUpperCase(),
            'title': title.trim(),
            'price_paisa': pricePaisa,
            'size': size.trim(),
            'image_url': imageUrl.trim(),
            'status': 'available',
          })
          .select()
          .single();

      return SellerProduct.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw LiveDropException(
          'Product flash code "$code" is already taken in this drop. Codes must be unique within a drop.',
          code: 'DUPLICATE_PRODUCT_CODE',
        );
      }
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
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
  Future<List<SellerOrder>> getAllOrders({
    String? dropId,
    String? status,
  }) async {
    _requireSellerId();

    try {
      var query = _client.from('orders').select('''
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
        )
      ''');

      if (dropId != null) {
        query = query.eq('drop_id', dropId);
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List<dynamic>)
          .map((e) => SellerOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
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

      // 2. Fetch latest orders
      final orders = await getAllOrders(dropId: dropId);
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

  /// Computes real analytics from database orders, products, and payment claims.
  /// Range can be: 'Today', 'Last 7 days', 'Last 30 days', 'This Month'.
  Future<SellerAnalytics> getSellerAnalytics({String? range}) async {
    _requireSellerId();

    try {
      final now = DateTime.now().toUtc();
      DateTime startDate;

      switch (range) {
        case 'Today':
          startDate = DateTime.utc(now.year, now.month, now.day);
          break;
        case 'Last 30 days':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case 'This Month':
          startDate = DateTime.utc(now.year, now.month, 1);
          break;
        case 'Last 7 days':
        default:
          startDate = now.subtract(const Duration(days: 7));
          break;
      }

      final allOrders = await getAllOrders();
      final pendingClaims = await getPendingVerifications();

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
        final dayDate = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: i));
        final nextDay = dayDate.add(const Duration(days: 1));

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
      throw LiveDropException(e.message, code: e.code ?? 'POSTGREST_ERROR');
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
