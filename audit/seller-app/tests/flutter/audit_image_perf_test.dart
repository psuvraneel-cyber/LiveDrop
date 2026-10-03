// AUDIT-ONLY micro-benchmark of ImageService on the dev host (Dart VM in `flutter test`).
// Device numbers will be slower (budget docs/22: compression < 600 ms on target phones).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:seller_app/core/services/image_service.dart';

Uint8List _photoLike(int w, int h) {
  final rnd = Random(42);
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // smooth gradient + texture noise ~ fabric photo entropy
      final n = rnd.nextInt(40);
      im.setPixelRgb(x, y, (x * 255 ~/ w + n) % 256, (y * 255 ~/ h + n) % 256, (n * 6) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

void main() {
  const service = ImageService();
  for (final size in const [[1280, 720], [4000, 3000]]) {
    test('SA-AUD-T24: processIntakeImage ${size[0]}x${size[1]}', () async {
      final raw = _photoLike(size[0], size[1]);
      final sw = Stopwatch()..start();
      final out = await service.processIntakeImage(raw);
      sw.stop();
      // ignore: avoid_print
      print('AUDIT T24 input=${size[0]}x${size[1]} ${(raw.length / 1024).round()}KB -> '
          '${out.width}x${out.height} ${(out.sizeInBytes / 1024).round()}KB ${out.mimeType} in ${sw.elapsedMilliseconds} ms (dev host)');
      expect(out.width, lessThanOrEqualTo(1200));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
