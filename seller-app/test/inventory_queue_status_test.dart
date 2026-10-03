// SA-INT-001: the inventory never shows a queued / failed piece as
// "Available"; the banner says how many pieces need attention and leads to
// an editor that blocks invalid input.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/services/offline_intake_queue.dart';
import 'package:seller_app/presentation/products/products_inventory_screen.dart';

import 'support/p0_fakes.dart';

Map<String, Object?> _manifestItem({
  required String id,
  required String code,
  required String status,
  String? reason,
  List<String> remoteUrls = const [],
}) {
  return {
    'id': id,
    'drop_id': 'drop-1',
    'code': code,
    'title': 'Queued $code',
    'price_paisa': 120000,
    'size': 'M',
    'local_image_paths': <String>[],
    'remote_image_urls': remoteUrls,
    'status': status,
    'retry_count': status == 'failed' ? 2 : 0,
    'attention_reason': reason,
    'created_at': '2026-10-03T10:00:00.000',
    'updated_at': '2026-10-03T10:00:00.000',
  };
}

Future<OfflineIntakeQueue> _queueWith(WidgetTester tester, List<Map<String, Object?>> items) async {
  final dir = Directory.systemTemp.createTempSync('inventory_queue_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  File('${dir.path}/queue.json').writeAsStringSync(jsonEncode(items));
  final queue = OfflineIntakeQueue(storageDir: dir);
  await tester.runAsync(() => queue.initialize());
  addTearDown(queue.dispose);
  return queue;
}

/// Phone-like tall surface so the whole list is on screen.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('queued, retrying and needs-attention pieces are never rendered as "Available"', (tester) async {
    _tallScreen(tester);
    final queue = await _queueWith(tester, [
      _manifestItem(
        id: 'q-attention',
        code: '#A02',
        status: 'needsAttention',
        reason: 'Code #A02 is already used by another piece in this drop. Change the code.',
        remoteUrls: ['https://cdn.test/drop-1/a02.jpg'],
      ),
      _manifestItem(id: 'q-failed', code: '#A03', status: 'failed'),
      _manifestItem(id: 'q-pending', code: '#A04', status: 'pending'),
      _manifestItem(id: 'q-done', code: '#A05', status: 'completed'),
    ]);
    final repo = P0FakeRepo(products: [
      testProduct(id: 'p-1', code: '#A01'),
      testProduct(id: 'p-5', code: '#A05'),
    ]);

    await tester.pumpWidget(testApp(ProductsInventoryScreen(repository: repo, intakeQueue: queue)));
    await _settle(tester);

    // Each queued piece shows its real state.
    expect(find.text('#A02'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('#A03'), findsOneWidget);
    expect(find.text('Retrying'), findsOneWidget);
    expect(find.text('#A04'), findsOneWidget);
    expect(find.text('Syncing'), findsOneWidget);

    // Only the two live server products are "Available".
    expect(find.text('Available'), findsNWidgets(2));
    expect(find.text('Available (2)'), findsOneWidget);
    expect(find.text('All (5)'), findsOneWidget);

    // The banner counts the pieces that need attention and shows the reason.
    expect(find.text('1 piece needs attention — not live yet'), findsOneWidget);
    expect(find.textContaining('already used by another piece'), findsWidgets);

    // Filtering on "Available" hides every piece that is not live.
    await tester.tap(find.text('Available (2)'));
    await _settle(tester);
    expect(find.text('#A02'), findsNothing);
    expect(find.text('#A03'), findsNothing);
    expect(find.text('#A04'), findsNothing);
    expect(find.text('#A01'), findsOneWidget);
  });

  testWidgets('the banner opens the fix sheet; the editor blocks invalid input and re-queues a fixed piece',
      (tester) async {
    final queue = await _queueWith(tester, [
      _manifestItem(
        id: 'q-attention',
        code: '#A02',
        status: 'needsAttention',
        reason: 'Code #A02 is already used by another piece in this drop. Change the code.',
        remoteUrls: ['https://cdn.test/drop-1/a02.jpg'],
      ),
    ]);
    final repo = P0FakeRepo(products: [testProduct(id: 'p-2', code: '#A02')]);

    await tester.pumpWidget(testApp(ProductsInventoryScreen(repository: repo, intakeQueue: queue)));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('queue-attention-banner')));
    await _settle(tester);
    expect(find.text('Fix 1 piece before they go live'), findsOneWidget);

    await tester.tap(find.text('Fix piece'));
    await _settle(tester);
    expect(find.text('Fix #A02'), findsOneWidget);

    // Invalid: 7 characters → inline error, dialog stays open, queue untouched.
    await tester.enterText(find.byKey(const ValueKey('queued-piece-code')), 'saree01');
    await tester.pump();
    await tester.tap(find.text('Save & sync'));
    await _settle(tester);
    expect(find.textContaining('at most 6'), findsOneWidget);
    expect(find.text('Fix #A02'), findsOneWidget);
    expect(queue.itemById('q-attention')!.status, IntakeQueueStatus.needsAttention);

    // Still a duplicate of the live #A02 → blocked as well.
    await tester.enterText(find.byKey(const ValueKey('queued-piece-code')), 'a02');
    await tester.pump();
    await tester.tap(find.text('Save & sync'));
    await _settle(tester);
    expect(find.textContaining('already used in this drop'), findsOneWidget);
    expect(queue.itemById('q-attention')!.status, IntakeQueueStatus.needsAttention);

    // Valid: dialog closes and the piece is re-queued with the new code.
    await tester.enterText(find.byKey(const ValueKey('queued-piece-code')), 'a09');
    await tester.pump();
    await tester.tap(find.text('Save & sync'));
    await _settle(tester);
    expect(find.text('Fix #A02'), findsNothing);
    final fixed = queue.itemById('q-attention')!;
    expect(fixed.code, '#A09');
    expect(fixed.status, IntakeQueueStatus.pending);
    expect(fixed.attentionReason, isNull);
  });

  testWidgets('a piece that needs attention can be discarded after confirmation', (tester) async {
    final queue = await _queueWith(tester, [
      _manifestItem(id: 'q-attention', code: '#A02', status: 'needsAttention', reason: 'Photo missing.'),
    ]);
    final repo = P0FakeRepo();

    await tester.pumpWidget(testApp(ProductsInventoryScreen(repository: repo, intakeQueue: queue)));
    await _settle(tester);

    await tester.tap(find.text('#A02'));
    await _settle(tester);
    await tester.tap(find.text('Discard'));
    await _settle(tester);
    expect(find.text('Discard #A02?'), findsOneWidget);
    await tester.tap(find.text('Discard piece'));
    await _settle(tester);
    expect(queue.itemById('q-attention'), isNull);
  });
}
