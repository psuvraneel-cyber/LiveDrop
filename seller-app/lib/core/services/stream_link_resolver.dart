import 'dart:async';
import 'dart:io';

import 'app_log.dart';

/// Turns the link a seller pastes for the drop's Facebook Live into one the
/// website can embed.
///
/// The Facebook app's "Share → Copy link" gives short share links
/// (`facebook.com/share/v/…`, `fb.watch/…`). Facebook's embed player cannot
/// play those ("Video unavailable"); it needs the full video address
/// (`facebook.com/<page>/videos/<id>/`). Facebook redirects a share link to
/// that address for a normal browser visit, so the app follows the redirect
/// once, from the seller's phone, when the drop is saved.
class StreamLinkResolver {
  StreamLinkResolver({Future<String?> Function(Uri uri)? fetchRedirect})
      : _fetchRedirect = fetchRedirect ?? _httpRedirect;

  final Future<String?> Function(Uri uri) _fetchRedirect;

  static final RegExp _shareLink = RegExp(
    r'^https?://((www|m|web)\.)?(facebook\.com/share/(v|r|p)/|fb\.watch/)',
    caseSensitive: false,
  );

  static final RegExp _embeddable = RegExp(
    r'^https://www\.facebook\.com/(([^/?#]+/videos/([^/?#]+/)?\d+)|watch/?\?v=\d+|reel/\d+)',
    caseSensitive: false,
  );

  /// True for share links the embed player cannot play.
  static bool isShareLink(String url) => _shareLink.hasMatch(url.trim());

  /// True for full video addresses the embed player can play.
  static bool isEmbeddable(String url) => _embeddable.hasMatch(url.trim());

  /// Returns the full video address for a share link, the link unchanged when
  /// it needs no conversion, or null when a share link could not be converted.
  Future<StreamLinkResult> resolve(String input) async {
    final url = input.trim();
    if (!isShareLink(url)) return StreamLinkResult(url, converted: false);
    try {
      var next = Uri.parse(url);
      // A share link can redirect more than once (fb.watch → share → video).
      for (var hop = 0; hop < 3; hop++) {
        final location = await _fetchRedirect(next).timeout(const Duration(seconds: 8));
        if (location == null) break;
        final target = next.resolve(location);
        final clean = _canonical(target);
        if (clean != null) return StreamLinkResult(clean, converted: true);
        next = target;
      }
    } catch (e, st) {
      AppLog.error('stream_link_resolver', e, st);
    }
    return StreamLinkResult(url, converted: false, failed: true);
  }

  /// `https://www.facebook.com/<page>/videos/<id>/` without tracking query.
  static String? _canonical(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!(host == 'facebook.com' || host.endsWith('.facebook.com'))) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final videos = segments.indexOf('videos');
    if (videos > 0 && videos + 1 < segments.length) {
      final id = segments.last;
      if (RegExp(r'^\d+$').hasMatch(id)) {
        return 'https://www.facebook.com/${segments[0]}/videos/$id/';
      }
    }
    final v = uri.queryParameters['v'];
    if (segments.isNotEmpty && segments.first == 'watch' && v != null && RegExp(r'^\d+$').hasMatch(v)) {
      return 'https://www.facebook.com/watch/?v=$v';
    }
    if (segments.length >= 2 && segments.first == 'reel' && RegExp(r'^\d+$').hasMatch(segments[1])) {
      return 'https://www.facebook.com/reel/${segments[1]}';
    }
    return null;
  }

  static Future<String?> _httpRedirect(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      // Facebook only redirects requests that look like a desktop browser visit.
      request.headers
        ..set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36')
        ..set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml')
        ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9')
        ..set('Sec-Fetch-Mode', 'navigate')
        ..set('Sec-Fetch-Dest', 'document');
      final response = await request.close();
      await response.drain<void>();
      return response.isRedirect ? response.headers.value(HttpHeaders.locationHeader) : null;
    } finally {
      client.close(force: true);
    }
  }
}

class StreamLinkResult {
  const StreamLinkResult(this.url, {required this.converted, this.failed = false});

  /// The link to save.
  final String url;

  /// A share link was replaced by the full video address.
  final bool converted;

  /// A share link could not be converted; buyers may see "Video unavailable".
  final bool failed;
}
