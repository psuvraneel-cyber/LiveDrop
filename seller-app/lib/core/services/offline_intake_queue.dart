import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/repositories/seller_repository.dart';

enum IntakeQueueStatus { pending, uploading, uploaded, failed, completed }

class IntakeQueueItem {
  final String id;
  final String dropId;
  final String code;
  final String title;
  final int pricePaisa;
  final String size;
  final List<String> localImagePaths;
  List<String> remoteImageUrls;
  IntakeQueueStatus status;
  int retryCount;
  String? lastError;
  final DateTime createdAt;
  DateTime updatedAt;

  // Backward-compatible accessors
  String get localImagePath =>
      localImagePaths.isNotEmpty ? localImagePaths.first : '';
  String? get remoteImageUrl =>
      remoteImageUrls.isNotEmpty ? remoteImageUrls.first : null;
  set remoteImageUrl(String? url) {
    if (url != null) {
      if (remoteImageUrls.isEmpty) {
        remoteImageUrls = [url];
      } else {
        remoteImageUrls[0] = url;
      }
    }
  }

  IntakeQueueItem({
    required this.id,
    required this.dropId,
    required this.code,
    required this.title,
    required this.pricePaisa,
    required this.size,
    List<String>? localImagePaths,
    String? localImagePath,
    List<String>? remoteImageUrls,
    String? remoteImageUrl,
    this.status = IntakeQueueStatus.pending,
    this.retryCount = 0,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  })  : localImagePaths = localImagePaths ??
            (localImagePath != null && localImagePath.isNotEmpty
                ? [localImagePath]
                : const []),
        remoteImageUrls = remoteImageUrls ??
            (remoteImageUrl != null && remoteImageUrl.isNotEmpty
                ? [remoteImageUrl]
                : []);

  Map<String, dynamic> toJson() => {
    'id': id,
    'drop_id': dropId,
    'code': code,
    'title': title,
    'price_paisa': pricePaisa,
    'size': size,
    'local_image_path': localImagePath,
    'local_image_paths': localImagePaths,
    'remote_image_url': remoteImageUrl,
    'remote_image_urls': remoteImageUrls,
    'status': status.name,
    'retry_count': retryCount,
    'last_error': lastError,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory IntakeQueueItem.fromJson(Map<String, dynamic> json) {
    final rawLocalPaths = json['local_image_paths'];
    List<String> localPaths = [];
    if (rawLocalPaths is List) {
      localPaths = rawLocalPaths.map((e) => e.toString()).toList();
    } else if (json['local_image_path'] != null) {
      localPaths = [json['local_image_path'] as String];
    }

    final rawRemoteUrls = json['remote_image_urls'];
    List<String> remoteUrls = [];
    if (rawRemoteUrls is List) {
      remoteUrls = rawRemoteUrls.map((e) => e.toString()).toList();
    } else if (json['remote_image_url'] != null) {
      remoteUrls = [json['remote_image_url'] as String];
    }

    return IntakeQueueItem(
      id: json['id'] as String,
      dropId: json['drop_id'] as String,
      code: json['code'] as String,
      title: json['title'] as String,
      pricePaisa: json['price_paisa'] as int,
      size: json['size'] as String,
      localImagePaths: localPaths,
      remoteImageUrls: remoteUrls,
      status: IntakeQueueStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => IntakeQueueStatus.pending,
      ),
      retryCount: json['retry_count'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Durable Offline Intake Queue
/// Persists captured garment photos to disk before network dispatch.
/// Survives app process termination and resumes queued uploads via exponential backoff.
class OfflineIntakeQueue {
  final Directory baseDir;
  final List<IntakeQueueItem> _items = [];
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  bool _isProcessing = false;
  Timer? _retryTimer;

  OfflineIntakeQueue({Directory? storageDir})
    : baseDir =
          storageDir ??
          Directory('${Directory.systemTemp.path}/livedrop_intake_queue');

  List<IntakeQueueItem> get items => List.unmodifiable(_items);

  int get pendingCount => _items
      .where(
        (item) =>
            item.status == IntakeQueueStatus.pending ||
            item.status == IntakeQueueStatus.uploading ||
            item.status == IntakeQueueStatus.uploaded ||
            item.status == IntakeQueueStatus.failed,
      )
      .length;

  int get failedCount =>
      _items.where((item) => item.status == IntakeQueueStatus.failed).length;

  Future<void> initialize() async {
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    final imagesDir = Directory('${baseDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final manifestFile = File('${baseDir.path}/queue.json');
    if (await manifestFile.exists()) {
      try {
        final content = await manifestFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _items.clear();
        for (final entry in list) {
          _items.add(IntakeQueueItem.fromJson(entry as Map<String, dynamic>));
        }
      } catch (_) {
        // Safe fallback if manifest unreadable
      }
    }
    _updateNotifier();
  }

  Future<void> _saveManifest() async {
    final manifestFile = File('${baseDir.path}/queue.json');
    final data = jsonEncode(_items.map((i) => i.toJson()).toList());
    await manifestFile.writeAsString(data, flush: true);
    _updateNotifier();
  }

  void _updateNotifier() {
    pendingCountNotifier.value = pendingCount;
  }

  /// Saves raw image bytes to disk and queues metadata with status = pending.
  /// Accepts single [imageBytes] or multiple [imageBytesList] for angles.
  Future<IntakeQueueItem> enqueue({
    required String dropId,
    required String code,
    required String title,
    required int pricePaisa,
    required String size,
    Uint8List? imageBytes,
    List<Uint8List>? imageBytesList,
  }) async {
    final list = imageBytesList ??
        (imageBytes != null ? [imageBytes] : <Uint8List>[]);
    if (list.isEmpty) {
      throw ArgumentError('At least one image is required to enqueue');
    }

    final id =
        'queue_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final imagesDir = Directory('${baseDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final savedPaths = <String>[];
    for (int i = 0; i < list.length; i++) {
      final imageFile = File('${imagesDir.path}/${id}_$i.jpg');
      await imageFile.writeAsBytes(list[i], flush: true);
      savedPaths.add(imageFile.path);
    }

    final item = IntakeQueueItem(
      id: id,
      dropId: dropId,
      code: code,
      title: title,
      pricePaisa: pricePaisa,
      size: size,
      localImagePaths: savedPaths,
      status: IntakeQueueStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _items.add(item);
    await _saveManifest();
    return item;
  }

  /// Retries all pending and failed queue items against the backend.
  Future<void> processQueue(SellerRepository repository) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final pendingItems = _items
          .where(
            (i) =>
                i.status == IntakeQueueStatus.pending ||
                i.status == IntakeQueueStatus.failed ||
                i.status == IntakeQueueStatus.uploading ||
                i.status == IntakeQueueStatus.uploaded,
          )
          .toList();

      for (final item in pendingItems) {
        try {
          item.status = IntakeQueueStatus.uploading;
          item.updatedAt = DateTime.now();
          await _saveManifest();

          // Step 1: Upload each image angle that hasn't been uploaded yet
          while (item.remoteImageUrls.length < item.localImagePaths.length) {
            final idx = item.remoteImageUrls.length;
            final localPath = item.localImagePaths[idx];
            final file = File(localPath);
            if (!await file.exists()) {
              item.status = IntakeQueueStatus.failed;
              item.lastError = 'Local image file not found on disk: $localPath';
              await _saveManifest();
              break;
            }

            final bytes = await file.readAsBytes();
            final fileName = '${item.code}_${item.id}_$idx.jpg';
            final url = await repository.uploadProductImage(
              dropId: item.dropId,
              fileName: fileName,
              imageBytes: bytes,
              contentType: 'image/jpeg',
            );
            item.remoteImageUrls.add(url);
            item.updatedAt = DateTime.now();
            await _saveManifest();
          }

          if (item.remoteImageUrls.length < item.localImagePaths.length) {
            continue; // Skipped due to file error
          }

          item.status = IntakeQueueStatus.uploaded;
          await _saveManifest();

          // Step 2: Create product in database
          final primaryUrl = item.remoteImageUrls.isNotEmpty
              ? item.remoteImageUrls.first
              : '';
          await repository.createProduct(
            dropId: item.dropId,
            code: item.code,
            title: item.title,
            pricePaisa: item.pricePaisa,
            size: item.size,
            imageUrl: primaryUrl,
            imageUrls: item.remoteImageUrls,
          );

          item.status = IntakeQueueStatus.completed;
          item.updatedAt = DateTime.now();
          await _saveManifest();
        } catch (err) {
          item.retryCount += 1;
          item.status = IntakeQueueStatus.failed;
          item.lastError = err.toString();
          item.updatedAt = DateTime.now();
          await _saveManifest();

          _scheduleRetry(repository, item.retryCount);
        }
      }
    } finally {
      _isProcessing = false;
      _updateNotifier();
    }
  }

  /// Manually trigger retry for all failed queue items.
  Future<void> retryFailed(SellerRepository repository) async {
    for (final item in _items) {
      if (item.status == IntakeQueueStatus.failed) {
        item.status = IntakeQueueStatus.pending;
      }
    }
    await _saveManifest();
    await processQueue(repository);
  }

  void _scheduleRetry(SellerRepository repository, int retryCount) {
    _retryTimer?.cancel();
    final baseSeconds = min(60, pow(2, min(retryCount, 6)).toInt());
    final jitterSeconds = Random().nextInt(4);
    final delay = Duration(seconds: baseSeconds + jitterSeconds);

    _retryTimer = Timer(delay, () {
      processQueue(repository);
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    pendingCountNotifier.dispose();
  }
}
