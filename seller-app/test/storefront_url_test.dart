import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/config/env_config.dart';

void main() {
  group('EnvConfig.getStorefrontUrl', () {
    test('generates canonical storefront URL matching production free Vercel domain', () {
      final url = EnvConfig.getStorefrontUrl('suv-s');
      expect(url, equals('https://livedrop-in.vercel.app/suv-s'));
    });

    test('handles leading slash in store slug correctly', () {
      final url = EnvConfig.getStorefrontUrl('/anita-silks');
      expect(url, equals('https://livedrop-in.vercel.app/anita-silks'));
    });

    test('handles clean store slugs without leading slash', () {
      final url = EnvConfig.getStorefrontUrl('priya-boutique');
      expect(url, equals('https://livedrop-in.vercel.app/priya-boutique'));
    });

    test('handles trailing slashes in store slug correctly', () {
      final url = EnvConfig.getStorefrontUrl('suv-s/');
      expect(url, equals('https://livedrop-in.vercel.app/suv-s'));
    });

    test('handles multiple leading and trailing slashes correctly', () {
      final url = EnvConfig.getStorefrontUrl('///suv-s///');
      expect(url, equals('https://livedrop-in.vercel.app/suv-s'));
    });

    test('handles whitespace surrounding store slug correctly', () {
      final url = EnvConfig.getStorefrontUrl('  suv-s  ');
      expect(url, equals('https://livedrop-in.vercel.app/suv-s'));
    });
  });
}
