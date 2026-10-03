import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/realtime/seller_live_store.dart';

/// Tells a tab of the home shell whether it is the one on screen. Tabs live in
/// an `IndexedStack`, so hidden tabs stay mounted; they defer live reloads
/// until they become visible again instead of refetching in the background.
class LiveTabVisibility extends InheritedWidget {
  const LiveTabVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  /// True when there is no shell around the widget (stand-alone screen).
  static bool isVisible(BuildContext context, {bool listen = false}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<LiveTabVisibility>()
        : context.getInheritedWidgetOfExactType<LiveTabVisibility>();
    return scope?.visible ?? true;
  }

  @override
  bool updateShouldNotify(LiveTabVisibility oldWidget) => oldWidget.visible != visible;
}

/// Reloads a screen when the [SellerLiveStore] revision changes (SA-RT-001).
///
/// The screen provides [liveStore] and [onLiveRevision]; the mixin attaches
/// and detaches the listener and postpones reloads of hidden tabs until the
/// tab is shown.
mixin SellerLiveRefreshMixin<T extends StatefulWidget> on State<T> {
  /// The store to follow (usually `widget.liveStore`). May be null.
  SellerLiveStore? get liveStore;

  /// Reload the screen's data after a live change, keeping the current
  /// content visible while it loads.
  void onLiveRevision();

  /// Called for every store notification (e.g. updated badge counts).
  void onLiveStoreNotified() {}

  SellerLiveStore? _attachedLiveStore;
  int _seenLiveRevision = 0;
  bool _liveReloadPending = false;

  @override
  void initState() {
    super.initState();
    _attachLiveStore();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attachLiveStore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = LiveTabVisibility.isVisible(context, listen: true);
    if (visible && _liveReloadPending) {
      _liveReloadPending = false;
      scheduleMicrotask(() {
        if (mounted) onLiveRevision();
      });
    }
  }

  @override
  void dispose() {
    _attachedLiveStore?.removeListener(_handleLiveStoreChanged);
    _attachedLiveStore = null;
    super.dispose();
  }

  void _attachLiveStore() {
    final store = liveStore;
    if (identical(store, _attachedLiveStore)) return;
    _attachedLiveStore?.removeListener(_handleLiveStoreChanged);
    _attachedLiveStore = store;
    if (store != null) {
      _seenLiveRevision = store.revision;
      store.addListener(_handleLiveStoreChanged);
    }
  }

  void _handleLiveStoreChanged() {
    final store = _attachedLiveStore;
    if (!mounted || store == null) return;
    onLiveStoreNotified();
    if (store.revision == _seenLiveRevision) return;
    _seenLiveRevision = store.revision;
    if (LiveTabVisibility.isVisible(context)) {
      onLiveRevision();
    } else {
      _liveReloadPending = true;
    }
  }
}
