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
  paid,
  cancelled,
  shipped;

  static OrderStatus fromString(String value) {
    switch (value) {
      case 'paid':
        return OrderStatus.paid;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'shipped':
        return OrderStatus.shipped;
      case 'pending':
      default:
        return OrderStatus.pending;
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
  final String phoneNumber;
  final String upiId;
  final String? upiQrUrl;
  final String returnAddress;
  final int defaultShippingFeePaisa;
  final int? freeShippingThresholdPaisa;

  const SellerProfile({
    required this.id,
    required this.storeName,
    required this.phoneNumber,
    required this.upiId,
    this.upiQrUrl,
    required this.returnAddress,
    required this.defaultShippingFeePaisa,
    this.freeShippingThresholdPaisa,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      id: json['id'] as String,
      storeName: json['store_name'] as String,
      phoneNumber: json['phone_number'] as String,
      upiId: json['upi_id'] as String,
      upiQrUrl: json['upi_qr_url'] as String?,
      returnAddress: json['return_address'] as String,
      defaultShippingFeePaisa: json['default_shipping_fee_paisa'] as int,
      freeShippingThresholdPaisa: json['free_shipping_threshold_paisa'] as int?,
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
      liveStartedAt: json['live_started_at'] != null
          ? DateTime.parse(json['live_started_at'] as String)
          : null,
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
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
    required this.status,
    this.reservedAt,
    this.reservedByOrderId,
    required this.version,
  });

  factory SellerProduct.fromJson(Map<String, dynamic> json) {
    return SellerProduct(
      id: json['id'] as String,
      dropId: json['drop_id'] as String,
      code: json['code'] as String,
      title: json['title'] as String,
      pricePaisa: json['price_paisa'] as int,
      size: json['size'] as String,
      imageUrl: json['image_url'] as String,
      status: ProductStatus.fromString(json['status'] as String),
      reservedAt: json['reserved_at'] != null
          ? DateTime.parse(json['reserved_at'] as String)
          : null,
      reservedByOrderId: json['reserved_by_order_id'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }
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
  final DateTime? holdExpiresAt;
  final DateTime? paidAt;
  final DateTime? shippedAt;
  final String? trackingNumber;
  final String? courierPartner;
  final DateTime createdAt;
  final List<SellerOrderItem> items;

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
    this.holdExpiresAt,
    this.paidAt,
    this.shippedAt,
    this.trackingNumber,
    this.courierPartner,
    required this.createdAt,
    required this.items,
  });

  factory SellerOrder.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['order_items'] as List<dynamic>?)
            ?.map((e) => SellerOrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

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
      totalPaisa: json['total_paisa'] as int,
      status: OrderStatus.fromString(json['status'] as String),
      holdExpiresAt: json['hold_expires_at'] != null
          ? DateTime.parse(json['hold_expires_at'] as String)
          : null,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      shippedAt: json['shipped_at'] != null
          ? DateTime.parse(json['shipped_at'] as String)
          : null,
      trackingNumber: json['tracking_number'] as String?,
      courierPartner: json['courier_partner'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: itemsList,
    );
  }
}
