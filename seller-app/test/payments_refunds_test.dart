// SA-PAY-003 / SA-PAY-004 (app side): Payments shows refunds owed, overdue
// claims first, warns before verifying a late claim and blocks on a
// refund_required verify response.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/pending_verifications_screen.dart';

import 'support/p0_fakes.dart';

Widget _payments(P0FakeRepo repo) => testApp(Scaffold(body: PendingVerificationsScreen(repository: repo)));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Refunds owed', () {
    testWidgets('the section lists amount, buyer, order code and reason at the top', (tester) async {
      final repo = P0FakeRepo(refunds: [testRefund()], attempts: [testAttempt(orderCode: 'LD-CLAIM1')]);
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      expect(find.text('Refunds owed (1)'), findsOneWidget);
      expect(find.text('#LD-REFUND'), findsOneWidget);
      expect(find.text('Meera Pal'), findsOneWidget);
      expect(find.text('₹1580 to refund'), findsOneWidget);
      expect(find.text('Late payment — the piece was no longer available when you verified it.'), findsOneWidget);
      expect(find.text('WhatsApp buyer'), findsOneWidget);
      expect(find.text('Mark refunded'), findsOneWidget);

      // Refunds come before the claims queue.
      final refundTop = tester.getTopLeft(find.text('#LD-REFUND')).dy;
      final claimTop = tester.getTopLeft(find.text('#LD-CLAIM1')).dy;
      expect(refundTop, lessThan(claimTop));
    });

    testWidgets('"Mark refunded" validates the reference like the RPC and records the refund', (tester) async {
      final repo = P0FakeRepo(refunds: [testRefund()]);
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      await tester.tap(find.text('Mark refunded'));
      await _settle(tester);
      expect(find.text('Mark #LD-REFUND refunded'), findsOneWidget);

      final referenceField = find.widgetWithText(TextFormField, 'Refund UPI reference (UTR)');
      await tester.enterText(referenceField, 'ab');
      await tester.tap(find.text('Save refund'));
      await _settle(tester);
      expect(find.textContaining('Enter 4–64 characters'), findsOneWidget);
      expect(repo.refundCalls, isEmpty);

      await tester.enterText(referenceField, 'UTR#123!');
      await tester.tap(find.text('Save refund'));
      await _settle(tester);
      expect(find.text('Use only letters, digits, spaces and . _ / -'), findsOneWidget);
      expect(repo.refundCalls, isEmpty);

      await tester.enterText(referenceField, '  412345678901  ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Note (optional)'), 'Sent via GPay');
      await tester.tap(find.text('Save refund'));
      await _settle(tester);

      expect(repo.refundCalls, [
        ['order-r', '412345678901', 'Sent via GPay'],
      ]);
      expect(find.text('Refund of ₹1580 recorded for #LD-REFUND.'), findsOneWidget);
      expect(find.text('#LD-REFUND'), findsNothing);
      expect(find.text('Refunds owed (1)'), findsNothing);
    });

    testWidgets('a record_refund error is shown as a friendly message', (tester) async {
      final repo = P0FakeRepo(refunds: [testRefund()])
        ..recordRefundError = const LiveDropException('No refund is due.', code: 'NO_REFUND_DUE');
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      await tester.tap(find.text('Mark refunded'));
      await _settle(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Refund UPI reference (UTR)'), 'UPI-REF/2026.10');
      await tester.tap(find.text('Save refund'));
      await _settle(tester);

      expect(find.textContaining('No refund is due on this order any more'), findsOneWidget);
      expect(find.textContaining('LiveDropException'), findsNothing);
      expect(find.text('#LD-REFUND'), findsOneWidget); // still owed
    });

    test('refund reference rule matches the record_refund RPC (4–64 chars, [A-Za-z0-9_./ -])', () {
      expect(SellerRepository.validateRefundReference('abc'), isNotNull);
      expect(SellerRepository.validateRefundReference('a' * 65), isNotNull);
      expect(SellerRepository.validateRefundReference('UTR#1234'), isNotNull);
      expect(SellerRepository.validateRefundReference(' 4123 4567 / ok_.- '), isNull);
    });

    test('OwedRefund parses the contract §11 projection and tolerates missing fields', () {
      final full = OwedRefund.fromJson({
        'id': 'o1',
        'drop_id': 'd1',
        'order_code': 'LD-AB12CD',
        'buyer_name': 'Riya Sen',
        'buyer_phone': '9830012345',
        'status': 'cancelled',
        'total_paisa': 250000,
        'total_paid_paisa': 25000,
        'payment_status': 'advance_paid',
        'refund_status': 'required',
        'refund_amount_paisa': 25000,
        'refund_reason': 'LATE_PAYMENT_INVENTORY_UNAVAILABLE',
        'refund_required_at': '2026-10-03T09:30:00+00:00',
        'refund_reference': null,
        'refunded_at': null,
        'created_at': '2026-10-02T09:30:00+00:00',
      });
      expect(full.refundAmountPaisa, 25000);
      expect(full.refundStatus, RefundStatus.required);
      expect(full.paymentStatus, OrderPaymentStatus.advancePaid);
      expect(full.refundRequiredAt, isNotNull);

      final sparse = OwedRefund.fromJson({'id': 'o2', 'order_code': 'LD-ZZ99ZZ'});
      expect(sparse.refundAmountPaisa, 0);
      expect(sparse.refundStatus, RefundStatus.none);
      expect(sparse.buyerName, 'Buyer');
    });
  });

  group('Verify', () {
    testWidgets('verify response with refund_required=true shows a blocking refund dialog, not a success snackbar',
        (tester) async {
      final late = testAttempt(
        id: 'late-1',
        orderId: 'order-late',
        orderCode: 'LD-LATE01',
        amountPaisa: 25000,
        status: PaymentAttemptStatus.lateClaimPendingReview,
      );
      final repo = P0FakeRepo(attempts: [late])
        ..verifyResponse = {
          'success': true,
          'idempotent': false,
          'is_late_claim': true,
          'inventory_available': false,
          'refund_required': true,
          'refund_amount_paisa': 25000,
          'order_id': 'order-late',
          'order_code': 'LD-LATE01',
        };
      repo.onVerify = () => repo.refunds = [testRefund(orderId: 'order-late', code: 'LD-LATE01', amountPaisa: 25000)];

      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      await tester.tap(find.text('Verify Payment'));
      await _settle(tester);
      // Late claim: the confirm dialog explains the refund risk first.
      expect(find.textContaining('you must refund ₹250 to the buyer'), findsOneWidget);
      await tester.tap(find.text('Confirm Receipt'));
      await _settle(tester);

      expect(repo.verifyCalls, ['late-1']);
      expect(find.text('Refund ₹250 to the buyer'), findsOneWidget);
      expect(find.textContaining('You must refund ₹250 to Riya Sen'), findsOneWidget);
      expect(find.textContaining('Payment verified for Order'), findsNothing);

      // Blocking: tapping outside does not dismiss it.
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester);
      expect(find.text('Refund ₹250 to the buyer'), findsOneWidget);

      await tester.tap(find.text('View refunds owed'));
      await _settle(tester);
      expect(find.text('Refund ₹250 to the buyer'), findsNothing);
      expect(find.text('Refunds owed (1)'), findsOneWidget);
      expect(find.text('#LD-LATE01'), findsOneWidget);
      expect(find.text('₹250 to refund'), findsOneWidget);
    });

    testWidgets('an on-time verify shows the usual success snackbar', (tester) async {
      final repo = P0FakeRepo(attempts: [testAttempt(orderCode: 'LD-OK0001')]);
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      await tester.tap(find.text('Verify Payment'));
      await _settle(tester);
      expect(find.textContaining('you must refund'), findsNothing); // only for late claims
      await tester.tap(find.text('Confirm Receipt'));
      await _settle(tester);
      expect(find.text('Payment verified for Order #LD-OK0001!'), findsOneWidget);
    });

    testWidgets('verify errors are mapped to friendly text', (tester) async {
      final repo = P0FakeRepo(attempts: [testAttempt()])
        ..verifyError = const LiveDropException('raw server text', code: 'INVENTORY_CONFLICT');
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      await tester.tap(find.text('Verify Payment'));
      await _settle(tester);
      await tester.tap(find.text('Confirm Receipt'));
      await _settle(tester);
      expect(find.textContaining('no longer reserved for this order'), findsOneWidget);
      expect(find.textContaining('LiveDropException'), findsNothing);
      expect(find.textContaining('raw server text'), findsNothing);
    });
  });

  group('Overdue claims (SA-PAY-003)', () {
    testWidgets('an overdue claim is labelled "Overdue — verify or reject" and sorted first', (tester) async {
      final onTime = testAttempt(
        id: 'on-time',
        orderCode: 'LD-ONTIME',
        claimedAt: DateTime.now().subtract(const Duration(hours: 30)),
        verificationExpiresAt: DateTime.now().add(const Duration(hours: 3)),
      );
      final overdue = testAttempt(
        id: 'overdue',
        orderCode: 'LD-OVERDU',
        claimedAt: DateTime.now().subtract(const Duration(hours: 2)),
        verificationExpiresAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      // Server order: oldest claim first (on-time first).
      final repo = P0FakeRepo(attempts: [onTime, overdue]);
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      expect(find.text('Overdue — verify or reject'), findsOneWidget);
      expect(find.textContaining('Verify within 2h'), findsOneWidget);
      final overdueTop = tester.getTopLeft(find.text('#LD-OVERDU')).dy;
      final onTimeTop = tester.getTopLeft(find.text('#LD-ONTIME')).dy;
      expect(overdueTop, lessThan(onTimeTop));
    });

    test('PaymentAttempt.isOverdue uses verification_expires_at and never applies to settled attempts', () {
      final now = DateTime.utc(2026, 10, 3, 12);
      final claim = PaymentAttempt.fromJson({
        'id': 'a1',
        'order_id': 'o1',
        'payment_type': 'advance',
        'expected_amount_paisa': 25000,
        'payee_vpa_snapshot': 'aarohi@okaxis',
        'transaction_reference': 'LD-X',
        'status': 'awaiting_seller_verification',
        'verification_expires_at': '2026-10-03T11:00:00+00:00',
        'expires_at': '2026-10-03T11:00:00+00:00',
        'created_at': '2026-10-02T11:00:00+00:00',
      });
      expect(claim.isOverdue(now), isTrue);
      final older = PaymentAttempt.fromJson({
        'id': 'a2',
        'order_id': 'o1',
        'payment_type': 'advance',
        'expected_amount_paisa': 25000,
        'payee_vpa_snapshot': 'aarohi@okaxis',
        'transaction_reference': 'LD-Y',
        'status': 'buyer_claimed',
        'expires_at': '2026-10-03T13:00:00+00:00', // no verification_expires_at on older rows
        'created_at': '2026-10-02T11:00:00+00:00',
      });
      expect(older.verificationExpiresAt, isNull);
      expect(older.isOverdue(now), isFalse);
      final verified = PaymentAttempt.fromJson({
        'id': 'a3',
        'order_id': 'o1',
        'payment_type': 'advance',
        'expected_amount_paisa': 25000,
        'payee_vpa_snapshot': 'aarohi@okaxis',
        'transaction_reference': 'LD-Z',
        'status': 'verified',
        'verification_expires_at': '2026-10-03T11:00:00+00:00',
        'expires_at': '2026-10-03T11:00:00+00:00',
        'created_at': '2026-10-02T11:00:00+00:00',
      });
      expect(verified.isOverdue(now), isFalse);
    });

    Map<String, dynamic> claimRow({
      required String status,
      required String claimedAt,
      String? verificationExpiresAt,
      required String expiresAt,
    }) =>
        {
          'id': 'a-$status',
          'order_id': 'o1',
          'payment_type': 'full',
          'expected_amount_paisa': 158000,
          'payee_vpa_snapshot': 'aarohi@okaxis',
          'transaction_reference': 'LD-L',
          'status': status,
          'buyer_claimed_at': claimedAt,
          'buyer_submitted_utr': '412345678999',
          'verification_expires_at': verificationExpiresAt,
          'expires_at': expiresAt,
          'created_at': '2026-10-03T09:00:00+00:00',
        };

    test('a fresh late claim (verification_expires_at NULL, expires_at past) is not overdue', () {
      // Exactly what the late path of submit_buyer_payment_claim writes
      // (023_late_upi_recovery.sql): claimed 1 min ago, no verification window.
      final now = DateTime.utc(2026, 10, 3, 12);
      final late = PaymentAttempt.fromJson(claimRow(
        status: 'late_claim_pending_review',
        claimedAt: '2026-10-03T11:59:00+00:00',
        expiresAt: '2026-10-03T10:00:00+00:00',
      ));
      expect(late.isLateClaim, isTrue);
      expect(late.verificationExpiresAt, isNull);
      expect(late.verificationDeadline, isNull, reason: 'expires_at is the payment window, never the verification window');
      expect(late.isOverdue(now), isFalse);
      expect(late.isOverdue(now.add(const Duration(days: 3))), isFalse);
    });

    test('an older claim row without verification_expires_at is never overdue via expires_at', () {
      final now = DateTime.utc(2026, 10, 3, 12);
      final older = PaymentAttempt.fromJson(claimRow(
        status: 'buyer_claimed',
        claimedAt: '2026-10-03T08:00:00+00:00',
        expiresAt: '2026-10-03T09:00:00+00:00', // payment window already over
      ));
      expect(older.verificationDeadline, isNull);
      expect(older.isOverdue(now), isFalse);
    });

    test('a late claim keeping a window from an earlier claim (ended before this claim) is not overdue', () {
      final now = DateTime.utc(2026, 10, 3, 12);
      final stale = PaymentAttempt.fromJson(claimRow(
        status: 'late_claim_pending_review',
        claimedAt: '2026-10-03T11:59:00+00:00',
        verificationExpiresAt: '2026-10-02T20:00:00+00:00', // window of an earlier claim
        expiresAt: '2026-10-02T20:00:00+00:00',
      ));
      expect(stale.verificationDeadline, isNull);
      expect(stale.isOverdue(now), isFalse);
    });

    test('a late claim whose own verification window has passed is overdue', () {
      // e.g. a claim routed to late review by migration 035 §1.2: it keeps the
      // 24 h window it got when it was claimed, and that window is over.
      final now = DateTime.utc(2026, 10, 3, 12);
      final overdue = PaymentAttempt.fromJson(claimRow(
        status: 'late_claim_pending_review',
        claimedAt: '2026-10-02T09:00:00+00:00',
        verificationExpiresAt: '2026-10-03T09:00:00+00:00',
        expiresAt: '2026-10-03T09:00:00+00:00',
      ));
      expect(overdue.verificationDeadline, DateTime.parse('2026-10-03T09:00:00+00:00'));
      expect(overdue.isOverdue(now), isTrue);
    });

    testWidgets('a late claim submitted a minute ago is not labelled overdue nor sorted first', (tester) async {
      final onTime = testAttempt(
        id: 'on-time',
        orderCode: 'LD-ONTIME',
        claimedAt: DateTime.now().subtract(const Duration(hours: 3)),
        verificationExpiresAt: DateTime.now().add(const Duration(hours: 21)),
      );
      final late = freshLateClaim(orderCode: 'LD-LATE01');
      // Server order: oldest claim first (on-time first).
      final repo = P0FakeRepo(attempts: [onTime, late]);
      await tester.pumpWidget(_payments(repo));
      await _settle(tester);

      expect(find.text('Late Claim'), findsOneWidget);
      expect(find.text('Overdue — verify or reject'), findsNothing);
      final onTimeTop = tester.getTopLeft(find.text('#LD-ONTIME')).dy;
      final lateTop = tester.getTopLeft(find.text('#LD-LATE01')).dy;
      expect(onTimeTop, lessThan(lateTop), reason: 'server order kept; the late claim is not promoted as overdue');
    });
  });
}
