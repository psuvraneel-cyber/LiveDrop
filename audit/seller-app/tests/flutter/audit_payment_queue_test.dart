// AUDIT-ONLY tests for PendingVerificationsScreen (seller-app/lib/presentation/pending_verifications_screen.dart)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/pending_verifications_screen.dart';

import 'audit_fakes.dart';

Widget _screen(AuditRepo repo) => auditApp(Scaffold(body: PendingVerificationsScreen(repository: repo)));

void main() {
  // SA-PAY-009 fixed: inverted. The label follows payment_type.
  testWidgets('SA-AUD-T09: a FULL payment claim is labelled "Full payment" (and an advance "Advance payment")',
      (tester) async {
    final repo = AuditRepo(attempts: [
      auditAttempt(paymentType: 'full', amountPaisa: 158000),
      auditAttempt(id: 'attempt-2', paymentType: 'advance', amountPaisa: 25000, orderTotalPaisa: 158000),
    ]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    expect(find.text('₹1580 Full payment'), findsOneWidget);
    expect(find.text('₹250 Advance payment of ₹1580'), findsOneWidget);
    expect(find.textContaining('Advance Payment'), findsNothing);
  });

  // SA-UX-002 fixed: inverted. The "Remarks" field, which was never sent, is gone.
  testWidgets('SA-AUD-T10: no "Remarks" field that is silently dropped', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt()]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Remarks (optional)'), findsNothing);
    await tester.tap(find.text('Verify Payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Receipt'));
    await tester.pumpAndSettle();
    expect(repo.verifyCalls, hasLength(1));
  });

  // SA-PAY-010 fixed: inverted. The seller chooses: ask the buyer to fix (keep hold) or reject & release.
  testWidgets('SA-AUD-T11: rejecting a claim offers "Ask buyer to fix (keep piece)" and calls releaseHold:false',
      (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt(orderStatus: 'pending')]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Reject & release piece'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reject-keep-hold')));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('AUDIT T11 reject calls: ${repo.rejectCalls}');
    expect(repo.rejectCalls.single['releaseHold'], isFalse);
  });

  // SA-PAY-009 / SA-UX-002 fixed: inverted. No fake "screenshot" any more.
  testWidgets('SA-AUD-T12: no "Screenshot: Tap to view" placeholder', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt()]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    expect(find.text('Tap to view'), findsNothing);
    expect(find.text('Google Pay / PhonePe UPI Receipt'), findsNothing);
  });

  // SA-PAY-009 fixed: inverted. The card names the piece and says what verifying a late claim does.
  testWidgets('SA-AUD-T13: verification card shows the piece and the late-claim consequence', (tester) async {
    final repo = AuditRepo(attempts: [
      auditAttempt(
        status: PaymentAttemptStatus.lateClaimPendingReview,
        orderStatus: 'cancelled',
        pieces: const [ClaimPiece(code: '#A01', title: 'Kantha Saree', status: 'sold')],
      ),
    ]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    expect(find.text('Late Claim'), findsOneWidget);
    expect(find.text('#A01'), findsOneWidget);
    expect(find.textContaining('you will owe the buyer a refund'), findsOneWidget);
  });
}
