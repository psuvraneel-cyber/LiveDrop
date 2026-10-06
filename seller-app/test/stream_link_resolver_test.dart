// Facebook share links cannot be embedded; the app converts them to the full video address.
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/services/stream_link_resolver.dart';

void main() {
  const share = 'https://www.facebook.com/share/v/1Days6zufk/';
  const redirect =
      'https://www.facebook.com/sonali.paul.576482/videos/1811409706548049/?rdid=5WiaQT496KozVrbT&share_url=x';

  test('recognises share links and embeddable addresses', () {
    expect(StreamLinkResolver.isShareLink(share), isTrue);
    expect(StreamLinkResolver.isShareLink('https://fb.watch/abc123/'), isTrue);
    expect(StreamLinkResolver.isShareLink('https://www.facebook.com/page/videos/123/'), isFalse);
    expect(StreamLinkResolver.isEmbeddable('https://www.facebook.com/page/videos/123/'), isTrue);
    expect(StreamLinkResolver.isEmbeddable(share), isFalse);
  });

  test('a share link becomes the full video address without tracking parameters', () async {
    final r = StreamLinkResolver(fetchRedirect: (_) async => redirect);
    final result = await r.resolve(share);
    expect(result.converted, isTrue);
    expect(result.failed, isFalse);
    expect(result.url, 'https://www.facebook.com/sonali.paul.576482/videos/1811409706548049/');
  });

  test('follows a second hop (fb.watch → share → video)', () async {
    final hops = <String?>['https://www.facebook.com/share/v/xyz/', redirect];
    final r = StreamLinkResolver(fetchRedirect: (_) async => hops.removeAt(0));
    final result = await r.resolve('https://fb.watch/abc123/');
    expect(result.url, 'https://www.facebook.com/sonali.paul.576482/videos/1811409706548049/');
  });

  test('full addresses and other links are kept as they are', () async {
    var called = false;
    final r = StreamLinkResolver(fetchRedirect: (_) async {
      called = true;
      return null;
    });
    final result = await r.resolve(' https://www.facebook.com/page/videos/123/ ');
    expect(result.url, 'https://www.facebook.com/page/videos/123/');
    expect(result.converted, isFalse);
    expect(called, isFalse);
  });

  test('a share link that cannot be converted is reported, never thrown', () async {
    final noRedirect = await StreamLinkResolver(fetchRedirect: (_) async => null).resolve(share);
    expect(noRedirect.failed, isTrue);
    expect(noRedirect.url, share);
    final offline = await StreamLinkResolver(fetchRedirect: (_) async => throw Exception('offline')).resolve(share);
    expect(offline.failed, isTrue);
  });
}
