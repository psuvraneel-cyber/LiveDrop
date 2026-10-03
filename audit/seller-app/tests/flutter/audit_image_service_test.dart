// AUDIT-ONLY tests for ImageService (seller-app/lib/core/services/image_service.dart)
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:seller_app/core/services/image_service.dart';

Uint8List _photo({required int w, required int h, int? orientation, bool gps = false}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  // red band across the TOP of the stored pixels
  img.fillRect(im, x1: 0, y1: 0, x2: w - 1, y2: (h * 0.1).round(), color: img.ColorRgb8(255, 0, 0));
  im.exif.imageIfd.make = 'AuditCam';
  if (orientation != null) im.exif.imageIfd.orientation = orientation;
  if (gps) {
    im.exif.gpsIfd.gpsLatitude = 22.5726;
    im.exif.gpsIfd.gpsLatitudeRef = 'N';
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  const service = ImageService();

  test('SA-AUD-T22: EXIF orientation is applied during decode (rotated photos stay upright)', () async {
    // orientation 6 = rotate 90° CW for display: the stored top band must end up on the RIGHT edge.
    final out = await service.processIntakeImage(_photo(w: 400, h: 300, orientation: 6));
    final decoded = img.decodeJpg(out.bytes)!;
    final right = decoded.getPixel(decoded.width - 2, decoded.height ~/ 2);
    final left = decoded.getPixel(1, decoded.height ~/ 2);
    // ignore: avoid_print
    print('AUDIT T22 out=${out.width}x${out.height} bytes=${out.sizeInBytes} rightPixel=${right.r},${right.g},${right.b} leftPixel=${left.r},${left.g},${left.b}');
    expect(right.r > 200 && right.g < 80, isTrue, reason: 'band should be on the right after applying orientation');
  });

  test('SA-AUD-T23: camera/gallery EXIF (device, GPS) survives compression and is published with the image', () async {
    final out = await service.processIntakeImage(_photo(w: 1600, h: 1200, gps: true));
    final decoded = img.decodeJpg(out.bytes)!;
    // ignore: avoid_print
    print('AUDIT T23 make=${decoded.exif.imageIfd.make} gpsLatitude=${decoded.exif.gpsIfd.gpsLatitude} size=${out.width}x${out.height} ${out.sizeInBytes}B mime=${out.mimeType}');
    expect(decoded.exif.imageIfd.make, 'AuditCam');
    expect(decoded.exif.gpsIfd.gpsLatitude, isNotNull);
    expect(out.mimeType, 'image/jpeg'); // spec/ADR-005 says WebP < 200 KB
    expect(out.width, 1200);
  });
}
