// P1 round 4b: payments, orders, labels and placeholder controls
// (SA-PAY-009/010/013, SA-ORD-004/005, SA-SHIP-002, SA-UX-002).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/core/services/pdf_label_service.dart';
import 'package:seller_app/core/theme/boutique_haptics.dart';
import 'package:seller_app/core/utils/payment_reminder.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/order_actions.dart';
import 'package:seller_app/presentation/orders/order_card.dart';
import 'package:seller_app/presentation/pending_verifications_screen.dart';

import 'support/p0_fakes.dart';

SellerOrder _order({
  OrderStatus status = OrderStatus.pending,
  OrderPaymentStatus payment = OrderPaymentStatus.unpaid,
  OrderFulfilmentStatus fulfilment = OrderFulfilmentStatus.notReady,
  OrderConfirmationMode mode = OrderConfirmationMode.fullPayment,
  int total = 258000,
  int advanceRequired = 0,
  int advancePaid = 0,
  int totalPaid = 0,
  int? balanceDue,
  String? token = 'tok-123',
  RefundStatus refund = RefundStatus.none,
  int refundAmount = 0,
  List<OrderPaymentAttemptSummary> attempts = const [],
}) =>
    SellerOrder(
      id: 'order-1',
      dropId: 'drop-1',
      orderCode: 'LD-AB12CD',
      buyerName: 'Riya Sen',
      buyerPhone: '9830012345',
      shippingAddress: '22 Ballygunge Place, Kolkata',
      pincode: '700019',
      subtotalPaisa: total,
      shippingPaisa: 0,
      totalPaisa: total,
      status: status,
      confirmationMode: mode,
      advanceRequiredPaisa: advanceRequired,
      advancePaidPaisa: advancePaid,
      totalPaidPaisa: totalPaid,
      balanceDuePaisa: balanceDue ?? (total - totalPaid),
      paymentStatus: payment,
      fulfilmentStatus: fulfilment,
      createdAt: DateTime.utc(2026, 10, 3, 9),
      items: const [],
      orderToken: token,
      refundStatus: refund,
      refundAmountPaisa: refundAmount,
      paymentAttempts: attempts,
    );

final _paid = _order(status: OrderStatus.paid, payment: OrderPaymentStatus.paid, totalPaid: 258000);

class _Repo extends P0FakeRepo {
  _Repo({super.attempts});

  final List<bool> rejectReleaseHold = [];

  @override
  Future<Map<String, dynamic>> rejectManualUpiPayment(String paymentAttemptId, String rejectionReason,
      {bool releaseHold = true}) async {
    rejectReleaseHold.add(releaseHold);
    attempts = attempts.where((a) => a.id != paymentAttemptId).toList();
    return {'success': true, 'hold_released': releaseHold};
  }
}

PaymentAttempt _claim({
  String type = 'full',
  int amount = 258000,
  int? orderTotal,
  PaymentAttemptStatus status = PaymentAttemptStatus.awaitingSellerVerification,
  String orderStatus = 'pending',
  List<ClaimPiece> pieces = const [ClaimPiece(code: '#A01', title: 'Kantha Saree', status: 'reserved', heldByOrderId: 'order-1')],
}) =>
    PaymentAttempt(
      id: 'claim-1',
      orderId: 'order-1',
      paymentType: type,
      paymentMethod: 'upi',
      expectedAmountPaisa: amount,
      payeeVpaSnapshot: 'aarohi@okaxis',
      transactionReference: 'LD-AB12CD-FUL-1A2B',
      status: status,
      buyerClaimedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      buyerSubmittedUtr: '412345678901',
      verificationExpiresAt: DateTime.now().add(const Duration(minutes: 28)),
      expiresAt: DateTime.now().add(const Duration(minutes: 28)),
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      orderCode: 'LD-AB12CD',
      buyerName: 'Riya Sen',
      buyerPhone: '9830012345',
      orderToken: 'tok-123',
      orderStatus: orderStatus,
      orderTotalPaisa: orderTotal,
      pieces: pieces,
    );

void main() {
  group('PaymentReminder (SA-PAY-013)', () {
    test('an advance order asks for the advance, links the order page, never shows the UPI ID', () {
      final msg = PaymentReminder.message(
        _order(mode: OrderConfirmationMode.advance, advanceRequired: 25000),
        storeName: 'Aarohi Boutique',
      )!;
      expect(msg, contains('an advance of ₹250 to confirm it (order total ₹2580)'));
      expect(msg, contains('/order/order-1?token=tok-123'));
      expect(msg, isNot(contains('aarohi@okaxis')));
    });

    test('a full-payment order asks for the total; a confirmed order asks for the balance', () {
      expect(PaymentReminder.message(_order(), storeName: 'A')!, contains('waiting for ₹2580.'));
      final confirmed = _order(
        status: OrderStatus.confirmed,
        payment: OrderPaymentStatus.advancePaid,
        mode: OrderConfirmationMode.advance,
        advanceRequired: 25000,
        advancePaid: 25000,
        totalPaid: 25000,
      );
      expect(PaymentReminder.message(confirmed, storeName: 'A')!, contains('the balance of ₹2330'));
    });

    test('nothing due means no reminder; no token means no link', () {
      expect(PaymentReminder.message(_paid, storeName: 'A'), isNull);
      expect(PaymentReminder.message(_order(token: null), storeName: 'A')!, isNot(contains('token=')));
    });
  });

  group('OrderActions follow the server state machine (SA-ORD-005)', () {
    final cases = <String, (SellerOrder, List<OrderAction>)>{
      'pending, unpaid': (_order(), [OrderAction.remindPayment, OrderAction.releaseHold]),
      'pending with a buyer claim': (
        _order(attempts: [OrderPaymentAttemptSummary.tryParse({'id': 'a', 'status': 'awaiting_seller_verification'})!]),
        [OrderAction.remindPayment],
      ),
      'advance paid, balance due': (
        _order(status: OrderStatus.confirmed, payment: OrderPaymentStatus.advancePaid, totalPaid: 25000),
        [OrderAction.collectBalance],
      ),
      'fully paid, not packed': (_paid, [OrderAction.markPacked]),
      'packed': (
        _order(status: OrderStatus.paid, payment: OrderPaymentStatus.paid, totalPaid: 258000, fulfilment: OrderFulfilmentStatus.readyToShip),
        [OrderAction.dispatch, OrderAction.printLabel],
      ),
      'shipped': (
        _order(status: OrderStatus.shipped, payment: OrderPaymentStatus.paid, totalPaid: 258000, fulfilment: OrderFulfilmentStatus.shipped),
        [OrderAction.reprintLabel],
      ),
      'cancelled': (_order(status: OrderStatus.cancelled), <OrderAction>[]),
      'expired': (_order(status: OrderStatus.expired), <OrderAction>[]),
    };
    cases.forEach((name, c) {
      test(name, () => expect(OrderActions.forOrder(c.$1), c.$2));
    });

    test('closed orders explain why', () {
      expect(OrderActions.closedReason(_order(status: OrderStatus.cancelled)), contains('went back on sale'));
      expect(
        OrderActions.closedReason(_order(status: OrderStatus.cancelled, refund: RefundStatus.required, refundAmount: 158000)),
        contains('Refund owed: ₹1580'),
      );
      expect(
        OrderActions.closedReason(_order(status: OrderStatus.expired, advancePaid: 25000)),
        contains('advance was kept'),
      );
    });
  });

  group('Shipping label (SA-SHIP-002)', () {
    test('no label while anything is due or for a closed order', () {
      expect(PdfLabelService.labelBlockedReason(_order()), isNotNull);
      expect(
        PdfLabelService.labelBlockedReason(_order(status: OrderStatus.confirmed, payment: OrderPaymentStatus.advancePaid, totalPaid: 25000)),
        contains('not fully paid'),
      );
      expect(PdfLabelService.labelBlockedReason(_order(status: OrderStatus.cancelled)), isNotNull);
      expect(PdfLabelService.labelBlockedReason(_paid), isNull);
    });

    test('generating a label for an unpaid order throws instead of printing PREPAID', () async {
      await expectLater(
        const PdfLabelService().generateShippingLabel(order: _order(), profile: testProfile),
        throwsA(isA<LiveDropException>().having((e) => e.code, 'code', 'LABEL_NOT_ALLOWED')),
      );
    });

    test('a barcode only for a real AWB', () {
      expect(PdfLabelService.barcodeData(_paid), isNull);
      expect(PdfLabelService.barcodeData(_paid, trackingNumber: ' 1234567890 '), '1234567890');
    });
  });

  group('Order card', () {
    testWidgets('an advance-paid order offers "Ask for balance" and no Dispatch (SA-ORD-005)', (tester) async {
      final order = _order(status: OrderStatus.confirmed, payment: OrderPaymentStatus.advancePaid, totalPaid: 25000);
      await tester.pumpWidget(testApp(Scaffold(body: SingleChildScrollView(child: OrderCard(
        order: order, profile: testProfile, repository: _Repo(), onOrderUpdated: () {},
      )))));
      await tester.pump();
      expect(find.text('Ask for balance'), findsOneWidget);
      expect(find.text('Dispatch'), findsNothing);
      expect(find.text('Mark packed'), findsNothing);
    });

    testWidgets('a refund-owed cancelled order says so instead of "Paid" (SA-ORD-004)', (tester) async {
      final order = _order(status: OrderStatus.cancelled, payment: OrderPaymentStatus.paid, totalPaid: 158000,
          refund: RefundStatus.required, refundAmount: 158000);
      await tester.pumpWidget(testApp(Scaffold(body: SingleChildScrollView(child: OrderCard(
        order: order, profile: testProfile, repository: _Repo(), onOrderUpdated: () {},
      )))));
      await tester.pump();
      expect(find.text('Refund owed'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
      expect(find.byKey(const Key('order-closed-reason')), findsOneWidget);
    });
  });

  group('Payment claim card (SA-PAY-009, SA-PAY-010)', () {
    testWidgets('shows type, piece, buyer phone and deadline; no fake screenshot or remarks', (tester) async {
      final repo = _Repo(attempts: [_claim(type: 'advance', amount: 25000, orderTotal: 258000)]);
      await tester.pumpWidget(testApp(Scaffold(body: PendingVerificationsScreen(repository: repo))));
      await tester.pumpAndSettle();
      expect(find.text('₹250 Advance payment of ₹2580'), findsOneWidget);
      expect(find.text('#A01'), findsOneWidget);
      expect(find.textContaining('9830012345'), findsOneWidget);
      expect(find.textContaining('Verify within'), findsOneWidget);
      expect(find.text('Tap to view'), findsNothing);
      expect(find.text('Remarks (optional)'), findsNothing);
    });

    testWidgets('a late claim whose piece is still free says verifying confirms the order again', (tester) async {
      final repo = _Repo(attempts: [
        _claim(status: PaymentAttemptStatus.lateClaimPendingReview, orderStatus: 'cancelled',
            pieces: const [ClaimPiece(code: '#A01', status: 'available')]),
      ]);
      await tester.pumpWidget(testApp(Scaffold(body: PendingVerificationsScreen(repository: repo))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Verifying confirms the order again'), findsOneWidget);
    });

    testWidgets('reject offers keep-hold and reject-and-release; each calls the right releaseHold', (tester) async {
      final repo = _Repo(attempts: [_claim()]);
      await tester.pumpWidget(testApp(Scaffold(body: PendingVerificationsScreen(repository: repo))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reject-release')));
      await tester.pumpAndSettle();
      expect(repo.rejectReleaseHold, [true]);
    });

    testWidgets('a late claim has no keep-hold choice (its order is already cancelled)', (tester) async {
      final repo = _Repo(attempts: [_claim(status: PaymentAttemptStatus.lateClaimPendingReview, orderStatus: 'cancelled')]);
      await tester.pumpWidget(testApp(Scaffold(body: PendingVerificationsScreen(repository: repo))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reject-keep-hold')), findsNothing);
      expect(find.text('Reject claim'), findsOneWidget);
    });
  });

  test('the haptics switch really turns haptics off (SA-UX-002)', () {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      BoutiqueHaptics.enabled = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    BoutiqueHaptics.enabled = false;
    BoutiqueHaptics.light();
    BoutiqueHaptics.heavy();
    expect(calls.where((c) => c.method == 'HapticFeedback.vibrate'), isEmpty);
    BoutiqueHaptics.enabled = true;
    BoutiqueHaptics.light();
    expect(calls.where((c) => c.method == 'HapticFeedback.vibrate'), isNotEmpty);
  });
}
