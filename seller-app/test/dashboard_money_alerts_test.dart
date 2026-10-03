// SA-PAY-003 / SA-PAY-004: Home shows refunds owed and overdue payment claims
// (only when there are any) and both lead to Payments.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/data/realtime/seller_live_store.dart';
import 'package:seller_app/presentation/dashboard/seller_dashboard_screen.dart';

import 'support/p0_fakes.dart';

Widget _home(P0FakeRepo repo, {SellerLiveStore? store, VoidCallback? onPayments}) => testApp(
      SellerDashboardScreen(
        repository: repo,
        liveStore: store,
        onNavigateToAddProduct: () {},
        onNavigateToOrders: () {},
        onNavigateToPayments: onPayments ?? () {},
        onNavigateToAnalytics: () {},
        onNavigateToShipping: () {},
        onManageDrop: () {},
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('refunds owed and overdue claims are shown on Home and open Payments', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var openedPayments = 0;
    final repo = P0FakeRepo(
      refunds: [testRefund(amountPaisa: 158000)],
      attempts: [
        testAttempt(id: 'late', verificationExpiresAt: DateTime.now().subtract(const Duration(minutes: 10))),
      ],
    );
    await tester.pumpWidget(_home(repo, onPayments: () => openedPayments++));
    await _settle(tester);

    expect(find.text('Refunds owed: 1'), findsOneWidget);
    expect(find.text('₹1,580 to send back to buyers — tap to settle'), findsOneWidget);
    expect(find.text('1 payment claim is overdue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-refunds-owed')));
    await tester.tap(find.byKey(const ValueKey('home-overdue-claims')));
    expect(openedPayments, 2);
  });

  testWidgets('nothing extra is shown when no refund is owed and no claim is overdue', (tester) async {
    await tester.pumpWidget(_home(P0FakeRepo(attempts: [testAttempt()])));
    await _settle(tester);
    expect(find.textContaining('Refunds owed'), findsNothing);
    expect(find.textContaining('overdue'), findsNothing);
  });

  testWidgets('a late claim submitted a minute ago does not raise the overdue alert on Home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_home(P0FakeRepo(attempts: [freshLateClaim()])));
    await _settle(tester);
    expect(find.textContaining('overdue'), findsNothing);
  });

  testWidgets('Home follows the live store counts without reloading', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = P0FakeRepo();
    final source = FakeLiveSource();
    final store = SellerLiveStore(
      repository: repo,
      source: source,
      debounce: const Duration(milliseconds: 300),
      observeAppLifecycle: false,
    );
    await store.start();
    await tester.pumpWidget(_home(repo, store: store));
    await _settle(tester);
    expect(find.textContaining('Refunds owed'), findsNothing);

    repo.refunds = [testRefund(amountPaisa: 25000)];
    await store.refreshCounts();
    await tester.pump();
    expect(find.text('Refunds owed: 1'), findsOneWidget);
    expect(find.text('₹250 to send back to buyers — tap to settle'), findsOneWidget);
    store.dispose();
  });
}
