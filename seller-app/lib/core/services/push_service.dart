import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_log.dart';

/// Where a tapped notification takes the seller (SA-NOT-001).
class PushRoute {
  PushRoute._();

  static const int ordersTab = 2;
  static const int paymentsTab = 3;

  /// Tab for a notification's data payload (see migration 041 triggers).
  static int? tabFor(Map<String, dynamic> data) {
    switch (data['type'] ?? data['kind']) {
      case 'payment_claim':
      case 'late_claim':
        return paymentsTab;
      case 'new_order':
        return ordersTab;
      default:
        return null;
    }
  }
}

/// Registers this phone for push notifications and routes taps (SA-NOT-001).
///
/// Works only when Firebase is configured ([AppLog.crashlyticsReady]); without
/// it every method is a no-op, so tests and builds without
/// `google-services.json` are unaffected.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// Android channel used by the server messages (push-dispatch Edge Function).
  static const String channelId = 'livedrop_seller_alerts';

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> Function(String token)? _unregister;
  String? _token;
  bool _started = false;

  /// Starts after an approved seller signed in.
  ///
  /// [register] / [unregister] store the token with the seller's account,
  /// [onOpen] is called with a message's data when the seller taps it, and
  /// [onForeground] when a message arrives while the app is open.
  Future<void> start({
    required Future<void> Function(String token) register,
    required Future<void> Function(String token) unregister,
    required void Function(Map<String, dynamic> data) onOpen,
    void Function()? onForeground,
  }) async {
    if (_started || !AppLog.crashlyticsReady) return;
    _started = true;
    _unregister = unregister;
    try {
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          onOpen((jsonDecode(payload) as Map).cast<String, dynamic>());
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            channelId,
            'Orders and payments',
            description: 'New orders and buyer payments to check',
            importance: Importance.high,
          ));

      final messaging = FirebaseMessaging.instance;
      // Android 13+ shows the system permission prompt here.
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) {
        _token = token;
        await register(token);
      }
      _subscriptions.add(messaging.onTokenRefresh.listen((fresh) async {
        _token = fresh;
        try {
          await register(fresh);
        } catch (e, st) {
          AppLog.error('push:onTokenRefresh', e, st);
        }
      }));

      // App open: Android does not show the notification itself, so show it.
      _subscriptions.add(FirebaseMessaging.onMessage.listen((message) {
        onForeground?.call();
        final n = message.notification;
        if (n == null) return;
        unawaited(_local.show(
          id: message.hashCode,
          title: n.title,
          body: n.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(channelId, 'Orders and payments',
                importance: Importance.high, priority: Priority.high),
          ),
          payload: jsonEncode(message.data),
        ));
      }));

      // Tapped while the app was in the background or closed.
      _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen(m.data)));
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpen(initial.data);
    } catch (e, st) {
      AppLog.error('push:start', e, st);
    }
  }

  /// Before signing out: this phone stops receiving the seller's alerts.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    final token = _token;
    final unregister = _unregister;
    _token = null;
    _unregister = null;
    try {
      if (token != null && unregister != null) await unregister(token);
      await FirebaseMessaging.instance.deleteToken();
    } catch (e, st) {
      AppLog.error('push:stop', e, st);
    }
  }

  @visibleForTesting
  bool get isStarted => _started;
}
