// Shared fakes for the P0 remediation tests (SA-INT-001, SA-RT-001,
// SA-PAY-003/004/005). Not a test file itself (no `_test` suffix).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/theme/app_theme.dart';
import 'package:seller_app/data/realtime/seller_live_store.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';

const testProfile = SellerProfile(
  id: 'seller-1',
  storeName: 'Aarohi Boutique',
  storeSlug: 'aarohi-boutique',
  phoneNumber: '9876500001',
  upiId: 'aarohi@okaxis',
  returnAddress: '12 MG Road, Kolkata 700001',
  defaultShippingFeePaisa: 8000,
  advanceConfirmationEnabled: false,
  advanceAmountPaisa: 25000,
  holdDurationDays: 30,
  isApproved: true,
);

SellerDrop testDrop({String id = 'drop-1', String title = 'Saturday Live', DropStatus status = DropStatus.live}) {
  return SellerDrop(
    id: id,
    sellerId: testProfile.id,
    title: title,
    slug: 'saturday-live-$id',
    status: status,
    shippingFeePaisa: 8000,
    createdAt: DateTime.utc(2026, 10, 1),
  );
}

/// A late claim exactly as the late path of `submit_buyer_payment_claim`
/// (023_late_upi_recovery.sql) leaves it: claimed a minute ago, status
/// `late_claim_pending_review`, `verification_expires_at` untouched (NULL for
/// an attempt never claimed before) and `expires_at` already in the past.
PaymentAttempt freshLateClaim({
  String id = 'late-claim',
  String orderId = 'order-late',
  String orderCode = 'LD-LATE01',
  DateTime? verificationExpiresAt,
}) {
  final now = DateTime.now();
  return PaymentAttempt(
    id: id,
    orderId: orderId,
    paymentType: 'full',
    paymentMethod: 'upi',
    expectedAmountPaisa: 158000,
    payeeVpaSnapshot: 'aarohi@okaxis',
    transactionReference: 'LD-$id',
    status: PaymentAttemptStatus.lateClaimPendingReview,
    buyerClaimedAt: now.subtract(const Duration(minutes: 1)),
    buyerSubmittedUtr: '412345678999',
    verificationExpiresAt: verificationExpiresAt,
    expiresAt: now.subtract(const Duration(hours: 2)),
    createdAt: now.subtract(const Duration(hours: 3)),
    orderCode: orderCode,
    buyerName: 'Riya Sen',
  );
}

PaymentAttempt testAttempt({
  String id = 'attempt-1',
  String orderId = 'order-1',
  String orderCode = 'LD-AB12CD',
  int amountPaisa = 158000,
  PaymentAttemptStatus status = PaymentAttemptStatus.awaitingSellerVerification,
  DateTime? verificationExpiresAt,
  DateTime? claimedAt,
}) {
  return PaymentAttempt(
    id: id,
    orderId: orderId,
    paymentType: 'full',
    paymentMethod: 'upi',
    expectedAmountPaisa: amountPaisa,
    payeeVpaSnapshot: 'aarohi@okaxis',
    transactionReference: 'LD-$id',
    status: status,
    buyerClaimedAt: claimedAt ?? DateTime.now().subtract(const Duration(hours: 1)),
    buyerSubmittedUtr: '412345678901',
    verificationExpiresAt: verificationExpiresAt ?? DateTime.now().add(const Duration(hours: 20)),
    expiresAt: verificationExpiresAt ?? DateTime.now().add(const Duration(hours: 20)),
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    orderCode: orderCode,
    buyerName: 'Riya Sen',
  );
}

OwedRefund testRefund({
  String orderId = 'order-r',
  String code = 'LD-REFUND',
  int amountPaisa = 158000,
}) {
  return OwedRefund(
    orderId: orderId,
    dropId: 'drop-1',
    orderCode: code,
    buyerName: 'Meera Pal',
    buyerPhone: '9123456789',
    orderStatus: OrderStatus.cancelled,
    totalPaisa: 158000,
    totalPaidPaisa: amountPaisa,
    paymentStatus: OrderPaymentStatus.paid,
    refundStatus: RefundStatus.required,
    refundAmountPaisa: amountPaisa,
    refundReason: 'LATE_PAYMENT_INVENTORY_UNAVAILABLE',
    refundRequiredAt: DateTime.utc(2026, 10, 3, 9, 30),
  );
}

SellerOrder testOrder({
  String id = 'order-1',
  String code = 'LD-AB12CD',
  String dropId = 'drop-1',
  OrderStatus status = OrderStatus.pending,
  List<OrderPaymentAttemptSummary> attempts = const [],
  DateTime? holdExpiresAt,
}) {
  return SellerOrder(
    id: id,
    dropId: dropId,
    orderCode: code,
    buyerName: 'Riya Sen',
    buyerPhone: '9830012345',
    shippingAddress: '22 Ballygunge Place, Kolkata',
    pincode: '700019',
    subtotalPaisa: 150000,
    shippingPaisa: 8000,
    totalPaisa: 158000,
    status: status,
    confirmationMode: OrderConfirmationMode.fullPayment,
    advanceRequiredPaisa: 0,
    advancePaidPaisa: 0,
    totalPaidPaisa: 0,
    balanceDuePaisa: 158000,
    paymentStatus: OrderPaymentStatus.unpaid,
    fulfilmentStatus: OrderFulfilmentStatus.notReady,
    holdExpiresAt: holdExpiresAt ?? DateTime.now().add(const Duration(minutes: 14)),
    createdAt: DateTime.utc(2026, 10, 3, 9),
    items: const [
      SellerOrderItem(
        id: 'item-1',
        orderId: 'order-1',
        productId: 'p-1',
        priceAtPurchasePaisa: 150000,
        productCode: '#A01',
        productTitle: 'Kantha Stitch Saree',
      ),
    ],
    paymentAttempts: attempts,
  );
}

/// In-memory repository whose data the tests mutate between events.
class P0FakeRepo extends Fake implements SellerRepository {
  P0FakeRepo({
    List<SellerDrop>? drops,
    List<SellerProduct>? products,
    List<SellerOrder>? orders,
    List<PaymentAttempt>? attempts,
    List<OwedRefund>? refunds,
  })  : drops = drops ?? [testDrop()],
        products = products ?? [],
        orders = orders ?? [],
        attempts = attempts ?? [],
        refunds = refunds ?? [];

  List<SellerDrop> drops;
  List<SellerProduct> products;
  List<SellerOrder> orders;
  List<PaymentAttempt> attempts;
  List<OwedRefund> refunds;

  /// Response returned by [verifyManualUpiPayment] (or [verifyError] thrown).
  Map<String, dynamic> verifyResponse = {'success': true};
  Object? verifyError;
  Object? recordRefundError;
  Object? releaseError;

  /// Applied to the data when verify succeeds (e.g. a new refund appears).
  void Function()? onVerify;

  final Map<String, int> callCounts = {};
  final List<String> verifyCalls = [];
  final List<List<Object?>> refundCalls = [];
  final List<String> releaseCalls = [];

  int count(String name) => callCounts[name] ?? 0;
  void _hit(String name) => callCounts[name] = count(name) + 1;

  @override
  Future<SellerProfile> getProfile() async {
    _hit('getProfile');
    return testProfile;
  }

  @override
  Future<List<SellerDrop>> getDrops() async {
    _hit('getDrops');
    return List.of(drops);
  }

  @override
  Future<List<SellerProduct>> getProducts(String dropId) async {
    _hit('getProducts');
    return products.where((p) => p.dropId == dropId).toList();
  }

  @override
  Future<List<SellerOrder>> getAllOrders({String? dropId, String? status}) async {
    _hit('getAllOrders');
    return orders.where((o) => dropId == null || o.dropId == dropId).toList();
  }

  @override
  Future<List<PaymentAttempt>> getPendingVerifications() async {
    _hit('getPendingVerifications');
    return List.of(attempts);
  }

  @override
  Future<List<OwedRefund>> getRefundsOwed() async {
    _hit('getRefundsOwed');
    return List.of(refunds);
  }

  @override
  Future<List<SellerActivityItem>> getRecentActivity({String? dropId, int limit = 5}) async => const [];

  @override
  Future<Map<String, dynamic>> verifyManualUpiPayment(String paymentAttemptId, [String? overrideReference]) async {
    _hit('verifyManualUpiPayment');
    verifyCalls.add(paymentAttemptId);
    final error = verifyError;
    if (error != null) throw error;
    attempts = attempts.where((a) => a.id != paymentAttemptId).toList();
    onVerify?.call();
    return verifyResponse;
  }

  @override
  Future<Map<String, dynamic>> rejectManualUpiPayment(String paymentAttemptId, String rejectionReason,
      {bool releaseHold = true}) async {
    _hit('rejectManualUpiPayment');
    attempts = attempts.where((a) => a.id != paymentAttemptId).toList();
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> recordRefund(String orderId, String refundReference, {String? note}) async {
    _hit('recordRefund');
    refundCalls.add([orderId, refundReference, note]);
    final error = recordRefundError;
    if (error != null) throw error;
    refunds = refunds.where((r) => r.orderId != orderId).toList();
    return {'success': true, 'idempotent': false, 'order_id': orderId, 'refund_status': 'refunded'};
  }

  @override
  Future<bool> forceReleaseHold(String orderId) async {
    _hit('forceReleaseHold');
    releaseCalls.add(orderId);
    final error = releaseError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<String> uploadProductImage({
    required String dropId,
    required String fileName,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    _hit('uploadProductImage');
    return 'https://cdn.test/$dropId/$fileName';
  }

  @override
  Future<SellerProduct> createProduct({
    required String dropId,
    required String code,
    required String title,
    required int pricePaisa,
    required String size,
    required String imageUrl,
    List<String>? imageUrls,
  }) async {
    _hit('createProduct');
    final product = SellerProduct(
      id: 'srv-${count('createProduct')}',
      dropId: dropId,
      code: code,
      title: title,
      pricePaisa: pricePaisa,
      size: size,
      imageUrl: imageUrl,
      imageUrls: imageUrls ?? [imageUrl],
      status: ProductStatus.available,
      version: 1,
    );
    products = [...products, product];
    return product;
  }

  @override
  Future<SellerProduct?> findProductByCode({required String dropId, required String code}) async {
    _hit('findProductByCode');
    return products.where((p) => p.dropId == dropId && p.code == code).firstOrNull;
  }
}

SellerProduct testProduct({
  String id = 'p-1',
  String code = '#A01',
  String dropId = 'drop-1',
  ProductStatus status = ProductStatus.available,
}) {
  return SellerProduct(
    id: id,
    dropId: dropId,
    code: code,
    title: 'Kantha Saree $code',
    pricePaisa: 150000,
    size: 'Free Size',
    imageUrl: '',
    status: status,
    version: 1,
  );
}

/// Realtime transport double: tests push events and channel statuses.
class FakeLiveSource implements SellerLiveEventSource {
  SellerLiveEventHandler? _onEvent;
  SellerLiveStatusHandler? _onStatus;
  int openCount = 0;
  int closeCount = 0;

  bool get isOpen => _onEvent != null;

  @override
  void open({required SellerLiveEventHandler onEvent, required SellerLiveStatusHandler onStatus}) {
    openCount++;
    _onEvent = onEvent;
    _onStatus = onStatus;
  }

  @override
  Future<void> close() async {
    closeCount++;
    _onEvent = null;
    _onStatus = null;
  }

  void emit(SellerLiveEvent event) => _onEvent?.call(event);

  void status(SellerLiveTransportStatus status) => _onStatus?.call(status, null);

  void emitPaymentAttempt({String id = 'attempt-new'}) => emit(
        SellerLiveEvent(
          table: 'payment_attempts',
          change: SellerLiveChange.insert,
          newRecord: {'id': id, 'order_id': 'order-1', 'status': 'awaiting_seller_verification'},
        ),
      );

  void emitOrder({String dropId = 'drop-1', SellerLiveChange change = SellerLiveChange.update}) => emit(
        SellerLiveEvent(
          table: 'orders',
          change: change,
          newRecord: {'id': 'order-x', 'drop_id': dropId, 'status': 'pending'},
        ),
      );

  void emitProduct({required String dropId}) => emit(
        SellerLiveEvent(
          table: 'products',
          change: SellerLiveChange.update,
          newRecord: {'id': 'product-x', 'drop_id': dropId, 'status': 'reserved'},
        ),
      );
}

Widget testApp(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);
