import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// LiveDrop Seller Mobile App — Image Processing Service
///
/// Handles high-performance 1:1 center cropping, scaling to <= 1200px,
/// and WebP/JPEG compression offloaded to background isolates (compute).
class ProcessedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final String mimeType;
  final int sizeInBytes;

  const ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.sizeInBytes,
  });
}

class _CropTaskParams {
  final Uint8List rawBytes;
  final int maxDimension;
  final int quality;

  const _CropTaskParams({
    required this.rawBytes,
    this.maxDimension = 1200,
    this.quality = 85,
  });
}

/// Pure top-level worker function for background isolate execution.
ProcessedImage _isolateCropAndCompress(_CropTaskParams params) {
  final original = img.decodeImage(params.rawBytes);
  if (original == null) {
    throw Exception('Failed to decode camera image.');
  }

  // 1. Calculate 1:1 Center Square Crop
  final width = original.width;
  final height = original.height;
  final cropSize = width < height ? width : height;
  final cropX = (width - cropSize) ~/ 2;
  final cropY = (height - cropSize) ~/ 2;

  final cropped = img.copyCrop(
    original,
    x: cropX,
    y: cropY,
    width: cropSize,
    height: cropSize,
  );

  // 2. Scale down if larger than maxDimension (1200px)
  final targetSize = cropSize > params.maxDimension
      ? params.maxDimension
      : cropSize;
  final resized = targetSize < cropSize
      ? img.copyResize(
          cropped,
          width: targetSize,
          height: targetSize,
          interpolation: img.Interpolation.linear,
        )
      : cropped;

  // 3. Encode image (JPG or WebP fallback)
  // image package supports encodeJpg and encodePng; encodeJpg gives fast compression
  final compressedBytes = Uint8List.fromList(
    img.encodeJpg(resized, quality: params.quality),
  );

  return ProcessedImage(
    bytes: compressedBytes,
    width: resized.width,
    height: resized.height,
    mimeType: 'image/jpeg',
    sizeInBytes: compressedBytes.lengthInBytes,
  );
}

class ImageService {
  const ImageService();

  /// Processes raw camera / picker bytes off the UI thread via `compute()`.
  /// Performs 1:1 center crop, scales to <= [maxDimension] px, and compresses.
  Future<ProcessedImage> processIntakeImage(
    Uint8List rawBytes, {
    int maxDimension = 1200,
    int quality = 85,
  }) async {
    final params = _CropTaskParams(
      rawBytes: rawBytes,
      maxDimension: maxDimension,
      quality: quality,
    );

    return compute(_isolateCropAndCompress, params);
  }
}
