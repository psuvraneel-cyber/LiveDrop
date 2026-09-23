import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/services/offline_intake_queue.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';

class FakeSellerRepository implements SellerRepository {
  final List<Map<String, dynamic>> uploadedImages = [];
  final List<SellerProduct> createdProducts = [];
  bool shouldFailUpload = false;
  bool shouldFailCreate = false;

  @override
  Future<String> uploadProductImage({
    required String dropId,
    required String fileName,
    required Uint8List imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    if (shouldFailUpload) {
      throw Exception('Network unreachable: connection timed out');
    }
    uploadedImages.add({'dropId': dropId, 'fileName': fileName, 'bytes': imageBytes});
    return 'https://storage.livedrop.store/$dropId/$fileName';
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
    if (shouldFailCreate) {
      throw Exception('Database connection refused');
    }
    final prod = SellerProduct(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      dropId: dropId,
      code: code,
      title: title,
      pricePaisa: pricePaisa,
      size: size,
      status: ProductStatus.available,
      imageUrl: imageUrl,
      imageUrls: imageUrls ?? [imageUrl],
      version: 1,
    );
    createdProducts.add(prod);
    return prod;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late FakeSellerRepository fakeRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('intake_queue_test_');
    fakeRepo = FakeSellerRepository();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Blocker 1G: Offline Intake Queue Reliability Tests', () {
    test('enqueue persists raw image bytes to disk and writes manifest', () async {
      final queue = OfflineIntakeQueue(storageDir: tempDir);
      await queue.initialize();

      expect(queue.pendingCount, 0);

      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final item = await queue.enqueue(
        dropId: 'drop-123',
        code: 'A01',
        title: 'Banarasi Silk Saree',
        pricePaisa: 150000,
        size: 'Free Size',
        imageBytes: dummyBytes,
      );

      expect(item.code, 'A01');
      expect(item.status, IntakeQueueStatus.pending);
      expect(queue.pendingCount, 1);
      expect(queue.pendingCountNotifier.value, 1);

      // Verify file persisted on disk
      final imageFile = File(item.localImagePath);
      expect(await imageFile.exists(), true);
      expect(await imageFile.readAsBytes(), dummyBytes);

      // Verify manifest persisted
      final manifestFile = File('${tempDir.path}/queue.json');
      expect(await manifestFile.exists(), true);

      queue.dispose();
    });

    test('reloading queue from disk recovers persisted state after simulated restart', () async {
      final queue1 = OfflineIntakeQueue(storageDir: tempDir);
      await queue1.initialize();

      final dummyBytes = Uint8List.fromList([10, 20, 30, 40]);
      await queue1.enqueue(
        dropId: 'drop-123',
        code: 'B01',
        title: 'Chanderi Kurti',
        pricePaisa: 95000,
        size: 'M',
        imageBytes: dummyBytes,
      );
      queue1.dispose();

      // Simulate app restart by instantiating new queue pointing to same directory
      final queue2 = OfflineIntakeQueue(storageDir: tempDir);
      await queue2.initialize();

      expect(queue2.items.length, 1);
      expect(queue2.pendingCount, 1);
      expect(queue2.items.first.code, 'B01');
      expect(queue2.items.first.title, 'Chanderi Kurti');
      expect(queue2.items.first.pricePaisa, 95000);

      queue2.dispose();
    });

    test('processQueue successfully uploads image and creates product in database', () async {
      final queue = OfflineIntakeQueue(storageDir: tempDir);
      await queue.initialize();

      final dummyBytes = Uint8List.fromList([99, 88, 77]);
      await queue.enqueue(
        dropId: 'drop-456',
        code: 'C01',
        title: 'Kanjivaram Saree',
        pricePaisa: 250000,
        size: 'Free Size',
        imageBytes: dummyBytes,
      );

      await queue.processQueue(fakeRepo);

      expect(fakeRepo.uploadedImages.length, 1);
      expect(fakeRepo.uploadedImages.first['dropId'], 'drop-456');
      expect(fakeRepo.createdProducts.length, 1);
      expect(fakeRepo.createdProducts.first.code, 'C01');
      expect(fakeRepo.createdProducts.first.pricePaisa, 250000);

      expect(queue.pendingCount, 0);
      expect(queue.items.first.status, IntakeQueueStatus.completed);

      queue.dispose();
    });

    test('processQueue handles network failure gracefully and survives retry', () async {
      final queue = OfflineIntakeQueue(storageDir: tempDir);
      await queue.initialize();

      fakeRepo.shouldFailUpload = true;

      final dummyBytes = Uint8List.fromList([55, 66, 77]);
      await queue.enqueue(
        dropId: 'drop-789',
        code: 'D01',
        title: 'Handloom Dupatta',
        pricePaisa: 45000,
        size: 'Free Size',
        imageBytes: dummyBytes,
      );

      await queue.processQueue(fakeRepo);

      // Should be marked failed with retry count incremented
      expect(queue.items.first.status, IntakeQueueStatus.failed);
      expect(queue.items.first.retryCount, 1);
      expect(queue.items.first.lastError, contains('Network unreachable'));
      expect(queue.pendingCount, 1);

      // Now restore network connection and reprocess
      fakeRepo.shouldFailUpload = false;
      await queue.processQueue(fakeRepo);

      expect(queue.items.first.status, IntakeQueueStatus.completed);
      expect(queue.pendingCount, 0);
      expect(fakeRepo.createdProducts.length, 1);

      queue.dispose();
    });

    test('enqueue with multiple angles persists all images and uploads them in sequence', () async {
      final queue = OfflineIntakeQueue(storageDir: tempDir);
      await queue.initialize();

      final angle1 = Uint8List.fromList([1, 2, 3]);
      final angle2 = Uint8List.fromList([4, 5, 6]);
      final angle3 = Uint8List.fromList([7, 8, 9]);

      final item = await queue.enqueue(
        dropId: 'drop-multi',
        code: 'M01',
        title: 'Multi Angle Kurta',
        pricePaisa: 120000,
        size: 'L',
        imageBytes: angle1,
        imageBytesList: [angle1, angle2, angle3],
      );

      expect(item.localImagePaths.length, 3);
      expect(queue.items.first.localImagePaths.length, 3);

      await queue.processQueue(fakeRepo);

      expect(fakeRepo.uploadedImages.length, 3);
      expect(fakeRepo.createdProducts.length, 1);
      final created = fakeRepo.createdProducts.first;
      expect(created.imageUrls.length, 3);
      expect(created.imageUrl, created.imageUrls.first);

      queue.dispose();
    });
  });
}
