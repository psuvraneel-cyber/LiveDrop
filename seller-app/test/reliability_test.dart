// P1 round 4c: live updates status and smaller downloads (SA-RT-002, SA-PERF-001).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/data/realtime/seller_live_store.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/main.dart';

import 'support/p0_fakes.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('the shell says when live updates are paused and clears it on reconnect (SA-RT-002)', (tester) async {
    final repo = P0FakeRepo();
    final source = FakeLiveSource();
    final store = SellerLiveStore(
      repository: repo,
      source: source,
      debounce: const Duration(milliseconds: 50),
      reconnectInterval: const Duration(seconds: 30),
      observeAppLifecycle: false,
    );
    await store.start();
    source.status(SellerLiveTransportStatus.subscribed);
    await tester.pumpWidget(testApp(SellerHomeScreen(repository: repo, liveStore: store)));
    await _settle(tester);
    expect(find.byKey(const Key('live-updates-paused')), findsNothing);

    source.status(SellerLiveTransportStatus.closed);
    await tester.pump();
    expect(store.status, SellerLiveStatus.reconnecting);
    expect(find.byKey(const Key('live-updates-paused')), findsOneWidget);

    final catchUpsBefore = store.catchUpCount;
    source.status(SellerLiveTransportStatus.subscribed);
    await _settle(tester);
    expect(find.byKey(const Key('live-updates-paused')), findsNothing);
    expect(store.catchUpCount, greaterThan(catchUpsBefore)); // missed events are fetched
    store.dispose();
  });

  test('analytics are read from seller_sales_summary (SA-PERF-001)', () {
    final a = SellerAnalytics.fromSummary({
      'total_revenue_paisa': 400000,
      'items_sold': 2,
      'active_holds': 1,
      'top_products': [
        {'code': '#A02', 'title': 'Banarasi Silk Saree', 'sold_count': 1, 'revenue_paisa': 250000, 'image_url': null},
        {'code': '#A01', 'title': 'Kantha Saree', 'sold_count': 1, 'revenue_paisa': 150000},
      ],
      'daily': [
        for (var i = 0; i < 7; i++) {'date': '2026-10-0${i + 1}', 'total_paisa': i == 3 ? 250000 : 0},
      ],
    }, paymentClaimsCount: 3);
    expect(a.totalRevenuePaisa, 400000);
    expect(a.itemsSoldCount, 2);
    expect(a.activeHoldsCount, 1);
    expect(a.paymentClaimsCount, 3);
    expect(a.dailySales, hasLength(7));
    expect(a.dailySales[3].dayLabel, 'Sun'); // 4 Oct 2026 is a Sunday
    expect(a.peakRevenuePaisa, 250000);
    expect(a.topProducts.first.productCode, '#A02');
  });
}
