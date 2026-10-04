/// LiveDrop Seller Mobile App — Domain Models
///
/// All monetary values are strictly non-negative integers in Paisa (1 INR = 100 Paisa).
/// Floating-point monetary values are strictly forbidden (ADR-009).
library;

enum ProductStatus {
  available,
  reserved,
  sold;

  static ProductStatus fromString(String value) {
    switch (value) {
      case 'reserved':
        return ProductStatus.reserved;
      case 'sold':
        return ProductStatus.sold;
      case 'available':
      default:
        return ProductStatus.available;
    }
  }

  String toDbValue() {
    switch (this) {
      case ProductStatus.reserved:
        return 'reserved';
      case ProductStatus.sold:
        return 'sold';
      case ProductStatus.available:
        return 'available';
    }
  }
}

enum OrderStatus {
  pending,
  confirmed,
  paid,
  cancelled,
  shipped,
  expired;

  static OrderStatus fromString(String value) {
    switch (value) {
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'paid':
        return OrderStatus.paid;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'shipped':
        return OrderStatus.shipped;
      case 'expired':
        return OrderStatus.expired;
      case 'pending':
      default:
        return OrderStatus.pending;
    }
  }

  String toDbValue() => name;
}

enum OrderConfirmationMode {
  advance,
  fullPayment;

  static OrderConfirmationMode fromString(String value) {
    switch (value) {
      case 'full_payment':
        return OrderConfirmationMode.fullPayment;
      case 'advance':
      default:
        return OrderConfirmationMode.advance;
    }
  }

  String toDbValue() {
    switch (this) {
      case OrderConfirmationMode.fullPayment:
        return 'full_payment';
      case OrderConfirmationMode.advance:
        return 'advance';
    }
  }
}

enum OrderPaymentStatus {
  unpaid,
  advancePaid,
  paid;

  static OrderPaymentStatus fromString(String value) {
    switch (value) {
      case 'advance_paid':
        return OrderPaymentStatus.advancePaid;
      case 'paid':
        return OrderPaymentStatus.paid;
      case 'unpaid':
      default:
        return OrderPaymentStatus.unpaid;
    }
  }

  String toDbValue() {
    switch (this) {
      case OrderPaymentStatus.advancePaid:
        return 'advance_paid';
      case OrderPaymentStatus.paid:
        return 'paid';
      case OrderPaymentStatus.unpaid:
        return 'unpaid';
    }
  }
}

enum OrderFulfilmentStatus {
  notReady,
  readyToShip,
  shipped;

  static OrderFulfilmentStatus fromString(String value) {
    switch (value) {
      case 'ready_to_ship':
        return OrderFulfilmentStatus.readyToShip;
      case 'shipped':
        return OrderFulfilmentStatus.shipped;
      case 'not_ready':
      default:
        return OrderFulfilmentStatus.notReady;
    }
  }

  String toDbValue() {
    switch (this) {
      case OrderFulfilmentStatus.readyToShip:
        return 'ready_to_ship';
      case OrderFulfilmentStatus.shipped:
        return 'shipped';
      case OrderFulfilmentStatus.notReady:
        return 'not_ready';
    }
  }
}

/// Refund obligation on an order (orders.refund_status, migration 035).
enum RefundStatus {
  none,
  required,
  refunded;

  static RefundStatus fromString(String? value) {
    switch (value) {
      case 'required':
        return RefundStatus.required;
      case 'refunded':
        return RefundStatus.refunded;
      case 'none':
      default:
        return RefundStatus.none;
    }
  }

  String toDbValue() => name;
}

enum DropStatus {
  draft,
  live,
  closed;

  static DropStatus fromString(String value) {
    switch (value) {
      case 'live':
        return DropStatus.live;
      case 'closed':
        return DropStatus.closed;
      case 'draft':
      default:
        return DropStatus.draft;
    }
  }

  String toDbValue() => name;
}

class SellerProfile {
  final String id;
  final String storeName;
  final String storeSlug;
  final String phoneNumber;
  final String upiId;
  final String? upiQrUrl;
  final String returnAddress;
  final int defaultShippingFeePaisa;
  final int? freeShippingThresholdPaisa;
  final bool advanceConfirmationEnabled;
  final int advanceAmountPaisa;
  final int holdDurationDays;
  final bool upiEnabled;
  final String? upiVpa;
  final String? upiDisplayName;
  final String? paymentInstructions;
  final bool isApproved;

  const SellerProfile({
    required this.id,
    required this.storeName,
    required this.storeSlug,
    required this.phoneNumber,
    required this.upiId,
    this.upiQrUrl,
    required this.returnAddress,
    required this.defaultShippingFeePaisa,
    this.freeShippingThresholdPaisa,
    required this.advanceConfirmationEnabled,
    required this.advanceAmountPaisa,
    required this.holdDurationDays,
    this.upiEnabled = true,
    this.upiVpa,
    this.upiDisplayName,
    this.paymentInstructions,
    this.isApproved = false,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      id: json['id'] as String,
      storeName: json['store_name'] as String,
      storeSlug: json['store_slug'] as String? ?? 'store',
      phoneNumber: json['phone_number'] as String,
      upiId: json['upi_id'] as String,
      upiQrUrl: json['upi_qr_url'] as String?,
      returnAddress: json['return_address'] as String,
      defaultShippingFeePaisa: json['default_shipping_fee_paisa'] as int? ?? 8000,
      freeShippingThresholdPaisa: json['free_shipping_threshold_paisa'] as int?,
      advanceConfirmationEnabled: json['advance_confirmation_enabled'] as bool? ?? false,
      advanceAmountPaisa: json['advance_amount_paisa'] as int? ?? 25000,
      holdDurationDays: json['hold_duration_days'] as int? ?? 30,
      upiEnabled: json['upi_enabled'] as bool? ?? true,
      upiVpa: json['upi_vpa'] as String? ?? json['upi_id'] as String?,
      upiDisplayName: json['upi_display_name'] as String?,
      paymentInstructions: json['payment_instructions'] as String?,
      isApproved: json['is_approved'] as bool? ?? false,
    );
  }
}

class SellerDrop {
  final String id;
  final String sellerId;
  final String title;
  final String slug;
  final DropStatus status;
  final int shippingFeePaisa;
  final int? freeShippingThresholdPaisa;
  final String? streamUrl;
  final DateTime? liveStartedAt;
  final DateTime? closedAt;
  final DateTime createdAt;

  const SellerDrop({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.slug,
    required this.status,
    required this.shippingFeePaisa,
    this.freeShippingThresholdPaisa,
    this.streamUrl,
    this.liveStartedAt,
    this.closedAt,
    required this.createdAt,
  });

  factory SellerDrop.fromJson(Map<String, dynamic> json) {
    return SellerDrop(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String,
      title: json['title'] as String,
      slug: json['slug'] as String,
      status: DropStatus.fromString(json['status'] as String),
      shippingFeePaisa: json['shipping_fee_paisa'] as int,
      freeShippingThresholdPaisa: json['free_shipping_threshold_paisa'] as int?,
      streamUrl: json['stream_url'] as String?,
      liveStartedAt: json['live_started_at'] != null
          ? _parseTimestamp(json['live_started_at'] as String)
          : null,
      closedAt: json['closed_at'] != null
          ? _parseTimestamp(json['closed_at'] as String)
          : null,
      createdAt: _parseTimestamp(json['created_at'] as String),
    );
  }
}

class SellerProduct {
  final String id;
  final String dropId;
  final String code;
  final String title;
  final int pricePaisa;
  final String size;
  final String imageUrl;
  final List<String> imageUrls;
  final ProductStatus status;
  final DateTime? reservedAt;
  final String? reservedByOrderId;
  final int version;

  const SellerProduct({
    required this.id,
    required this.dropId,
    required this.code,
    required this.title,
    required this.pricePaisa,
    required this.size,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.status,
    this.reservedAt,
    this.reservedByOrderId,
    required this.version,
  });

  factory SellerProduct.fromJson(Map<String, dynamic> json) {
    final rawImageUrls = json['image_urls'];
    List<String> parsedImageUrls = [];
    if (rawImageUrls is List) {
      parsedImageUrls = rawImageUrls.map((e) => e.toString()).toList();
    }
    final primaryImageUrl = json['image_url'] as String? ??
        (parsedImageUrls.isNotEmpty ? parsedImageUrls.first : '');
    if (parsedImageUrls.isEmpty && primaryImageUrl.isNotEmpty) {
      parsedImageUrls = [primaryImageUrl];
    }

    return SellerProduct(
      id: json['id'] as String,
      dropId: json['drop_id'] as String,
      code: json['code'] as String,
      title: json['title'] as String,
      pricePaisa: json['price_paisa'] as int,
      size: json['size'] as String,
      imageUrl: primaryImageUrl,
      imageUrls: parsedImageUrls,
      status: ProductStatus.fromString(json['status'] as String),
      reservedAt: json['reserved_at'] != null
          ? _parseTimestamp(json['reserved_at'] as String)
          : null,
      reservedByOrderId: json['reserved_by_order_id'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'drop_id': dropId,
    'code': code,
    'title': title,
    'price_paisa': pricePaisa,
    'size': size,
    'image_url': imageUrl,
    'image_urls': imageUrls.isNotEmpty ? imageUrls : [imageUrl],
    'status': status.toDbValue(),
    'reserved_at': reservedAt?.toUtc().toIso8601String(),
    'reserved_by_order_id': reservedByOrderId,
    'version': version,
  };
}

class SellerOrderItem {
  final String id;
  final String orderId;
  final String productId;
  final int priceAtPurchasePaisa;
  final String? productCode;
  final String? productTitle;
  final String? productImageUrl;

  const SellerOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.priceAtPurchasePaisa,
    this.productCode,
    this.productTitle,
    this.productImageUrl,
  });

  factory SellerOrderItem.fromJson(Map<String, dynamic> json) {
    final productMap = json['products'] as Map<String, dynamic>?;

    return SellerOrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String,
      priceAtPurchasePaisa: json['price_at_purchase_paisa'] as int,
      productCode: productMap?['code'] as String?,
      productTitle: productMap?['title'] as String?,
      productImageUrl: productMap?['image_url'] as String?,
    );
  }
}

/// Minimal view of a payment attempt embedded in an order list
/// (`payment_attempts(id, status, buyer_submitted_utr)`), used to know
/// whether the buyer has already claimed a payment (SA-PAY-005).
class OrderPaymentAttemptSummary {
  final String id;
  final PaymentAttemptStatus status;
  final String? buyerSubmittedUtr;

  const OrderPaymentAttemptSummary({
    required this.id,
    required this.status,
    this.buyerSubmittedUtr,
  });

  bool get isClaim => status.isClaim;

  static OrderPaymentAttemptSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final status = raw['status'];
    if (id is! String || status is! String) return null;
    final utr = raw['buyer_submitted_utr'];
    return OrderPaymentAttemptSummary(
      id: id,
      status: PaymentAttemptStatus.fromString(status),
      buyerSubmittedUtr: utr is String ? utr : null,
    );
  }
}

/// PostgREST returns `timestamptz` in UTC. Every timestamp the app shows or
/// buckets by day is converted to the device's local time here, at the model
/// boundary (SA-ORD-001: order times and labels were 5 h 30 min early in IST).
/// Instants are unchanged, so comparisons and durations are not affected.
DateTime _parseTimestamp(String value) => DateTime.parse(value).toLocal();

DateTime? _parseOptionalDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

int _parseOptionalInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

class SellerOrder {
  final String id;
  final String dropId;
  final String orderCode;
  final String buyerName;
  final String buyerPhone;
  final String shippingAddress;
  final String pincode;
  final int subtotalPaisa;
  final int shippingPaisa;
  final int totalPaisa;
  final OrderStatus status;
  final OrderConfirmationMode confirmationMode;
  final int advanceRequiredPaisa;
  final int advancePaidPaisa;
  final int totalPaidPaisa;
  final int balanceDuePaisa;
  final OrderPaymentStatus paymentStatus;
  final OrderFulfilmentStatus fulfilmentStatus;
  final DateTime? advancePaidAt;
  final DateTime? holdExpiresAt;
  final DateTime? paidAt;
  final DateTime? packedAt;
  final DateTime? shippedAt;
  final String? trackingNumber;
  final String? courierPartner;
  final DateTime createdAt;
  final List<SellerOrderItem> items;

  /// Refund obligation (migration 035). Defaults keep older rows parseable.
  final RefundStatus refundStatus;
  final int refundAmountPaisa;
  final String? refundReason;
  final DateTime? refundRequiredAt;
  final String? refundReference;
  final DateTime? refundedAt;

  /// Payment attempts embedded in order lists (empty when not selected).
  final List<OrderPaymentAttemptSummary> paymentAttempts;

  const SellerOrder({
    required this.id,
    required this.dropId,
    required this.orderCode,
    required this.buyerName,
    required this.buyerPhone,
    required this.shippingAddress,
    required this.pincode,
    required this.subtotalPaisa,
    required this.shippingPaisa,
    required this.totalPaisa,
    required this.status,
    required this.confirmationMode,
    required this.advanceRequiredPaisa,
    required this.advancePaidPaisa,
    required this.totalPaidPaisa,
    required this.balanceDuePaisa,
    required this.paymentStatus,
    required this.fulfilmentStatus,
    this.advancePaidAt,
    this.holdExpiresAt,
    this.paidAt,
    this.packedAt,
    this.shippedAt,
    this.trackingNumber,
    this.courierPartner,
    required this.createdAt,
    required this.items,
    this.refundStatus = RefundStatus.none,
    this.refundAmountPaisa = 0,
    this.refundReason,
    this.refundRequiredAt,
    this.refundReference,
    this.refundedAt,
    this.paymentAttempts = const [],
  });

  /// The buyer-claimed attempt awaiting the seller (if any). While it exists
  /// the hold must not be released (force_release_hold → PAYMENT_CLAIM_PENDING).
  OrderPaymentAttemptSummary? get pendingPaymentClaim {
    for (final attempt in paymentAttempts) {
      if (attempt.isClaim) return attempt;
    }
    return null;
  }

  bool get hasPendingPaymentClaim => pendingPaymentClaim != null;

  bool get isRefundOwed => refundStatus == RefundStatus.required;

  factory SellerOrder.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['order_items'] as List<dynamic>?)
            ?.map((e) => SellerOrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    final rawAttempts = json['payment_attempts'];
    final attempts = <OrderPaymentAttemptSummary>[];
    if (rawAttempts is List) {
      for (final raw in rawAttempts) {
        final parsed = OrderPaymentAttemptSummary.tryParse(raw);
        if (parsed != null) attempts.add(parsed);
      }
    }

    final total = json['total_paisa'] as int;
    final totalPaid = json['total_paid_paisa'] as int? ?? 0;
    final balanceDue = json['balance_due_paisa'] as int? ?? (total - totalPaid);

    return SellerOrder(
      id: json['id'] as String,
      dropId: json['drop_id'] as String,
      orderCode: json['order_code'] as String,
      buyerName: json['buyer_name'] as String,
      buyerPhone: json['buyer_phone'] as String,
      shippingAddress: json['shipping_address'] as String,
      pincode: json['pincode'] as String,
      subtotalPaisa: json['subtotal_paisa'] as int,
      shippingPaisa: json['shipping_paisa'] as int,
      totalPaisa: total,
      status: OrderStatus.fromString(json['status'] as String),
      confirmationMode: OrderConfirmationMode.fromString(
          json['confirmation_mode'] as String? ?? 'advance'),
      advanceRequiredPaisa: json['advance_required_paisa'] as int? ?? 0,
      advancePaidPaisa: json['advance_paid_paisa'] as int? ?? 0,
      totalPaidPaisa: totalPaid,
      balanceDuePaisa: balanceDue,
      paymentStatus: OrderPaymentStatus.fromString(
          json['payment_status'] as String? ?? 'unpaid'),
      fulfilmentStatus: OrderFulfilmentStatus.fromString(
          json['fulfilment_status'] as String? ?? 'not_ready'),
      advancePaidAt: json['advance_paid_at'] != null
          ? _parseTimestamp(json['advance_paid_at'] as String)
          : null,
      holdExpiresAt: json['hold_expires_at'] != null
          ? _parseTimestamp(json['hold_expires_at'] as String)
          : null,
      paidAt: json['paid_at'] != null
          ? _parseTimestamp(json['paid_at'] as String)
          : null,
      packedAt: json['packed_at'] != null
          ? _parseTimestamp(json['packed_at'] as String)
          : null,
      shippedAt: json['shipped_at'] != null
          ? _parseTimestamp(json['shipped_at'] as String)
          : null,
      trackingNumber: json['tracking_number'] as String?,
      courierPartner: json['courier_partner'] as String?,
      createdAt: _parseTimestamp(json['created_at'] as String),
      items: itemsList,
      refundStatus: RefundStatus.fromString(json['refund_status'] as String?),
      refundAmountPaisa: _parseOptionalInt(json['refund_amount_paisa']),
      refundReason: json['refund_reason'] as String?,
      refundRequiredAt: _parseOptionalDate(json['refund_required_at']),
      refundReference: json['refund_reference'] as String?,
      refundedAt: _parseOptionalDate(json['refunded_at']),
      paymentAttempts: List.unmodifiable(attempts),
    );
  }
}

/// An order on which the seller owes the buyer a refund (refund_status =
/// 'required'), e.g. a late payment verified after the piece was resold
/// (SA-PAY-004). Parsed from the contract §11 projection; every field that may
/// be missing on older rows has a safe default.
class OwedRefund {
  final String orderId;
  final String? dropId;
  final String orderCode;
  final String buyerName;
  final String buyerPhone;
  final OrderStatus orderStatus;
  final int totalPaisa;
  final int totalPaidPaisa;
  final OrderPaymentStatus paymentStatus;
  final RefundStatus refundStatus;
  final int refundAmountPaisa;
  final String? refundReason;
  final DateTime? refundRequiredAt;
  final String? refundReference;
  final DateTime? refundedAt;
  final DateTime? createdAt;

  const OwedRefund({
    required this.orderId,
    this.dropId,
    required this.orderCode,
    required this.buyerName,
    required this.buyerPhone,
    this.orderStatus = OrderStatus.cancelled,
    this.totalPaisa = 0,
    this.totalPaidPaisa = 0,
    this.paymentStatus = OrderPaymentStatus.paid,
    this.refundStatus = RefundStatus.required,
    required this.refundAmountPaisa,
    this.refundReason,
    this.refundRequiredAt,
    this.refundReference,
    this.refundedAt,
    this.createdAt,
  });

  factory OwedRefund.fromJson(Map<String, dynamic> json) {
    return OwedRefund(
      orderId: json['id'] as String,
      dropId: json['drop_id'] as String?,
      orderCode: json['order_code'] as String? ?? '',
      buyerName: json['buyer_name'] as String? ?? 'Buyer',
      buyerPhone: json['buyer_phone'] as String? ?? '',
      orderStatus: OrderStatus.fromString(json['status'] as String? ?? 'cancelled'),
      totalPaisa: _parseOptionalInt(json['total_paisa']),
      totalPaidPaisa: _parseOptionalInt(json['total_paid_paisa']),
      paymentStatus: OrderPaymentStatus.fromString(json['payment_status'] as String? ?? 'paid'),
      refundStatus: RefundStatus.fromString(json['refund_status'] as String?),
      refundAmountPaisa: _parseOptionalInt(json['refund_amount_paisa']),
      refundReason: json['refund_reason'] as String?,
      refundRequiredAt: _parseOptionalDate(json['refund_required_at']),
      refundReference: json['refund_reference'] as String?,
      refundedAt: _parseOptionalDate(json['refunded_at']),
      createdAt: _parseOptionalDate(json['created_at']),
    );
  }

  /// Seller-facing explanation of why the refund is owed.
  String get reasonLabel => describeRefundReason(refundReason);

  static String describeRefundReason(String? reason) {
    if (reason == 'LATE_PAYMENT_INVENTORY_UNAVAILABLE') {
      return 'Late payment — the piece was no longer available when you verified it.';
    }
    if (reason == null || reason.trim().isEmpty) {
      return 'Payment received for an order that cannot be fulfilled.';
    }
    final readable = reason.replaceAll('_', ' ').toLowerCase();
    return '${readable[0].toUpperCase()}${readable.substring(1)}.';
  }
}

enum PaymentAttemptStatus {
  created,
  awaitingPayment,
  buyerClaimed,
  awaitingSellerVerification,
  lateClaimPendingReview,
  verified,
  rejected,
  expired;

  static PaymentAttemptStatus fromString(String value) {
    switch (value) {
      case 'awaiting_payment':
        return PaymentAttemptStatus.awaitingPayment;
      case 'buyer_claimed':
        return PaymentAttemptStatus.buyerClaimed;
      case 'awaiting_seller_verification':
        return PaymentAttemptStatus.awaitingSellerVerification;
      case 'late_claim_pending_review':
        return PaymentAttemptStatus.lateClaimPendingReview;
      case 'verified':
        return PaymentAttemptStatus.verified;
      case 'rejected':
        return PaymentAttemptStatus.rejected;
      case 'expired':
        return PaymentAttemptStatus.expired;
      case 'created':
      default:
        return PaymentAttemptStatus.created;
    }
  }

  /// Statuses meaning "the buyer says they paid and the seller must decide".
  /// These stay in the seller's queue until verified or rejected (SA-PAY-003).
  static const Set<PaymentAttemptStatus> claimStatuses = {
    PaymentAttemptStatus.buyerClaimed,
    PaymentAttemptStatus.awaitingSellerVerification,
    PaymentAttemptStatus.lateClaimPendingReview,
  };

  bool get isClaim => claimStatuses.contains(this);

  String toDbValue() {
    switch (this) {
      case PaymentAttemptStatus.awaitingPayment:
        return 'awaiting_payment';
      case PaymentAttemptStatus.buyerClaimed:
        return 'buyer_claimed';
      case PaymentAttemptStatus.awaitingSellerVerification:
        return 'awaiting_seller_verification';
      case PaymentAttemptStatus.lateClaimPendingReview:
        return 'late_claim_pending_review';
      case PaymentAttemptStatus.verified:
        return 'verified';
      case PaymentAttemptStatus.rejected:
        return 'rejected';
      case PaymentAttemptStatus.expired:
        return 'expired';
      case PaymentAttemptStatus.created:
        return 'created';
    }
  }
}

class PaymentAttempt {
  final String id;
  final String orderId;
  final String paymentType;
  final String paymentMethod;
  final int expectedAmountPaisa;
  final String payeeVpaSnapshot;
  final String? payeeDisplayNameSnapshot;
  final String transactionReference;
  final PaymentAttemptStatus status;
  final DateTime? buyerClaimedAt;
  final String? buyerSubmittedUtr;
  final DateTime? sellerVerifiedAt;
  final String? verifiedBy;
  final String? rejectionReason;
  final DateTime? verificationExpiresAt;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String? orderCode;
  final String? buyerName;

  const PaymentAttempt({
    required this.id,
    required this.orderId,
    required this.paymentType,
    required this.paymentMethod,
    required this.expectedAmountPaisa,
    required this.payeeVpaSnapshot,
    this.payeeDisplayNameSnapshot,
    required this.transactionReference,
    required this.status,
    this.buyerClaimedAt,
    this.buyerSubmittedUtr,
    this.sellerVerifiedAt,
    this.verifiedBy,
    this.rejectionReason,
    this.verificationExpiresAt,
    required this.expiresAt,
    required this.createdAt,
    this.orderCode,
    this.buyerName,
  });

  bool get isLateClaim => status == PaymentAttemptStatus.lateClaimPendingReview;

  /// When the seller was expected to have verified this claim: its
  /// `verification_expires_at` only (contract §11 — overdue means
  /// `verification_expires_at < now()`). Null means the claim has no
  /// verification deadline, so it is listed but never "overdue":
  /// - `expires_at` is the buyer's payment window, never a verification
  ///   window, so it is never used as a fallback. A late claim is submitted
  ///   after `expires_at` by definition, and the late path of
  ///   `submit_buyer_payment_claim` (023) leaves `verification_expires_at`
  ///   untouched (NULL for an attempt never claimed before).
  /// - A window that ended at or before the current `buyer_claimed_at`
  ///   belongs to an earlier claim on the same attempt (the late path keeps
  ///   the old value), not to this claim.
  DateTime? get verificationDeadline {
    if (!status.isClaim) return null;
    final deadline = verificationExpiresAt;
    if (deadline == null) return null;
    final claimedAt = buyerClaimedAt;
    if (claimedAt != null && !deadline.isAfter(claimedAt)) return null;
    return deadline;
  }

  /// A claim whose verification window has passed. The server keeps it
  /// verifiable (money in flight never auto-expires), so the seller must
  /// still verify or reject it — it is shown first and labelled "Overdue".
  bool isOverdue(DateTime now) {
    final deadline = verificationDeadline;
    return deadline != null && deadline.isBefore(now);
  }

  factory PaymentAttempt.fromJson(Map<String, dynamic> json) {
    final orderMap = json['orders'] as Map<String, dynamic>?;

    return PaymentAttempt(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      paymentType: json['payment_type'] as String,
      paymentMethod: json['payment_method'] as String? ?? 'upi',
      expectedAmountPaisa: json['expected_amount_paisa'] as int,
      payeeVpaSnapshot: json['payee_vpa_snapshot'] as String,
      payeeDisplayNameSnapshot: json['payee_display_name_snapshot'] as String?,
      transactionReference: json['transaction_reference'] as String,
      status: PaymentAttemptStatus.fromString(json['status'] as String),
      buyerClaimedAt: json['buyer_claimed_at'] != null
          ? _parseTimestamp(json['buyer_claimed_at'] as String)
          : null,
      buyerSubmittedUtr: json['buyer_submitted_utr'] as String?,
      sellerVerifiedAt: json['seller_verified_at'] != null
          ? _parseTimestamp(json['seller_verified_at'] as String)
          : null,
      verifiedBy: json['verified_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      verificationExpiresAt: json['verification_expires_at'] != null
          ? _parseTimestamp(json['verification_expires_at'] as String)
          : null,
      expiresAt: _parseTimestamp(json['expires_at'] as String),
      createdAt: _parseTimestamp(json['created_at'] as String),
      orderCode: orderMap?['order_code'] as String?,
      buyerName: orderMap?['buyer_name'] as String?,
    );
  }
}

class TopProductStat {
  final String productCode;
  final String title;
  final int soldCount;
  final int revenuePaisa;
  final String? imageUrl;

  const TopProductStat({
    required this.productCode,
    required this.title,
    required this.soldCount,
    required this.revenuePaisa,
    this.imageUrl,
  });
}

class DailySalesStat {
  final DateTime date;
  final String dayLabel;
  final int totalPaisa;

  const DailySalesStat({
    required this.date,
    required this.dayLabel,
    required this.totalPaisa,
  });
}

class SellerAnalytics {
  final int totalRevenuePaisa;
  final int itemsSoldCount;
  final int activeHoldsCount;
  final int paymentClaimsCount;
  final int peakRevenuePaisa;
  final List<DailySalesStat> dailySales;
  final List<TopProductStat> topProducts;

  const SellerAnalytics({
    required this.totalRevenuePaisa,
    required this.itemsSoldCount,
    required this.activeHoldsCount,
    required this.paymentClaimsCount,
    required this.peakRevenuePaisa,
    required this.dailySales,
    required this.topProducts,
  });
}

class SellerActivityItem {
  final String id;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String type;

  const SellerActivityItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.type,
  });
}

