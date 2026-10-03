// LiveDrop Seller-App Audit — shared fakes for audit-only widget/unit tests.
// AUDIT-ONLY: these files are copied into a scratch copy of seller-app/test/audit
// by run_flutter_audit_tests.sh. They never modify application code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:seller_app/core/theme/app_theme.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const auditProfile = SellerProfile(
  id: '11111111-1111-1111-1111-111111111111',
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

SellerOrder auditOrder({
  String id = 'order-1',
  String code = 'LD-AB12CD',
  String buyerName = 'Riya Sen',
  String buyerPhone = '9830012345',
  OrderStatus status = OrderStatus.pending,
  OrderPaymentStatus paymentStatus = OrderPaymentStatus.unpaid,
  OrderFulfilmentStatus fulfilmentStatus = OrderFulfilmentStatus.notReady,
  int totalPaisa = 158000,
  int totalPaidPaisa = 0,
  DateTime? createdAt,
  DateTime? holdExpiresAt,
}) {
  return SellerOrder(
    id: id,
    dropId: 'drop-1',
    orderCode: code,
    buyerName: buyerName,
    buyerPhone: buyerPhone,
    shippingAddress: '22 Ballygunge Place, Kolkata',
    pincode: '700019',
    subtotalPaisa: totalPaisa - 8000,
    shippingPaisa: 8000,
    totalPaisa: totalPaisa,
    status: status,
    confirmationMode: OrderConfirmationMode.fullPayment,
    advanceRequiredPaisa: 0,
    advancePaidPaisa: 0,
    totalPaidPaisa: totalPaidPaisa,
    balanceDuePaisa: totalPaisa - totalPaidPaisa,
    paymentStatus: paymentStatus,
    fulfilmentStatus: fulfilmentStatus,
    holdExpiresAt: holdExpiresAt,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 3, 9, 0),
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
  );
}

PaymentAttempt auditAttempt({
  String id = 'attempt-1',
  String paymentType = 'full',
  int amountPaisa = 158000,
  PaymentAttemptStatus status = PaymentAttemptStatus.awaitingSellerVerification,
}) {
  return PaymentAttempt(
    id: id,
    orderId: 'order-1',
    paymentType: paymentType,
    paymentMethod: 'upi',
    expectedAmountPaisa: amountPaisa,
    payeeVpaSnapshot: 'aarohi@okaxis',
    transactionReference: 'LD-AB12CD-FUL-1A2B',
    status: status,
    buyerClaimedAt: DateTime.utc(2026, 10, 3, 9, 5),
    buyerSubmittedUtr: '412345678901',
    expiresAt: DateTime.utc(2026, 10, 4, 9, 5),
    createdAt: DateTime.utc(2026, 10, 3, 9, 0),
    orderCode: 'LD-AB12CD',
    buyerName: 'Riya Sen',
  );
}

OwedRefund auditRefund({
  String orderId = 'o-refund',
  String code = 'LD-REFUND',
  int amountPaisa = 158000,
}) {
  return OwedRefund(
    orderId: orderId,
    dropId: 'drop-1',
    orderCode: code,
    buyerName: 'Riya Sen',
    buyerPhone: '9830012345',
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

/// Records every mutating call so tests can assert what the UI actually sends.
class AuditRepo extends Fake implements SellerRepository {
  AuditRepo({
    this.profile = auditProfile,
    this.profileError,
    this.drops = const [],
    this.products = const [],
    this.orders = const [],
    this.attempts = const [],
    this.refunds = const [],
  });

  final SellerProfile profile;
  final Object? profileError;
  final List<SellerDrop> drops;
  final List<SellerProduct> products;
  final List<SellerOrder> orders;
  final List<PaymentAttempt> attempts;
  final List<OwedRefund> refunds;

  final List<String> calls = [];
  final List<Map<String, Object?>> shipCalls = [];
  final List<Map<String, Object?>> rejectCalls = [];
  final List<List<Object?>> verifyCalls = [];
  final List<List<Object?>> refundCalls = [];

  @override
  Future<List<OwedRefund>> getRefundsOwed() async => refunds;

  @override
  Future<Map<String, dynamic>> recordRefund(String orderId, String refundReference, {String? note}) async {
    refundCalls.add([orderId, refundReference, note]);
    return {'success': true, 'idempotent': false, 'order_id': orderId, 'refund_status': 'refunded'};
  }

  @override
  Future<SellerProfile> getProfile() async {
    calls.add('getProfile');
    if (profileError != null) throw profileError!;
    return profile;
  }

  @override
  Future<List<SellerDrop>> getDrops() async => drops;

  @override
  Future<List<SellerProduct>> getProducts(String dropId) async => products;

  @override
  Future<List<SellerOrder>> getAllOrders({String? dropId, String? status}) async {
    calls.add('getAllOrders');
    return orders;
  }

  @override
  Future<List<PaymentAttempt>> getPendingVerifications() async => attempts;

  @override
  Future<List<SellerActivityItem>> getRecentActivity({String? dropId, int limit = 5}) async => const [];

  @override
  Future<Map<String, dynamic>> verifyManualUpiPayment(String paymentAttemptId, [String? overrideReference]) async {
    verifyCalls.add([paymentAttemptId, overrideReference]);
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> rejectManualUpiPayment(String paymentAttemptId, String rejectionReason,
      {bool releaseHold = true}) async {
    rejectCalls.add({'id': paymentAttemptId, 'reason': rejectionReason, 'releaseHold': releaseHold});
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> markOrderShipped({
    required String orderId,
    required String trackingNumber,
    required String courierPartner,
    String? notes,
  }) async {
    shipCalls.add({'orderId': orderId, 'tracking': trackingNumber, 'courier': courierPartner});
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> markOrderReadyToShip(String orderId) async {
    calls.add('markOrderReadyToShip:$orderId');
    return {'success': true};
  }
}

/// Captures URLs the app tries to open (WhatsApp, dialer, browser).
class RecordingLauncher extends Fake with MockPlatformInterfaceMixin implements UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> launch(String url,
      {required bool useSafariVC,
      required bool useWebView,
      required bool enableJavaScript,
      required bool enableDomStorage,
      required bool universalLinksOnly,
      required Map<String, String> headers,
      String? webOnlyWindowName}) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
}

Widget auditApp(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);
