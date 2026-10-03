import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../errors/exceptions.dart';
import '../validation/product_rules.dart';
import 'intake_error_classifier.dart';

/// Lifecycle of a captured piece on this phone.
///
/// * `pending` / `uploading` / `uploaded` — syncing (not yet live).
/// * `failed` — a transient failure (network, timeout, 5xx); retried with backoff.
/// * `needsAttention` — a permanent failure (invalid code, duplicate code,
///   permission…). Never retried automatically; the seller edits or discards it.
/// * `completed` — the product exists on the server.
enum IntakeQueueStatus { pending, uploading, uploaded, failed, needsAttention, completed }

class IntakeQueueItem {
  final String id;
  final String dropId;
  String code;
  String title;
  int pricePaisa;
  String size;
  final List<String> localImagePaths;
  List<String> remoteImageUrls;
  IntakeQueueStatus status;
  int retryCount;
  String? lastError;

  /// Seller-facing reason when [status] is [IntakeQueueStatus.needsAttention].
  String? attentionReason;

  /// SQLSTATE / HTTP / app code of the last failure, when known.
  String? errorCode;

  /// Server product id once the piece is live.
  String? serverProductId;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Bumped whenever the seller edits or explicitly retries the item so a
  /// running sync picks it up again (not persisted).
  int localRevision = 0;

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

  bool get isSyncing =>
      status == IntakeQueueStatus.pending ||
      status == IntakeQueueStatus.uploading ||
      status == IntakeQueueStatus.uploaded;

  bool get isInFlight =>
      status == IntakeQueueStatus.uploading || status == IntakeQueueStatus.uploaded;

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
    this.attentionReason,
    this.errorCode,
    this.serverProductId,
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
    'attention_reason': attentionReason,
    'error_code': errorCode,
    'server_product_id': serverProductId,
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
      attentionReason: json['attention_reason'] as String?,
      errorCode: json['error_code'] as String?,
      serverProductId: json['server_product_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Durable Offline Intake Queue
/// Persists captured garment photos to disk before network dispatch.
/// Survives app process termination and resumes queued uploads via exponential backoff.
///
/// Failures are classified (SA-INT-001): transient ones are retried with
/// backoff; permanent ones (validation, duplicate code, permission) move the
/// piece to [IntakeQueueStatus.needsAttention] with a human-readable reason and
/// are never retried automatically.
class OfflineIntakeQueue {
  final Directory baseDir;
  final List<IntakeQueueItem> _items = [];
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  /// Bumped on every change of any item (status, fields, add, discard).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  bool _isProcessing = false;
  bool _rerunRequested = false;
  bool _disposed = false;
  Timer? _retryTimer;
  Future<void>? _initFuture;
  Future<void> _manifestWrites = Future<void>.value();

  OfflineIntakeQueue({Directory? storageDir})
    : baseDir =
          storageDir ??
          Directory('${Directory.systemTemp.path}/livedrop_intake_queue');

  List<IntakeQueueItem> get items => List.unmodifiable(_items);

  /// Pieces that are not live yet (syncing, retrying or needing attention).
  int get pendingCount =>
      _items.where((item) => item.status != IntakeQueueStatus.completed).length;

  /// Pieces waiting for / in the middle of an upload.
  int get syncingCount => _items.where((item) => item.isSyncing).length;

  /// Pieces that hit a transient failure and will be retried automatically.
  int get failedCount =>
      _items.where((item) => item.status == IntakeQueueStatus.failed).length;

  /// Pieces the seller must fix (edit or discard).
  int get needsAttentionCount => _items
      .where((item) => item.status == IntakeQueueStatus.needsAttention)
      .length;

  bool get isProcessing => _isProcessing;

  /// True while an automatic retry is scheduled.
  @visibleForTesting
  bool get hasScheduledRetry => _retryTimer?.isActive ?? false;

  /// Loads the manifest once. Later calls (e.g. every time the camera screen
  /// opens on the shared queue) are no-ops, so a running sync never loses its
  /// in-memory progress.
  Future<void> initialize() {
    return _initFuture ??= _loadFromDisk().catchError((Object error, StackTrace stack) {
      _initFuture = null; // allow another attempt after an I/O failure
      return Future<void>.error(error, stack);
    });
  }

  Future<void> _loadFromDisk() async {
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

  /// Seller edits / discards can now happen while a sync is saving progress,
  /// so manifest writes are serialised (each write snapshots the latest
  /// in-memory state) and atomic (temp file + rename), never interleaved.
  Future<void> _saveManifest() {
    final write = _manifestWrites.then((_) => _writeManifestNow());
    _manifestWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _writeManifestNow() async {
    final manifestFile = File('${baseDir.path}/queue.json');
    final tempFile = File('${baseDir.path}/queue.json.tmp');
    final data = jsonEncode(_items.map((i) => i.toJson()).toList());
    await tempFile.writeAsString(data, flush: true);
    await tempFile.rename(manifestFile.path);
    _updateNotifier();
  }

  void _updateNotifier() {
    if (_disposed) return;
    pendingCountNotifier.value = pendingCount;
    changes.value = changes.value + 1;
  }

  IntakeQueueItem? itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Saves raw image bytes to disk and queues metadata with status = pending.
  /// Accepts single [imageBytes] or multiple [imageBytesList] for angles.
  ///
  /// The code is normalised (`a01` → `#A01`) and the piece is validated with
  /// [ProductRules]; invalid input throws a [LiveDropException] with code
  /// `INVALID_PRODUCT_INPUT` and nothing is queued.
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

    final normalizedCode = ProductRules.normalizeCode(code);
    final errors = ProductRules.validatePiece(
      code: normalizedCode,
      title: title,
      size: size,
      pricePaisa: pricePaisa,
    );
    if (errors.isNotEmpty) {
      throw LiveDropException(errors.values.first, code: 'INVALID_PRODUCT_INPUT');
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
      code: normalizedCode,
      title: title.trim(),
      pricePaisa: pricePaisa,
      size: size.trim(),
      localImagePaths: savedPaths,
      status: IntakeQueueStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _items.add(item);
    await _saveManifest();
    return item;
  }

  /// Seller edit of a piece that needs attention (or is waiting to retry).
  /// Validates like [enqueue], clears the failure and re-queues the piece.
  /// Photos already uploaded are kept. Call [processQueue] afterwards.
  Future<IntakeQueueItem> updateItem(
    String id, {
    required String code,
    required String title,
    required int pricePaisa,
    required String size,
  }) async {
    final item = itemById(id);
    if (item == null) {
      throw const LiveDropException('This piece is no longer in the queue.', code: 'QUEUE_ITEM_NOT_FOUND');
    }
    if (item.isInFlight || item.status == IntakeQueueStatus.completed) {
      throw const LiveDropException(
        'This piece is uploading right now and cannot be edited.',
        code: 'QUEUE_ITEM_BUSY',
      );
    }
    final normalizedCode = ProductRules.normalizeCode(code);
    final errors = ProductRules.validatePiece(
      code: normalizedCode,
      title: title,
      size: size,
      pricePaisa: pricePaisa,
    );
    if (errors.isNotEmpty) {
      throw LiveDropException(errors.values.first, code: 'INVALID_PRODUCT_INPUT');
    }

    item
      ..code = normalizedCode
      ..title = title.trim()
      ..pricePaisa = pricePaisa
      ..size = size.trim()
      ..status = IntakeQueueStatus.pending
      ..attentionReason = null
      ..errorCode = null
      ..lastError = null
      ..retryCount = 0
      ..localRevision += 1
      ..updatedAt = DateTime.now();
    await _saveManifest();
    return item;
  }

  /// Retries one piece (e.g. after a permission problem was fixed elsewhere).
  Future<void> retryItem(String id, SellerRepository repository) async {
    final item = itemById(id);
    if (item == null || item.isInFlight || item.status == IntakeQueueStatus.completed) {
      return;
    }
    item
      ..status = IntakeQueueStatus.pending
      ..attentionReason = null
      ..localRevision += 1
      ..updatedAt = DateTime.now();
    await _saveManifest();
    await processQueue(repository);
  }

  /// Removes a piece that is not live and deletes its local photos.
  /// Returns false when the piece is uploading right now.
  Future<bool> discardItem(String id) async {
    final item = itemById(id);
    if (item == null) return true;
    if (item.isInFlight) return false;
    _items.remove(item);
    for (final path in item.localImagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A leftover temp photo is harmless; the manifest no longer references it.
      }
    }
    await _saveManifest();
    return true;
  }

  static bool _isProcessable(IntakeQueueItem item) =>
      item.status == IntakeQueueStatus.pending ||
      item.status == IntakeQueueStatus.failed ||
      item.status == IntakeQueueStatus.uploading ||
      item.status == IntakeQueueStatus.uploaded;

  /// Uploads every syncing / retrying piece. Pieces that need attention are
  /// skipped until the seller edits or retries them. Items added or edited
  /// while a run is in progress are picked up by the same run.
  Future<void> processQueue(SellerRepository repository) async {
    if (_disposed) return;
    if (_isProcessing) {
      // e.g. the retry timer fired during a long run: run again afterwards so
      // the request is not lost.
      _rerunRequested = true;
      return;
    }
    _isProcessing = true;
    _rerunRequested = false;

    try {
      final attempted = <String>{};
      while (!_disposed) {
        final batch = _items
            .where((i) => _isProcessable(i) && !attempted.contains('${i.id}:${i.localRevision}'))
            .toList();
        if (batch.isEmpty) break;

        for (final item in batch) {
          if (_disposed) break;
          if (!_items.contains(item) || !_isProcessable(item)) continue;
          attempted.add('${item.id}:${item.localRevision}');
          await _processItem(item, repository);
        }
      }
    } finally {
      _isProcessing = false;
      _updateNotifier();
      if (_rerunRequested && !_disposed) {
        _rerunRequested = false;
        unawaited(processQueue(repository));
      }
    }
  }

  Future<void> _processItem(IntakeQueueItem item, SellerRepository repository) async {
    // Step 0: pre-flight validation (pieces queued by older app versions or
    // by other callers never reach the server with an invalid code).
    item.code = ProductRules.normalizeCode(item.code);
    final errors = ProductRules.validatePiece(
      code: item.code,
      title: item.title,
      size: item.size,
      pricePaisa: item.pricePaisa,
    );
    if (errors.isNotEmpty) {
      _markNeedsAttention(item, errors.values.first, code: 'INVALID_PRODUCT_INPUT');
      await _saveManifest();
      return;
    }

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
          _markNeedsAttention(
            item,
            'A photo of this piece is missing on this phone. Discard it and capture it again.',
            code: 'LOCAL_PHOTO_MISSING',
          );
          item.lastError = 'Local image file not found on disk: $localPath';
          await _saveManifest();
          return;
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

      if (item.remoteImageUrls.isEmpty) {
        _markNeedsAttention(
          item,
          'This piece has no photo. Discard it and capture it again.',
          code: 'LOCAL_PHOTO_MISSING',
        );
        await _saveManifest();
        return;
      }

      item.status = IntakeQueueStatus.uploaded;
      await _saveManifest();

      // Step 2: Create product in database
      final primaryUrl = item.remoteImageUrls.first;
      SellerProduct created;
      try {
        created = await repository.createProduct(
          dropId: item.dropId,
          code: item.code,
          title: item.title,
          pricePaisa: item.pricePaisa,
          size: item.size,
          imageUrl: primaryUrl,
          imageUrls: item.remoteImageUrls,
        );
      } catch (err) {
        final failure = IntakeErrorClassifier.classify(err, productCode: item.code);
        if (failure.kind != IntakeFailureKind.duplicateCode) rethrow;

        // UNIQUE(drop_id, code): if the product carrying *our* uploaded photos
        // already exists, an earlier create committed but its response was
        // lost — the piece is live, so this is a success (idempotent replay).
        final existing = await repository.findProductByCode(
          dropId: item.dropId,
          code: item.code,
        );
        if (existing != null && _isSameUpload(existing, item)) {
          _markCompleted(item, existing.id);
          await _saveManifest();
          return;
        }
        _markNeedsAttention(item, failure.reason, code: failure.code, error: err);
        await _saveManifest();
        return;
      }

      _markCompleted(item, created.id);
      await _saveManifest();
    } catch (err) {
      final failure = IntakeErrorClassifier.classify(err, productCode: item.code);
      if (failure.kind == IntakeFailureKind.transient) {
        item.retryCount += 1;
        item.status = IntakeQueueStatus.failed;
        item.lastError = err.toString();
        item.errorCode = failure.code;
        item.attentionReason = null;
        item.updatedAt = DateTime.now();
        await _saveManifest();
        _scheduleRetry(repository, item.retryCount);
      } else {
        _markNeedsAttention(item, failure.reason, code: failure.code, error: err);
        await _saveManifest();
      }
    }
  }

  static bool _isSameUpload(SellerProduct existing, IntakeQueueItem item) {
    final ours = item.remoteImageUrls.toSet();
    if (ours.isEmpty) return false;
    return ours.contains(existing.imageUrl) || existing.imageUrls.any(ours.contains);
  }

  void _markCompleted(IntakeQueueItem item, String productId) {
    item
      ..status = IntakeQueueStatus.completed
      ..serverProductId = productId
      ..attentionReason = null
      ..errorCode = null
      ..lastError = null
      ..updatedAt = DateTime.now();
  }

  void _markNeedsAttention(IntakeQueueItem item, String reason, {String? code, Object? error}) {
    item
      ..status = IntakeQueueStatus.needsAttention
      ..attentionReason = reason
      ..errorCode = code
      ..lastError = error?.toString() ?? reason
      ..updatedAt = DateTime.now();
  }

  /// Manually trigger retry for all items waiting on a transient failure.
  /// Pieces that need attention are not touched (they need an edit first).
  Future<void> retryFailed(SellerRepository repository) async {
    for (final item in _items) {
      if (item.status == IntakeQueueStatus.failed) {
        item.status = IntakeQueueStatus.pending;
        item.localRevision += 1;
      }
    }
    await _saveManifest();
    await processQueue(repository);
  }

  void _scheduleRetry(SellerRepository repository, int retryCount) {
    if (_disposed) return;
    _retryTimer?.cancel();
    final baseSeconds = min(60, pow(2, min(retryCount, 6)).toInt());
    final jitterSeconds = Random().nextInt(4);
    final delay = Duration(seconds: baseSeconds + jitterSeconds);

    _retryTimer = Timer(delay, () {
      processQueue(repository);
    });
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    pendingCountNotifier.dispose();
    changes.dispose();
  }
}
