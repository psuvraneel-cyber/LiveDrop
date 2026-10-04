// SA-OFF-001: durable storage location, atomic manifest + backup, corrupt
// manifest recovery, and migration from the old temp-directory queue.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/services/offline_intake_queue.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';

class _UploadRepo extends Fake implements SellerRepository {
  final List<List<int>> uploadedBytes = [];
  int created = 0;

  @override
  Future<String> uploadProductImage({
    required String dropId,
    required String fileName,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    uploadedBytes.add(imageBytes);
    return 'https://x.supabase.co/storage/v1/object/public/product-images/$dropId/$fileName';
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
    created++;
    return SellerProduct(
      id: 'p$created',
      dropId: dropId,
      code: code,
      title: title,
      pricePaisa: pricePaisa,
      size: size,
      imageUrl: imageUrl,
      status: ProductStatus.available,
      version: 1,
    );
  }
}

Uint8List _jpeg([int fill = 7]) => Uint8List.fromList(List<int>.filled(64, fill));

List<dynamic> _readJsonList(File f) => jsonDecode(f.readAsStringSync()) as List<dynamic>;

Map<String, dynamic> _legacyEntry({
  required String id,
  required String code,
  required List<String> localPaths,
}) =>
    {
      'id': id,
      'drop_id': 'd1',
      'code': code,
      'title': 'Legacy saree',
      'price_paisa': 150000,
      'size': 'Free Size',
      'local_image_paths': localPaths,
      'remote_image_urls': <String>[],
      'status': 'pending',
      'retry_count': 0,
      'created_at': '2026-10-01T10:00:00.000',
      'updated_at': '2026-10-01T10:00:00.000',
    };

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('ld_queue_durability_'));
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('storage location', () {
    test('default folder is <app support dir>/livedrop_intake_queue, not the temp directory', () async {
      final support = Directory('${root.path}/app_support')..createSync();
      final q = OfflineIntakeQueue(
        supportDirProvider: () async => support,
        legacyDir: Directory('${root.path}/no_legacy_here'),
      );
      expect(() => q.baseDir, throwsStateError); // unknown until initialised
      await q.initialize();
      expect(q.baseDir.path, '${support.path}/${OfflineIntakeQueue.storageFolderName}');
      expect(Directory('${q.baseDir.path}/images').existsSync(), isTrue);
      q.dispose();
    });

    test('the pre-fix default legacy location is the old temp folder', () {
      expect(
        OfflineIntakeQueue.legacyTempDir.path,
        '${Directory.systemTemp.path}/${OfflineIntakeQueue.storageFolderName}',
      );
    });
  });

  group('atomic manifest writes', () {
    test('every save leaves a valid queue.json and a matching queue.json.bak, no temp files', () async {
      final dir = Directory('${root.path}/q');
      final q = OfflineIntakeQueue(storageDir: dir);
      await q.initialize();
      await q.enqueue(dropId: 'd1', code: '#A01', title: 'One', pricePaisa: 100000, size: 'M', imageBytes: _jpeg());
      await q.enqueue(dropId: 'd1', code: '#A02', title: 'Two', pricePaisa: 120000, size: 'L', imageBytes: _jpeg());
      q.dispose();

      final manifest = File('${dir.path}/queue.json');
      final backup = File('${dir.path}/queue.json.bak');
      expect(_readJsonList(manifest).map((e) => (e as Map)['code']), ['#A01', '#A02']);
      expect(backup.readAsStringSync(), manifest.readAsStringSync());
      expect(File('${dir.path}/queue.json.tmp').existsSync(), isFalse);
      expect(File('${dir.path}/queue.json.bak.tmp').existsSync(), isFalse);
    });

    test('a half-written temp file from a crash does not affect the manifest', () async {
      final dir = Directory('${root.path}/q');
      final q = OfflineIntakeQueue(storageDir: dir);
      await q.initialize();
      await q.enqueue(dropId: 'd1', code: '#A01', title: 'One', pricePaisa: 100000, size: 'M', imageBytes: _jpeg());
      q.dispose();
      // Power loss while the next write was in progress:
      File('${dir.path}/queue.json.tmp').writeAsStringSync('[{"id": "trunc');

      final reloaded = OfflineIntakeQueue(storageDir: dir);
      await reloaded.initialize();
      expect(reloaded.items.map((i) => i.code), ['#A01']);
      await reloaded.enqueue(dropId: 'd1', code: '#A02', title: 'Two', pricePaisa: 100000, size: 'M', imageBytes: _jpeg());
      expect(_readJsonList(File('${dir.path}/queue.json')), hasLength(2));
      reloaded.dispose();
    });
  });

  group('corrupt manifest recovery', () {
    test('restores from queue.json.bak and moves the corrupt file aside (not overwritten)', () async {
      final dir = Directory('${root.path}/q');
      final q = OfflineIntakeQueue(storageDir: dir);
      await q.initialize();
      await q.enqueue(dropId: 'd1', code: '#A01', title: 'One', pricePaisa: 100000, size: 'M', imageBytes: _jpeg());
      q.dispose();

      const corrupt = '[{"id": "trunc';
      File('${dir.path}/queue.json').writeAsStringSync(corrupt);

      final reloaded = OfflineIntakeQueue(storageDir: dir);
      await reloaded.initialize();
      expect(reloaded.items.map((i) => i.code), ['#A01']);

      final quarantined = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('queue.json.corrupt-'))
          .toList();
      expect(quarantined, hasLength(1));
      expect(quarantined.single.readAsStringSync(), corrupt);
      // The healthy manifest was rewritten from the backup right away.
      expect(_readJsonList(File('${dir.path}/queue.json')), hasLength(1));

      // And the restored piece still uploads.
      final repo = _UploadRepo();
      await reloaded.processQueue(repo);
      expect(reloaded.items.single.status, IntakeQueueStatus.completed);
      reloaded.dispose();
    });

    test('when both files are unreadable, both are kept aside and the queue starts empty', () async {
      final dir = Directory('${root.path}/q')..createSync(recursive: true);
      File('${dir.path}/queue.json').writeAsStringSync('not json');
      File('${dir.path}/queue.json.bak').writeAsStringSync('{also not a list');

      final q = OfflineIntakeQueue(storageDir: dir);
      await q.initialize();
      expect(q.items, isEmpty);
      final names = dir.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toList();
      expect(names.where((n) => n.startsWith('queue.json.corrupt-')), hasLength(1));
      expect(names.where((n) => n.startsWith('queue.json.bak.corrupt-')), hasLength(1));
      q.dispose();
    });
  });

  group('migration from the old temp location', () {
    test('moves the manifest and photos, rewrites photo paths and removes the old folder', () async {
      final legacy = Directory('${root.path}/legacy_tmp/livedrop_intake_queue');
      final legacyImages = Directory('${legacy.path}/images')..createSync(recursive: true);
      final photo0 = File('${legacyImages.path}/queue_1_0.jpg')..writeAsBytesSync(_jpeg(1));
      final photo1 = File('${legacyImages.path}/queue_1_1.jpg')..writeAsBytesSync(_jpeg(2));
      File('${legacy.path}/queue.json').writeAsStringSync(jsonEncode([
        _legacyEntry(id: 'queue_1', code: '#B01', localPaths: [photo0.path, photo1.path]),
      ]));

      final support = Directory('${root.path}/support')..createSync();
      final q = OfflineIntakeQueue(supportDirProvider: () async => support, legacyDir: legacy);
      await q.initialize();

      final item = q.items.single;
      expect(item.id, 'queue_1');
      expect(item.code, '#B01');
      for (final path in item.localImagePaths) {
        expect(path, startsWith('${q.baseDir.path}/images/'));
        expect(File(path).existsSync(), isTrue);
      }
      expect(File(item.localImagePaths[0]).readAsBytesSync(), _jpeg(1));
      expect(File(item.localImagePaths[1]).readAsBytesSync(), _jpeg(2));
      expect(legacy.existsSync(), isFalse);
      expect(_readJsonList(File('${q.baseDir.path}/queue.json')), hasLength(1));

      // Migrated pieces upload from their new location.
      final repo = _UploadRepo();
      await q.processQueue(repo);
      expect(q.items.single.status, IntakeQueueStatus.completed);
      expect(repo.uploadedBytes, [_jpeg(1), _jpeg(2)]);
      q.dispose();
    });

    test('merges with an existing durable queue without duplicating items', () async {
      final dir = Directory('${root.path}/durable');
      final first = OfflineIntakeQueue(storageDir: dir);
      await first.initialize();
      final existing =
          await first.enqueue(dropId: 'd1', code: '#A01', title: 'Kept', pricePaisa: 100000, size: 'M', imageBytes: _jpeg());
      first.dispose();

      final legacy = Directory('${root.path}/legacy');
      final legacyImages = Directory('${legacy.path}/images')..createSync(recursive: true);
      final photo = File('${legacyImages.path}/queue_9_0.jpg')..writeAsBytesSync(_jpeg(9));
      File('${legacy.path}/queue.json').writeAsStringSync(jsonEncode([
        _legacyEntry(id: existing.id, code: '#A01', localPaths: [existing.localImagePath]),
        _legacyEntry(id: 'queue_9', code: '#C09', localPaths: [photo.path]),
      ]));

      final q = OfflineIntakeQueue(storageDir: dir, legacyDir: legacy);
      await q.initialize();
      expect(q.items.map((i) => i.id), [existing.id, 'queue_9']);
      expect(q.items.last.localImagePath, '${dir.path}/images/queue_9_0.jpg');
      expect(legacy.existsSync(), isFalse);
      q.dispose();
    });

    test('an unreadable legacy manifest is preserved in the new folder, photos are copied', () async {
      final legacy = Directory('${root.path}/legacy');
      final legacyImages = Directory('${legacy.path}/images')..createSync(recursive: true);
      File('${legacyImages.path}/queue_5_0.jpg').writeAsBytesSync(_jpeg(5));
      File('${legacy.path}/queue.json').writeAsStringSync('[{"broken');

      final dir = Directory('${root.path}/durable');
      final q = OfflineIntakeQueue(storageDir: dir, legacyDir: legacy);
      await q.initialize();
      expect(q.items, isEmpty);
      expect(File('${dir.path}/images/queue_5_0.jpg').existsSync(), isTrue);
      final kept = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('queue.json.legacy.corrupt-'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single.readAsStringSync(), '[{"broken');
      q.dispose();
    });
  });
}
