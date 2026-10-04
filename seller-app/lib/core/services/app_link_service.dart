import 'dart:async';

import 'package:app_links/app_links.dart';

import 'app_log.dart';

/// Links that open the seller app (SA-AND-003): `livedrop-seller://open/<section>`.
///
/// Used by the website after a password reset ("Open the LiveDrop Seller
/// app") and available for future e-mails. A custom scheme needs no file on
/// the website and keeps working if the website's domain changes.
class AppLinkRoute {
  AppLinkRoute._();

  static const String scheme = 'livedrop-seller';

  static const Map<String, int> _tabs = {
    'home': 0,
    'products': 1,
    'orders': 2,
    'payments': 3,
    'settings': 4,
  };

  /// Tab for a link, or null when the link is not ours or names no section
  /// (the app then simply opens where it was).
  static int? tabFor(Uri uri) {
    if (uri.scheme != scheme || uri.host != 'open') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return _tabs[segments.first.toLowerCase()];
  }
}

/// Delivers links that opened the app, cold start included.
class AppLinkService {
  AppLinkService({AppLinks? links}) : _links = links;

  AppLinks? _links;
  StreamSubscription<Uri>? _subscription;

  /// [onTab] runs for every link that names a section.
  void start(void Function(int tab) onTab) {
    if (_subscription != null) return;
    try {
      final links = _links ??= AppLinks();
      // uriLinkStream also emits the link the app was started with.
      _subscription = links.uriLinkStream.listen((uri) {
        final tab = AppLinkRoute.tabFor(uri);
        if (tab != null) onTab(tab);
      }, onError: (Object e, StackTrace st) => AppLog.error('app_links:stream', e, st));
    } catch (e, st) {
      // No platform implementation (tests, desktop): links simply do nothing.
      AppLog.error('app_links:start', e, st);
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
