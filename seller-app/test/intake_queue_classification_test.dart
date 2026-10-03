// SA-INT-001 / SA-OFF-003: the offline intake queue classifies failures.
// Permanent (validation, duplicate, permission) → needs attention, never
// auto-retried; transient (network, timeout, 5xx) → backoff retries;
// 23505 for our own earlier insert → completed (lost-response idempotency).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/core/services/intake_error_classifier.dart';
import 'package:seller_app/core/services/offline_intake_queue.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScriptedIntakeRepo extends Fake implements SellerRepository {
  /// Errors thrown by successive createProduct calls (null entry = succeed).
  final List<Object?> createScript = [];

  /// When set, the product is stored first and then this error is thrown
  /// (the server committed but the response was lost).
  Object? commitThenThrow;
  Object? uploadError;

  final Map<String, SellerProduct> serverProducts = {};
  int uploadCalls = 0;
  int createCalls = 0;
  int lookupCalls = 0;
  final List<String> createdCodes = [];

  @override
  Future<String> uploadProductImage({
    required String dropId,
    required String fileName,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    uploadCalls++;
    final error = uploadError;
    if (error != null) throw error;
    return 'https://cdn.test/s/$dropId/$fileName';
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
    if (createScript.isNotEmpty) {
      final scripted = createScript.removeAt(0);
      if (scripted != null) throw scripted;
    }
    final key = '$dropId|$code';
    if (serverProducts.containsKey(key)) {
      // What SellerRepository.createProduct throws for a 23505.
      throw LiveDropException('Product flash code "$code" is already taken in this drop.', code: 'DUPLICATE_PRODUCT_CODE');
    }
    final product = SellerProduct(
      id: 'srv-$createCalls',
      dropId: dropId,
      code: code,
      title: title,
      pricePaisa: pricePaisa,
      size: size,
      imageUrl: imageUrl,
      imageUrls: imageUrls ?? [imageUrl],
      status: ProductStatus.available,
      version: 1,
    );
    serverProducts[key] = product;
    createdCodes.add(code);
    final lost = commitThenThrow;
    if (lost != null) {
      commitThenThrow = null;
      throw lost;
    }
    return product;
  }

  @override
  Future<SellerProduct?> findProductByCode({required String dropId, required String code}) async {
    lookupCalls++;
    return serverProducts['$dropId|$code'];
  }
}

Uint8List _jpeg() => Uint8List.fromList(List<int>.filled(32, 9));

void main() {
  late Directory dir;
  late OfflineIntakeQueue queue;
  late ScriptedIntakeRepo repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('intake_classify_');
    queue = OfflineIntakeQueue(storageDir: dir);
    await queue.initialize();
    repo = ScriptedIntakeRepo();
  });

  tearDown(() async {
    queue.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<IntakeQueueItem> enqueue({String code = '#A01'}) => queue.enqueue(
        dropId: 'drop-1',
        code: code,
        title: 'Kantha Saree',
        pricePaisa: 150000,
        size: 'Free Size',
        imageBytes: _jpeg(),
      );

  group('permanent failures → needs attention, no retry timer', () {
    test('23514 check violation from the server', () async {
      repo.createScript.add(const PostgrestException(
        message: 'new row for relation "products" violates check constraint "products_code_check"',
        code: '23514',
      ));
      await enqueue();
      await queue.processQueue(repo);

      final item = queue.items.single;
      expect(item.status, IntakeQueueStatus.needsAttention);
      expect(item.errorCode, '23514');
      expect(item.attentionReason, contains('Code #A01 is not valid'));
      expect(queue.hasScheduledRetry, isFalse);
      expect(queue.needsAttentionCount, 1);
      expect(queue.failedCount, 0);

      // Never retried automatically, not even by "retry failed uploads".
      await queue.processQueue(repo);
      await queue.retryFailed(repo);
      expect(repo.createCalls, 1);
      expect(queue.items.single.status, IntakeQueueStatus.needsAttention);
    });

    test('22001, 23502, 22P02 and 42501 (as PostgrestException or LiveDropException) are permanent', () async {
      const codes = ['22001', '23502', '22P02', '42501'];
      for (final code in codes) {
        final permanent = IntakeErrorClassifier.classify(
          PostgrestException(message: 'server says no', code: code),
          productCode: '#A01',
        );
        final wrapped = IntakeErrorClassifier.classify(LiveDropException('server says no', code: code));
        expect(permanent.kind, IntakeFailureKind.permanent, reason: code);
        expect(wrapped.kind, IntakeFailureKind.permanent, reason: code);
        expect(permanent.reason, isNot(contains('server says no')), reason: 'human readable for $code');
      }

      repo.createScript.add(const LiveDropException('new row violates row-level security policy', code: '42501'));
      await enqueue();
      await queue.processQueue(repo);
      expect(queue.items.single.status, IntakeQueueStatus.needsAttention);
      expect(queue.items.single.attentionReason, contains('Not allowed'));
      expect(queue.hasScheduledRetry, isFalse);
    });

    test('storage rejections (413 too large, 403 RLS) are permanent', () async {
      repo.uploadError = const StorageException('The object exceeded the maximum allowed size', statusCode: '413');
      await enqueue();
      await queue.processQueue(repo);
      expect(queue.items.single.status, IntakeQueueStatus.needsAttention);
      expect(queue.items.single.attentionReason, contains('too large'));
      expect(queue.hasScheduledRetry, isFalse);

      expect(
        IntakeErrorClassifier.classify(const LiveDropException('new row violates row-level security policy', code: '403')).kind,
        IntakeFailureKind.permanent,
      );
    });

    test('a 23505 for a product that is NOT ours is a real duplicate → needs attention', () async {
      repo.serverProducts['drop-1|#A01'] = const SellerProduct(
        id: 'someone-else',
        dropId: 'drop-1',
        code: '#A01',
        title: 'Another garment',
        pricePaisa: 99900,
        size: 'M',
        imageUrl: 'https://cdn.test/other.jpg',
        status: ProductStatus.available,
        version: 1,
      );
      await enqueue();
      await queue.processQueue(repo);
      final item = queue.items.single;
      expect(item.status, IntakeQueueStatus.needsAttention);
      expect(item.errorCode, '23505');
      expect(item.attentionReason, contains('already used'));
      expect(repo.lookupCalls, 1);
      expect(queue.hasScheduledRetry, isFalse);
    });

    test('a missing local photo is held for the seller instead of looping', () async {
      final item = await enqueue();
      await File(item.localImagePath).delete();
      await queue.processQueue(repo);
      expect(queue.items.single.status, IntakeQueueStatus.needsAttention);
      expect(queue.items.single.attentionReason, contains('missing'));
      expect(repo.createCalls, 0);
    });
  });

  group('transient failures → backoff retries', () {
    test('a network error keeps the piece retrying with a scheduled retry', () async {
      repo.uploadError = const SocketException('Network is unreachable');
      await enqueue();
      await queue.processQueue(repo);

      final item = queue.items.single;
      expect(item.status, IntakeQueueStatus.failed);
      expect(item.retryCount, 1);
      expect(queue.hasScheduledRetry, isTrue);
      expect(queue.needsAttentionCount, 0);

      repo.uploadError = null;
      await queue.retryFailed(repo);
      expect(queue.items.single.status, IntakeQueueStatus.completed);
    });

    test('timeouts, 5xx and expired sessions are transient', () {
      expect(IntakeErrorClassifier.classify(TimeoutException('slow')).kind, IntakeFailureKind.transient);
      expect(
        IntakeErrorClassifier.classify(const PostgrestException(message: 'Service Unavailable', code: '503')).kind,
        IntakeFailureKind.transient,
      );
      expect(
        IntakeErrorClassifier.classify(const PostgrestException(message: 'JWT expired', code: 'PGRST301')).kind,
        IntakeFailureKind.transient,
      );
      expect(IntakeErrorClassifier.classify(const UnauthorizedException()).kind, IntakeFailureKind.transient);
      expect(
        IntakeErrorClassifier.classify(const StorageException('Internal error', statusCode: '500')).kind,
        IntakeFailureKind.transient,
      );
    });
  });

  group('23505 idempotency (lost response)', () {
    test('23505 for an existing identical product (same uploaded photo) → completed', () async {
      repo.commitThenThrow = TimeoutException('response lost after commit');
      await enqueue();
      await queue.processQueue(repo); // committed on the server, client saw a timeout
      expect(queue.items.single.status, IntakeQueueStatus.failed);

      await queue.retryFailed(repo); // replay → 23505 → lookup finds our product
      final item = queue.items.single;
      expect(item.status, IntakeQueueStatus.completed);
      expect(item.serverProductId, repo.serverProducts['drop-1|#A01']!.id);
      expect(repo.createCalls, 2);
      expect(repo.lookupCalls, 1);
      expect(repo.serverProducts, hasLength(1));
      expect(queue.pendingCount, 0);
    });

    test('a raw PostgrestException 23505 is handled the same way', () async {
      repo.commitThenThrow = const SocketException('connection reset');
      await enqueue();
      await queue.processQueue(repo);
      repo.createScript.add(const PostgrestException(
        message: 'duplicate key value violates unique constraint "products_drop_id_code_key"',
        code: '23505',
      ));
      await queue.retryFailed(repo);
      expect(queue.items.single.status, IntakeQueueStatus.completed);
    });
  });

  group('entry validation, edit and discard', () {
    test('enqueue normalises the code and refuses invalid pieces', () async {
      final item = await enqueue(code: ' a 05 ');
      expect(item.code, '#A05');

      await expectLater(
        enqueue(code: 'saree01'),
        throwsA(isA<LiveDropException>().having((e) => e.code, 'code', 'INVALID_PRODUCT_INPUT')),
      );
      await expectLater(
        queue.enqueue(
          dropId: 'drop-1',
          code: '#A06',
          title: 'x' * 101,
          pricePaisa: 150000,
          size: 'M',
          imageBytes: _jpeg(),
        ),
        throwsA(isA<LiveDropException>()),
      );
      expect(queue.items, hasLength(1));
    });

    test('a piece queued by an older app version with an invalid code needs attention without any network call',
        () async {
      final legacyDir = await Directory.systemTemp.createTemp('intake_legacy_');
      File('${legacyDir.path}/queue.json').writeAsStringSync(jsonEncode([
        {
          'id': 'queue_legacy',
          'drop_id': 'drop-1',
          'code': 'SAREE01',
          'title': 'Old piece',
          'price_paisa': 150000,
          'size': 'M',
          'local_image_paths': <String>[],
          'remote_image_urls': ['https://cdn.test/legacy.jpg'],
          'status': 'failed',
          'retry_count': 12,
          'created_at': '2026-10-01T10:00:00.000',
          'updated_at': '2026-10-01T10:00:00.000',
        },
        {
          'id': 'queue_legacy_ok',
          'drop_id': 'drop-1',
          'code': 'a07',
          'title': 'Old piece without #',
          'price_paisa': 150000,
          'size': 'M',
          'local_image_paths': <String>[],
          'remote_image_urls': ['https://cdn.test/legacy-ok.jpg'],
          'status': 'failed',
          'retry_count': 3,
          'created_at': '2026-10-01T10:00:00.000',
          'updated_at': '2026-10-01T10:00:00.000',
        },
      ]));
      final legacy = OfflineIntakeQueue(storageDir: legacyDir);
      await legacy.initialize();
      await legacy.processQueue(repo);

      final invalid = legacy.itemById('queue_legacy')!;
      final healed = legacy.itemById('queue_legacy_ok')!;
      expect(invalid.status, IntakeQueueStatus.needsAttention);
      expect(invalid.attentionReason, contains('at most 6'));
      expect(healed.status, IntakeQueueStatus.completed); // 'a07' normalised to '#A07'
      expect(healed.code, '#A07');
      expect(repo.createdCodes, ['#A07']);
      expect(legacy.hasScheduledRetry, isFalse);
      legacy.dispose();
      await legacyDir.delete(recursive: true);
    });

    test('the seller can fix a piece that needs attention and it syncs', () async {
      repo.createScript.add(const PostgrestException(message: 'products_code_check', code: '23514'));
      final item = await enqueue();
      await queue.processQueue(repo);
      expect(queue.items.single.status, IntakeQueueStatus.needsAttention);

      await expectLater(
        queue.updateItem(item.id, code: 'TOOLONG1', title: 'Kantha Saree', pricePaisa: 150000, size: 'M'),
        throwsA(isA<LiveDropException>()),
      );
      await queue.updateItem(item.id, code: 'b09', title: 'Kantha Saree (fixed)', pricePaisa: 160000, size: 'L');
      expect(queue.items.single.status, IntakeQueueStatus.pending);
      expect(queue.items.single.attentionReason, isNull);

      await queue.processQueue(repo);
      final fixed = queue.items.single;
      expect(fixed.status, IntakeQueueStatus.completed);
      expect(fixed.code, '#B09');
      expect(repo.createdCodes, ['#B09']);
      expect(repo.uploadCalls, 1); // photo uploaded once, not again after the edit
    });

    test('the seller can discard a piece; its photos are deleted', () async {
      repo.createScript.add(const PostgrestException(message: 'products_code_check', code: '23514'));
      final item = await enqueue();
      await queue.processQueue(repo);
      final photo = File(item.localImagePath);
      expect(photo.existsSync(), isTrue);

      expect(await queue.discardItem(item.id), isTrue);
      expect(queue.items, isEmpty);
      expect(photo.existsSync(), isFalse);
      final manifest = File('${dir.path}/queue.json').readAsStringSync();
      expect(manifest, isNot(contains(item.id)));
    });

    test('concurrent edits and discards leave a complete, parseable manifest', () async {
      repo.createScript.addAll(const [
        PostgrestException(message: 'products_code_check', code: '23514'),
        PostgrestException(message: 'products_code_check', code: '23514'),
        PostgrestException(message: 'products_code_check', code: '23514'),
      ]);
      final a = await enqueue(code: '#A01');
      final b = await enqueue(code: '#A02');
      final c = await enqueue(code: '#A03');
      await queue.processQueue(repo);
      expect(queue.needsAttentionCount, 3);

      await Future.wait([
        queue.updateItem(a.id, code: '#B01', title: 'Fixed A', pricePaisa: 150000, size: 'M'),
        queue.updateItem(b.id, code: '#B02', title: 'Fixed B', pricePaisa: 150000, size: 'M'),
        queue.discardItem(c.id),
      ]);

      final reloaded = OfflineIntakeQueue(storageDir: dir);
      await reloaded.initialize();
      expect(reloaded.items.map((i) => i.code), unorderedEquals(['#B01', '#B02']));
      expect(reloaded.items.every((i) => i.status == IntakeQueueStatus.pending), isTrue);
      expect(File('${dir.path}/queue.json.tmp').existsSync(), isFalse);
      reloaded.dispose();
    });

    test('initialize is idempotent (a second call never reloads over in-memory progress)', () async {
      await enqueue();
      File('${dir.path}/queue.json').writeAsStringSync('[]');
      await queue.initialize();
      expect(queue.items, hasLength(1));
    });
  });
}
