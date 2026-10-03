// SA-RT-001: one app-level live store drives Home, Products, Orders and
// Payments. Tested with a fake event source (no network).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/data/realtime/seller_live_store.dart';
import 'package:seller_app/main.dart';
import 'package:seller_app/presentation/common/live_refresh.dart';
import 'package:seller_app/presentation/orders/kanban_board_screen.dart';
import 'package:seller_app/presentation/pending_verifications_screen.dart';

import 'support/p0_fakes.dart';

const _debounce = Duration(milliseconds: 300);

SellerLiveStore _store(P0FakeRepo repo, FakeLiveSource source) => SellerLiveStore(
      repository: repo,
      source: source,
      debounce: _debounce,
      reconnectInterval: const Duration(seconds: 30),
      observeAppLifecycle: false,
    );

void main() {
  group('SellerLiveStore', () {
    testWidgets('a payment_attempts event bumps the revision and the payment counts without a manual refresh',
        (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);

      await store.start();
      source.status(SellerLiveTransportStatus.subscribed);
      expect(store.status, SellerLiveStatus.live);
      expect(store.revision, 0);
      expect(store.pendingVerifications, 0);

      repo.attempts = [testAttempt()];
      source.emitPaymentAttempt();
      source.emitPaymentAttempt(id: 'attempt-2'); // a burst …
      source.emitPaymentAttempt(id: 'attempt-3');
      expect(store.revision, 0, reason: 'debounced');

      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(store.revision, 1, reason: '… is coalesced into one revision bump');
      expect(store.pendingVerifications, 1);
      expect(store.paymentsBadgeCount, 1);

      repo.refunds = [testRefund()];
      source.emitOrder(); // own drop
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(store.revision, 2);
      expect(store.refundsOwed, 1);
      expect(store.refundsOwedPaisa, 158000);
      expect(store.paymentsBadgeCount, 2);
      store.dispose();
    });

    testWidgets('overdue claims are counted from verification deadlines', (tester) async {
      final repo = P0FakeRepo(attempts: [
        testAttempt(id: 'late', verificationExpiresAt: DateTime.now().subtract(const Duration(minutes: 5))),
        testAttempt(id: 'fresh'),
      ]);
      final store = _store(repo, FakeLiveSource());
      addTearDown(store.dispose);
      await store.start();
      expect(store.pendingVerifications, 2);
      expect(store.overdueClaims, 1);
      store.dispose();
    });

    testWidgets('a fresh late claim (no verification window yet) is pending but not overdue', (tester) async {
      final repo = P0FakeRepo(attempts: [freshLateClaim(), testAttempt(id: 'fresh')]);
      final store = _store(repo, FakeLiveSource());
      addTearDown(store.dispose);
      await store.start();
      expect(store.pendingVerifications, 2);
      expect(store.overdueClaims, 0);
      store.dispose();
    });

    testWidgets('a reconnect after a channel error triggers a catch-up (revision bump + counts refetch)',
        (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();
      source.status(SellerLiveTransportStatus.subscribed);
      final dropsCalls = repo.count('getDrops');
      final claimCalls = repo.count('getPendingVerifications');

      source.status(SellerLiveTransportStatus.error);
      expect(store.status, SellerLiveStatus.reconnecting);
      repo.attempts = [testAttempt()]; // arrived while the channel was down

      source.status(SellerLiveTransportStatus.subscribed);
      await tester.pump();
      expect(store.status, SellerLiveStatus.live);
      expect(store.catchUpCount, 1);
      expect(store.revision, 1);
      expect(repo.count('getDrops'), dropsCalls + 1);
      expect(repo.count('getPendingVerifications'), greaterThan(claimCalls));
      expect(store.pendingVerifications, 1);
      store.dispose();
    });

    testWidgets('while the channel is down the store polls and re-subscribes', (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();
      source.status(SellerLiveTransportStatus.timedOut);
      expect(source.openCount, 1);

      await tester.pump(const Duration(seconds: 31));
      expect(store.catchUpCount, 1);
      expect(source.openCount, 2);
      expect(store.revision, 1);
      store.dispose();
    });

    testWidgets('app resume catches up and re-subscribes when the channel is not live', (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();
      expect(store.status, SellerLiveStatus.connecting);

      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.catchUpCount, 1);
      expect(store.revision, 1);
      expect(source.openCount, 2);
      store.dispose();
    });

    testWidgets('resume after a real background stay catches up; a brief interruption does not', (tester) async {
      var now = DateTime.utc(2026, 10, 3, 12);
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = SellerLiveStore(
        repository: repo,
        source: source,
        debounce: _debounce,
        observeAppLifecycle: false,
        clock: () => now,
      );
      await store.start();
      source.status(SellerLiveTransportStatus.subscribed);

      // Permission dialog / image picker: inactive → resumed, channel live.
      store.didChangeAppLifecycleState(AppLifecycleState.inactive);
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.catchUpCount, 0);

      // Paused for one second only.
      store.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 1));
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.catchUpCount, 0);

      // Back after ten minutes in the background.
      store.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 10));
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(store.catchUpCount, 1);
      expect(store.revision, 1);
      expect(source.openCount, 1, reason: 'channel was live: no re-subscribe needed');
      store.dispose();
    });

    testWidgets("events for other sellers' drops are ignored (and resolved only once)", (tester) async {
      final repo = P0FakeRepo(drops: [testDrop(id: 'drop-1')]);
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();
      source.status(SellerLiveTransportStatus.subscribed);
      final dropsCalls = repo.count('getDrops');

      source.emitProduct(dropId: 'drop-of-another-seller');
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(store.revision, 0);
      expect(repo.count('getDrops'), dropsCalls + 1, reason: 'unknown drop id resolved once');

      source.emitProduct(dropId: 'drop-of-another-seller');
      source.emitOrder(dropId: 'drop-of-another-seller');
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(store.revision, 0);
      expect(repo.count('getDrops'), dropsCalls + 1, reason: 'known foreign drop is not refetched');

      source.emitProduct(dropId: 'drop-1');
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(store.revision, 1);
      store.dispose();
    });

    testWidgets('events for a drop created after start are recognised as our own', (tester) async {
      final repo = P0FakeRepo(drops: [testDrop(id: 'drop-1')]);
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();

      repo.drops = [...repo.drops, testDrop(id: 'drop-2', title: 'Sunday Live')];
      source.emitOrder(dropId: 'drop-2', change: SellerLiveChange.insert);
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(store.revision, 1);
      expect(store.ownDropIds, contains('drop-2'));
      store.dispose();
    });

    testWidgets('dispose closes the channel and ignores late events', (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      await store.start();
      store.dispose();
      expect(source.closeCount, 1);
      source.emitPaymentAttempt(); // handler already detached by close()
      await tester.pump(_debounce * 2);
      expect(store.isDisposed, isTrue);
    });
  });

  group('screens follow the live store', () {
    testWidgets('Payments tab badge and queue update from a payment_attempts event without a refresh',
        (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);

      await tester.pumpWidget(testApp(SellerHomeScreen(repository: repo, liveStore: store)));
      await store.start();
      source.status(SellerLiveTransportStatus.subscribed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('nav-badge-Payments')), findsNothing);

      // Open the Payments tab: empty queue.
      await tester.tap(find.text('Payments'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('All Payments Verified!'), findsOneWidget);

      // A buyer submits a payment claim.
      repo.attempts = [testAttempt(orderCode: 'LD-LIVE01')];
      source.emitPaymentAttempt();
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));

      final badge = find.byKey(const ValueKey('nav-badge-Payments'));
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.text('1')), findsOneWidget);
      expect(find.text('#LD-LIVE01'), findsOneWidget);
      expect(find.text('All Payments Verified!'), findsNothing);

      // A refund obligation is added to the badge.
      repo.refunds = [testRefund()];
      source.emitOrder();
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.descendant(of: badge, matching: find.text('2')), findsOneWidget);
      expect(find.text('Refunds owed (1)'), findsOneWidget);
      store.dispose();
    });

    testWidgets('Orders (All Drops) reloads on a live order event; hidden tabs wait until shown', (tester) async {
      final repo = P0FakeRepo(drops: [testDrop(id: 'drop-1'), testDrop(id: 'drop-2', title: 'Sunday Live')]);
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();

      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(testApp(ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, isVisible, _) => LiveTabVisibility(
          visible: isVisible,
          child: KanbanBoardScreen(repository: repo, liveStore: store),
        ),
      )));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pending (0)'), findsOneWidget);

      // New order in the second drop while "All Drops" is selected.
      repo.orders = [testOrder(id: 'o-2', code: 'LD-NEW002', dropId: 'drop-2')];
      source.emitOrder(dropId: 'drop-2', change: SellerLiveChange.insert);
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Pending (1)'), findsOneWidget);
      expect(find.text('#LD-NEW002'), findsOneWidget);

      // Hidden tab: the change is remembered, fetched when the tab is shown.
      visible.value = false;
      await tester.pump();
      final ordersCalls = repo.count('getAllOrders');
      repo.orders = [
        ...repo.orders,
        testOrder(id: 'o-3', code: 'LD-NEW003', dropId: 'drop-1'),
      ];
      source.emitOrder(dropId: 'drop-1', change: SellerLiveChange.insert);
      await tester.pump(_debounce + const Duration(milliseconds: 50));
      expect(repo.count('getAllOrders'), ordersCalls);

      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.count('getAllOrders'), ordersCalls + 1);
      expect(find.text('Pending (2)'), findsOneWidget);
      store.dispose();
    });

    testWidgets('verifying a payment invalidates every tab immediately (no waiting for realtime)', (tester) async {
      final repo = P0FakeRepo(attempts: [testAttempt(orderCode: 'LD-PAYME1')]);
      final source = FakeLiveSource();
      final store = _store(repo, source);
      await store.start();

      await tester.pumpWidget(testApp(Scaffold(
        body: PendingVerificationsScreen(repository: repo, liveStore: store),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      final before = store.revision;

      await tester.tap(find.text('Verify Payment'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirm Receipt'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.verifyCalls, ['attempt-1']);
      expect(store.revision, before + 1, reason: 'other tabs (Orders, Home, Products) reload on this revision');
      expect(find.text('#LD-PAYME1'), findsNothing);
      store.dispose();
    });

    testWidgets('a stand-alone Payments screen reloads when the revision changes', (tester) async {
      final repo = P0FakeRepo();
      final source = FakeLiveSource();
      final store = _store(repo, source);
      addTearDown(store.dispose);
      await store.start();

      await tester.pumpWidget(testApp(Scaffold(
        body: PendingVerificationsScreen(repository: repo, liveStore: store),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('All Payments Verified!'), findsOneWidget);

      repo.attempts = [testAttempt(orderCode: 'LD-CLAIM9')];
      store.requestRefresh(immediate: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('#LD-CLAIM9'), findsOneWidget);
      store.dispose();
    });
  });
}
