// AUDIT-ONLY tests for OfflineIntakeQueue (seller-app/lib/core/services/offline_intake_queue.dart)
//
// T16, T17, T18 and T25 were inverted after the SA-INT-001 / SA-OFF-003 fix,
// and T14 / T19 after the SA-OFF-001 fix: they now assert the FIXED behaviour
// (IDs kept). T15 (pruning, P2) still documents an open finding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/core/services/offline_intake_queue.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';

/// Simulates the server: products keyed by "dropId|code" (UNIQUE(drop_id, code) in migration 003).
class ServerLikeRepo extends Fake implements SellerRepository {
  final Map<String, SellerProduct> serverProducts = {};
  int createCalls = 0;
  bool commitThenTimeoutOnce = false;
  Completer<void>? uploadGate;

  @override
  Future<String> uploadProductImage({
    required String dropId,
    required String fileName,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    if (uploadGate != null) await uploadGate!.future;
    return 'https://x.supabase.co/storage/v1/object/public/product-images/s/$dropId/$fileName';
  }

  @override
  Future<SellerProduct> createProduct({
    required String dropId,
    required String code,
    required String title,
    required int pricePaisa,
    required String size,
    required String imageUrl,
    List<String>? imageUrls,
  }) async {
    createCalls++;
    final key = '$dropId|${code.toUpperCase()}';
    if (!RegExp(r'^#[A-Z0-9]{1,6}$').hasMatch(code.toUpperCase())) {
      throw Exception('PostgrestException 23514 products_code_check'); // what the DB CHECK does
    }
    if (serverProducts.containsKey(key)) {
      throw Exception('LiveDropException[DUPLICATE_PRODUCT_CODE]');
    }
    final p = SellerProduct(
      id: 'p$createCalls', dropId: dropId, code: code, title: title, pricePaisa: pricePaisa,
      size: size, imageUrl: imageUrl, status: ProductStatus.available, version: 1,
    );
    serverProducts[key] = p;
    if (commitThenTimeoutOnce) {
      commitThenTimeoutOnce = false;
      throw TimeoutException('response lost after commit');
    }
    return p;
  }

  int lookups = 0;

  @override
  Future<SellerProduct?> findProductByCode({required String dropId, required String code}) async {
    lookups++;
    return serverProducts['$dropId|${code.toUpperCase()}'];
  }
}

/// Stands in for the platform plugin: the app support directory.
class _FakePathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _FakePathProvider(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

Uint8List _jpeg() => Uint8List.fromList(List<int>.filled(64, 7));

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('audit_queue_'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('SA-AUD-T14 (fixed): default queue location is the app support directory, not the OS temp/cache directory',
      () async {
    final support = await Directory.systemTemp.createTemp('audit_app_support_');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      if (await support.exists()) await support.delete(recursive: true);
    });

    // Default storage; only the legacy (migration source) folder is redirected
    // so the test does not touch a real queue in the machine's temp folder.
    final q = OfflineIntakeQueue(legacyDir: Directory('${dir.path}/no_legacy_queue'));
    await q.initialize();
    // ignore: avoid_print
    print('AUDIT T14 default baseDir=${q.baseDir.path} systemTemp=${Directory.systemTemp.path} '
        'migrates from=${OfflineIntakeQueue.legacyTempDir.path}');
    expect(q.baseDir.path, '${support.path}/livedrop_intake_queue');
    expect(q.baseDir.path, isNot(startsWith('${Directory.systemTemp.path}/livedrop_intake_queue')));
    expect(OfflineIntakeQueue.legacyTempDir.path, '${Directory.systemTemp.path}/livedrop_intake_queue');
    q.dispose();
  });

  test('SA-AUD-T15: completed items and their photos are never removed from disk or manifest', () async {
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    final item = await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    await q.processQueue(ServerLikeRepo());
    expect(q.items.single.status, IntakeQueueStatus.completed);
    expect(File(item.localImagePath).existsSync(), isTrue);
    final manifest = File('${dir.path}/queue.json').readAsStringSync();
    expect(manifest, contains('"status":"completed"'));
  });

  test('SA-AUD-T16 (fixed): a timeout after the server committed is recognised on retry — 23505 for a product '
      'carrying our own uploaded photo marks the piece completed (lost-response idempotency)', () async {
    final repo = ServerLikeRepo()..commitThenTimeoutOnce = true;
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    await q.processQueue(repo); // server stores the product, client sees a timeout
    final afterTimeout = q.items.single.status;
    for (var i = 0; i < 3; i++) {
      await q.retryFailed(repo);
    }
    final it = q.items.single;
    // ignore: avoid_print
    print('AUDIT T16 afterTimeout=$afterTimeout status=${it.status} retries=${it.retryCount} '
        'serverProductId=${it.serverProductId} lookups=${repo.lookups} createCalls=${repo.createCalls} '
        'serverProducts=${repo.serverProducts.length}');
    q.dispose();
    expect(afterTimeout, IntakeQueueStatus.failed); // transient: retried with backoff
    expect(repo.serverProducts, hasLength(1)); // the product is live on the server...
    expect(it.status, IntakeQueueStatus.completed); // ...and the device now agrees
    expect(it.serverProductId, repo.serverProducts.values.single.id);
    expect(q.failedCount, 0);
    expect(q.needsAttentionCount, 0);
    expect(repo.createCalls, 2); // one replay, then recognised — no retry loop
  });

  test('SA-AUD-T17 (fixed): a code typed without "#" is normalised before it is queued and syncs; an invalid '
      'code is refused at entry, and one queued by an older build is held as "needs attention" (no retry loop)',
      () async {
    final repo = ServerLikeRepo();
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    final item = await q.enqueue(dropId: 'd1', code: 'a05', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    await q.processQueue(repo);
    final synced = q.items.single;

    Object? entryError;
    try {
      await q.enqueue(dropId: 'd1', code: 'SAREE01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    } catch (e) {
      entryError = e;
    }
    q.dispose();

    // A manifest written by the old app (no validation at entry) with an invalid code:
    final legacyDir = await Directory.systemTemp.createTemp('audit_queue_legacy_');
    File('${legacyDir.path}/queue.json').writeAsStringSync(jsonEncode([
      {
        'id': 'queue_legacy', 'drop_id': 'd1', 'code': '#SAREE01', 'title': 't', 'price_paisa': 1000,
        'size': 'M', 'local_image_paths': <String>[], 'remote_image_urls': ['https://x/legacy.jpg'],
        'status': 'failed', 'retry_count': 7, 'last_error': '23514 products_code_check',
        'created_at': '2026-10-01T10:00:00.000', 'updated_at': '2026-10-01T10:00:00.000',
      }
    ]));
    final legacy = OfflineIntakeQueue(storageDir: legacyDir);
    await legacy.initialize();
    final legacyRepo = ServerLikeRepo();
    await legacy.processQueue(legacyRepo);
    final held = legacy.items.single;
    // ignore: avoid_print
    print('AUDIT T17 enqueued code=${item.code} status=${synced.status} | entry refusal=$entryError | '
        'legacy status=${held.status} reason="${held.attentionReason}" createCalls=${legacyRepo.createCalls} '
        'retryScheduled=${legacy.hasScheduledRetry}');
    final legacyRetryScheduled = legacy.hasScheduledRetry;
    legacy.dispose();
    await legacyDir.delete(recursive: true);

    expect(item.code, '#A05');
    expect(synced.status, IntakeQueueStatus.completed);
    expect(entryError, isA<LiveDropException>().having((e) => e.code, 'code', 'INVALID_PRODUCT_INPUT'));
    expect(held.status, IntakeQueueStatus.needsAttention);
    expect(held.attentionReason, contains('at most 6'));
    expect(legacyRepo.createCalls, 0); // never sent to the server again
    expect(legacyRetryScheduled, isFalse); // no background retry loop
  });

  test('SA-AUD-T18 (fixed): an item enqueued while a sync is running is picked up by that same run', () async {
    final repo = ServerLikeRepo()..uploadGate = Completer<void>();
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 'first', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    final run = q.processQueue(repo);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await q.enqueue(dropId: 'd1', code: '#A02', title: 'second', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    await q.processQueue(repo); // returns immediately because a run is in progress
    repo.uploadGate!.complete();
    await run;
    final second = q.items.firstWhere((i) => i.code == '#A02');
    // ignore: avoid_print
    print('AUDIT T18 second item status after the run finished: ${second.status} createCalls=${repo.createCalls}');
    q.dispose();
    expect(second.status, IntakeQueueStatus.completed);
    expect(repo.serverProducts, hasLength(2));
  });

  test('SA-AUD-T25 (fixed): re-initialising the shared queue during a sync (camera_intake_screen.dart) is a no-op, '
      'so the run keeps its progress and the garment is created exactly once', () async {
    final repo = ServerLikeRepo()..uploadGate = Completer<void>();
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    final run = q.processQueue(repo); // sync still running from the previous intake session
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await q.initialize(); // seller taps "Add Product" again: CameraIntakeScreen._initialize() on the shared queue
    repo.uploadGate!.complete();
    await run;
    final statusAfterRun = q.items.single.status;
    repo.uploadGate = null;
    await q.processQueue(repo); // next trigger has nothing left to send
    final it = q.items.single;
    // ignore: avoid_print
    print('AUDIT T25 statusAfterFirstRun=$statusAfterRun final=${it.status} lastError=${it.lastError} '
        'serverProducts=${repo.serverProducts.length} createCalls=${repo.createCalls}');
    q.dispose();
    expect(repo.serverProducts, hasLength(1));
    expect(statusAfterRun, IntakeQueueStatus.completed);
    expect(it.status, IntakeQueueStatus.completed);
    expect(repo.createCalls, 1);
  });

  test('SA-AUD-T19 (fixed): a corrupt manifest is moved aside and the queue is restored from queue.json.bak',
      () async {
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    q.dispose();
    File('${dir.path}/queue.json').writeAsStringSync('[{"id": "trunc'); // e.g. disk corruption
    final reloaded = OfflineIntakeQueue(storageDir: dir);
    await reloaded.initialize();
    final quarantined = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('queue.json.corrupt-'))
        .toList();
    // ignore: avoid_print
    print('AUDIT T19 reloaded items=${reloaded.items.map((i) => i.code).toList()} '
        'quarantined=${quarantined.map((f) => f.uri.pathSegments.last).toList()}');
    reloaded.dispose();
    expect(reloaded.items.map((i) => i.code), ['#A01']); // nothing lost
    expect(quarantined, hasLength(1)); // corrupt file kept for inspection, not overwritten
    expect(quarantined.single.readAsStringSync(), '[{"id": "trunc');
    expect(jsonDecode(File('${dir.path}/queue.json').readAsStringSync()), hasLength(1)); // healthy again
  });
}
