// AUDIT-ONLY tests for OfflineIntakeQueue (seller-app/lib/core/services/offline_intake_queue.dart)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
}

Uint8List _jpeg() => Uint8List.fromList(List<int>.filled(64, 7));

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('audit_queue_'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('SA-AUD-T14: default queue location is the OS temp/cache directory', () {
    final q = OfflineIntakeQueue();
    // ignore: avoid_print
    print('AUDIT T14 default baseDir=${q.baseDir.path} systemTemp=${Directory.systemTemp.path}');
    expect(q.baseDir.path, startsWith(Directory.systemTemp.path));
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

  test('SA-AUD-T16: a timeout after the server committed turns into a permanent DUPLICATE failure', () async {
    final repo = ServerLikeRepo()..commitThenTimeoutOnce = true;
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    await q.processQueue(repo); // server stores the product, client sees a timeout
    for (var i = 0; i < 3; i++) {
      await q.retryFailed(repo);
    }
    final it = q.items.single;
    // ignore: avoid_print
    print('AUDIT T16 status=${it.status} retries=${it.retryCount} lastError=${it.lastError} serverProducts=${repo.serverProducts.length}');
    expect(repo.serverProducts, hasLength(1)); // the product IS live on the server...
    expect(it.status, IntakeQueueStatus.failed); // ...but the device shows a failed upload forever
    expect(it.lastError, contains('DUPLICATE_PRODUCT_CODE'));
    expect(q.failedCount, 1);
  });

  test('SA-AUD-T17: a code typed without "#" is queued and fails only in the background', () async {
    final repo = ServerLikeRepo();
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: 'A05', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    await q.processQueue(repo);
    // ignore: avoid_print
    print('AUDIT T17 lastError=${q.items.single.lastError}');
    expect(q.items.single.status, IntakeQueueStatus.failed);
    expect(q.items.single.lastError, contains('23514'));
  });

  test('SA-AUD-T18: an item enqueued while a sync is running is not picked up by that run', () async {
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
    print('AUDIT T18 second item status after the run finished: ${second.status}');
    expect(second.status, IntakeQueueStatus.pending);
  });

  test('SA-AUD-T25: re-initialising the shared queue during a sync (camera_intake_screen.dart:76) '
      'discards the run\'s progress and ends in a permanent DUPLICATE failure', () async {
    final repo = ServerLikeRepo()..uploadGate = Completer<void>();
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    final run = q.processQueue(repo); // sync still running from the previous intake session
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await q.initialize(); // seller taps "Add Product" again: CameraIntakeScreen._initialize() on the shared queue
    repo.uploadGate!.complete();
    await run; // the old run finishes on objects that are no longer in the queue
    final statusAfterRun = q.items.single.status;
    repo.uploadGate = null;
    await q.processQueue(repo); // next trigger re-sends the same garment
    final it = q.items.single;
    // ignore: avoid_print
    print('AUDIT T25 statusAfterFirstRun=$statusAfterRun final=${it.status} lastError=${it.lastError} '
        'serverProducts=${repo.serverProducts.length} createCalls=${repo.createCalls}');
    q.dispose();
    expect(repo.serverProducts, hasLength(1)); // the garment is live on the server...
    expect(statusAfterRun, isNot(IntakeQueueStatus.completed)); // ...the device lost that fact...
    expect(it.status, IntakeQueueStatus.failed); // ...and now shows a failed upload forever
    expect(it.lastError, contains('DUPLICATE_PRODUCT_CODE'));
  });

  test('SA-AUD-T19: a corrupt manifest silently drops every queued garment', () async {
    final q = OfflineIntakeQueue(storageDir: dir);
    await q.initialize();
    await q.enqueue(dropId: 'd1', code: '#A01', title: 't', pricePaisa: 1000, size: 'M', imageBytes: _jpeg());
    File('${dir.path}/queue.json').writeAsStringSync('[{"id": "trunc'); // e.g. power loss mid-write
    final reloaded = OfflineIntakeQueue(storageDir: dir);
    await reloaded.initialize();
    expect(reloaded.items, isEmpty);
    expect(Directory('${dir.path}/images').listSync(), isNotEmpty); // photos orphaned on disk
  });
}
