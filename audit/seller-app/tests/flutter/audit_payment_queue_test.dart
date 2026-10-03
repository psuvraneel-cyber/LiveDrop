// AUDIT-ONLY tests for PendingVerificationsScreen (seller-app/lib/presentation/pending_verifications_screen.dart)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/pending_verifications_screen.dart';

import 'audit_fakes.dart';

Widget _screen(AuditRepo repo) => auditApp(Scaffold(body: PendingVerificationsScreen(repository: repo)));

void main() {
  testWidgets('SA-AUD-T09: a FULL payment claim is labelled "Advance Payment"', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt(paymentType: 'full', amountPaisa: 158000)]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    expect(find.text('₹1580 Advance Payment'), findsOneWidget);
  });

  testWidgets('SA-AUD-T10: "Remarks" typed by the seller are never sent to the server', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt()]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Remarks (optional)'), 'Matched in HDFC statement 14:05');
    await tester.tap(find.text('Verify Payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Receipt'));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('AUDIT T10 verify calls: ${repo.verifyCalls}');
    expect(repo.verifyCalls, hasLength(1));
    expect(repo.verifyCalls.first, equals(['attempt-1', null])); // remark dropped
  });

  testWidgets('SA-AUD-T11: rejecting a claim always releases the reserved garment (no "keep hold" option)', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt()]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.textContaining('release'), findsNothing); // dialog never mentions releasing stock
    await tester.tap(find.text('Reject Claim'));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('AUDIT T11 reject calls: ${repo.rejectCalls}');
    expect(repo.rejectCalls.single['releaseHold'], isTrue);
  });

  testWidgets('SA-AUD-T12: "Screenshot: Tap to view" shows a placeholder, not buyer evidence', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt()]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to view'));
    await tester.pumpAndSettle();
    expect(find.text('Google Pay / PhonePe UPI Receipt'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('SA-AUD-T13: verification queue shows no garment / line items for the claim', (tester) async {
    final repo = AuditRepo(attempts: [auditAttempt(status: PaymentAttemptStatus.lateClaimPendingReview)]);
    await tester.pumpWidget(_screen(repo));
    await tester.pumpAndSettle();
    expect(find.text('Late Claim'), findsOneWidget);
    expect(find.textContaining('#A01'), findsNothing); // the seller cannot see which piece is being paid for
  });
}
