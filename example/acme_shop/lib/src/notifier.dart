import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

/// Acme's OS-tray notifier: the host-side half of Kletso `system`
/// notifications. The SDK never bundles a push/notification plugin; the app
/// wires whatever it already uses (here `flutter_local_notifications`, which
/// covers Android and the browser `Notification` API) and hands taps back to
/// `Kletso.instance.ui.openNotification`.
final class AcmeNotifier {
  AcmeNotifier._();

  static final AcmeNotifier instance = AcmeNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, KletsoNotification> _recent =
      <String, KletsoNotification>{};
  bool _ready = false;
  bool? _permitted;

  /// Whether the OS granted notification permission (null = not asked yet).
  bool? get permitted => _permitted;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        web: WebInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );
  }

  Future<bool> requestPermission() async {
    await init();
    if (kIsWeb) {
      final web = _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >();
      _permitted = await web?.requestNotificationsPermission() ?? false;
    } else {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      _permitted = await android?.requestNotificationsPermission() ?? true;
    }
    return _permitted ?? false;
  }

  /// [KletsoSystemNotifier]: returns false so the SDK shows a banner instead
  /// when the tray is unavailable or denied.
  Future<bool> show(KletsoNotification n) async {
    try {
      await init();
      if (_permitted != true && !(await requestPermission())) return false;
      _recent[n.id] = n;
      if (_recent.length > 20) _recent.remove(_recent.keys.first);
      await _plugin.show(
        id: n.id.hashCode & 0x7fffffff,
        title: n.title,
        body: n.payload.body,
        payload: jsonEncode(<String, Object?>{'kletsoNotificationId': n.id}),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'kletso',
            'Kletso assistant',
            channelDescription: 'Proactive messages from the Acme assistant',
            importance: Importance.high,
            priority: Priority.high,
          ),
          web: WebNotificationDetails(requireInteraction: true),
        ),
      );
      return true;
    } on Object catch (e) {
      debugPrint('AcmeNotifier: tray unavailable ($e); falling back');
      return false;
    }
  }

  void _onTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null) return;
    final id = (jsonDecode(raw) as Map)['kletsoNotificationId'] as String?;
    final n = id == null ? null : _recent[id];
    if (n != null) Kletso.instance.ui.openNotification(n).ignore();
  }
}
