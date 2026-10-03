// AUDIT-ONLY tests for OrderDetailsScreen (seller-app/lib/presentation/orders/order_details_screen.dart)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/presentation/orders/order_details_screen.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'audit_fakes.dart';

void main() {
  testWidgets('SA-AUD-T01: buyer name with two consecutive spaces crashes the order screen (RangeError in _getInitials)',
      (tester) async {
    final order = auditOrder(buyerName: 'Priya  Sharma');
    await tester.pumpWidget(auditApp(OrderDetailsScreen(
      order: order,
      profile: auditProfile,
      repository: AuditRepo(orders: [order]),
      onOrderUpdated: () {},
    )));
    final error = tester.takeException();
    // Evidence line for the audit log.
    // ignore: avoid_print
    print('AUDIT T01 exception: ${error.runtimeType}: $error');
    expect(error, isA<RangeError>());
  });

  testWidgets('SA-AUD-T02: WhatsApp contact drops the +91 country code for mobile numbers starting with 91',
      (tester) async {
    final launcher = RecordingLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);

    final order = auditOrder(buyerPhone: '9123456789'); // valid Indian mobile (starts with 9, then 1)
    await tester.pumpWidget(auditApp(OrderDetailsScreen(
      order: order,
      profile: auditProfile,
      repository: AuditRepo(orders: [order]),
      onOrderUpdated: () {},
    )));
    await tester.tap(find.byTooltip('WhatsApp'));
    await tester.pump();

    // ignore: avoid_print
    print('AUDIT T02 launched: ${launcher.launched}');
    expect(launcher.launched, isNotEmpty);
    expect(launcher.launched.first, contains('phone=9123456789&'));
    expect(launcher.launched.first, isNot(contains('phone=919123456789')));
  });

  testWidgets('SA-AUD-T03: primary button labelled "Mark as Ready" opens the dispatch (ship) dialog, also for shipped orders',
      (tester) async {
    final order = auditOrder();
    await tester.pumpWidget(auditApp(OrderDetailsScreen(
      order: order,
      profile: auditProfile,
      repository: AuditRepo(orders: [order]),
      onOrderUpdated: () {},
    )));
    expect(find.text('Mark as Ready'), findsOneWidget);
    await tester.ensureVisible(find.text('Mark as Ready'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Ready'));
    await tester.pumpAndSettle();
    expect(find.text('Dispatch & Print Label'), findsOneWidget);
    expect(find.text('Confirm Dispatch'), findsOneWidget);
  });
}
