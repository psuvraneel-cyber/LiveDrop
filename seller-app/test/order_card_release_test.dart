// SA-PAY-005 (app side): orders know about buyer payment claims; Release is
// hidden while a claim exists and release errors are shown as friendly text.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/core/errors/seller_error_messages.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/order_card.dart';

import 'support/p0_fakes.dart';

Widget _card(SellerOrder order, P0FakeRepo repo, {VoidCallback? onUpdated}) => testApp(
      Scaffold(
        body: SingleChildScrollView(
          child: OrderCard(
            order: order,
            profile: testProfile,
            repository: repo,
            onOrderUpdated: onUpdated ?? () {},
          ),
        ),
      ),
    );

const _claim = OrderPaymentAttemptSummary(
  id: 'attempt-1',
  status: PaymentAttemptStatus.awaitingSellerVerification,
  buyerSubmittedUtr: '412345678901',
);

void main() {
  testWidgets('Release is hidden while the buyer has a payment claim; the card points to Payments', (tester) async {
    await tester.pumpWidget(_card(testOrder(attempts: const [_claim]), P0FakeRepo()));
    await tester.pump();

    expect(find.text('Release'), findsNothing);
    expect(
      find.text('Payment claim pending (UTR 412345678901) — verify or reject it in Payments.'),
      findsOneWidget,
    );
    expect(find.textContaining('Hold Expires in:'), findsNothing);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('Release is shown when there is no claim (expired/created attempts do not count)', (tester) async {
    const unclaimed = OrderPaymentAttemptSummary(id: 'attempt-0', status: PaymentAttemptStatus.awaitingPayment);
    const expired = OrderPaymentAttemptSummary(id: 'attempt-x', status: PaymentAttemptStatus.expired);
    await tester.pumpWidget(_card(testOrder(attempts: const [unclaimed, expired]), P0FakeRepo()));
    await tester.pump();

    expect(find.text('Release'), findsOneWidget);
    expect(find.textContaining('Hold Expires in:'), findsOneWidget);
  });

  testWidgets('the release dialog says the piece returns to sale; PAYMENT_CLAIM_PENDING becomes a friendly message',
      (tester) async {
    var refreshed = 0;
    final repo = P0FakeRepo()
      ..releaseError = const LiveDropException(
        'The buyer has already submitted a payment for this order.',
        code: 'PAYMENT_CLAIM_PENDING',
      );
    await tester.pumpWidget(_card(testOrder(), repo, onUpdated: () => refreshed++));
    await tester.pump();

    await tester.tap(find.text('Release'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // countdown timer: no pumpAndSettle
    expect(find.textContaining('returns its piece to sale'), findsOneWidget);

    await tester.tap(find.text('Release Inventory Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.releaseCalls, ['order-1']);
    expect(
      find.text('The buyer has already submitted a payment for this order. '
          'Verify or reject it in Payments before releasing the piece.'),
      findsOneWidget,
    );
    expect(find.textContaining('LiveDropException'), findsNothing);
    expect(refreshed, 1, reason: 'card refreshes so the claim shows and Release hides');
  });

  test('release errors never surface raw exception text', () {
    expect(
      SellerErrorMessages.releaseHold(const LiveDropException('x', code: 'ONLY_PENDING_CAN_BE_RELEASED')),
      contains('Only orders still waiting for payment can be released'),
    );
    expect(
      SellerErrorMessages.releaseHold(const LiveDropException('x', code: 'ORDER_NOT_FOUND_OR_UNAUTHORIZED')),
      contains('could not be found'),
    );
    expect(SellerErrorMessages.releaseHold(const UnauthorizedException()), contains('sign in again'));
    expect(SellerErrorMessages.releaseHold(const SocketException('down')), contains('No connection'));
    final generic = SellerErrorMessages.releaseHold(Exception('PostgrestException(message: boom)'));
    expect(generic, 'Could not release the hold right now. Please try again.');
  });

  test('orders parse embedded payment_attempts and optional refund fields (older rows keep defaults)', () {
    final base = <String, dynamic>{
      'id': 'o1',
      'drop_id': 'd1',
      'order_code': 'LD-AB12CD',
      'buyer_name': 'Riya Sen',
      'buyer_phone': '9830012345',
      'shipping_address': '22 Ballygunge Place',
      'pincode': '700019',
      'subtotal_paisa': 150000,
      'shipping_paisa': 8000,
      'total_paisa': 158000,
      'status': 'pending',
      'created_at': '2026-10-03T09:00:00+00:00',
    };

    final legacy = SellerOrder.fromJson(base);
    expect(legacy.paymentAttempts, isEmpty);
    expect(legacy.hasPendingPaymentClaim, isFalse);
    expect(legacy.refundStatus, RefundStatus.none);
    expect(legacy.refundAmountPaisa, 0);

    final withClaim = SellerOrder.fromJson({
      ...base,
      'payment_attempts': [
        {'id': 'pa-1', 'status': 'expired', 'buyer_submitted_utr': null},
        {'id': 'pa-2', 'status': 'late_claim_pending_review', 'buyer_submitted_utr': 'UTR998877'},
        {'bad': 'row'},
      ],
      'refund_status': 'required',
      'refund_amount_paisa': 25000,
      'refund_reason': 'LATE_PAYMENT_INVENTORY_UNAVAILABLE',
      'refund_required_at': '2026-10-03T10:00:00+00:00',
    });
    expect(withClaim.paymentAttempts, hasLength(2));
    expect(withClaim.hasPendingPaymentClaim, isTrue);
    expect(withClaim.pendingPaymentClaim!.buyerSubmittedUtr, 'UTR998877');
    expect(withClaim.isRefundOwed, isTrue);
    expect(withClaim.refundAmountPaisa, 25000);
    expect(withClaim.refundRequiredAt, isNotNull);
  });
}
