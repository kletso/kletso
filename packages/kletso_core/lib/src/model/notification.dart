import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

/// Where a notification came from.
enum KletsoNotificationSource {
  /// The realtime connection (app in the foreground).
  live,

  /// A push message the host handed to `KletsoClient.handlePushPayload`.
  push,
}

/// An `app.notify` event as seen by the host: the payload plus where it
/// belongs and how it arrived. Deduped on `notificationId`.
@immutable
final class KletsoNotification {
  /// Creates a notification.
  const KletsoNotification({
    required this.payload,
    required this.conversationId,
    required this.eventId,
    required this.receivedAt,
    required this.source,
  });

  /// The typed payload.
  final KletsoAppNotification payload;

  /// The conversation to open for it (`openChat`).
  final String conversationId;

  /// The envelope id.
  final String eventId;

  /// When the device saw it.
  final DateTime receivedAt;

  /// Live socket or push.
  final KletsoNotificationSource source;

  /// Shortcut.
  String get id => payload.notificationId;

  /// Shortcut.
  String get title => payload.title;

  /// Shortcut.
  KletsoNotificationChannel get channel => payload.channel;
}

/// Push providers the runtime can deliver through.
enum KletsoPushPlatform {
  /// Firebase Cloud Messaging (Android, also web/iOS via Firebase).
  fcm('fcm'),

  /// Apple Push Notification service.
  apns('apns'),

  /// Web Push (VAPID subscription JSON as the token).
  webPush('web_push');

  const KletsoPushPlatform(this.wire);

  /// The wire string.
  final String wire;
}

/// A device push token registered for the current end user. The host
/// obtains it from its own push plugin (e.g. `firebase_messaging`) and hands
/// it to `KletsoClient.registerPushToken`; the SDK never bundles a push
/// plugin.
@immutable
final class KletsoPushToken {
  /// Creates a token record.
  const KletsoPushToken({required this.platform, required this.token});

  /// Provider.
  final KletsoPushPlatform platform;

  /// Provider token (or Web Push subscription JSON).
  final String token;

  /// Wire form.
  JsonMap toJson() => <String, Object?>{
    'platform': platform.wire,
    'token': token,
  };

  @override
  bool operator ==(Object other) =>
      other is KletsoPushToken &&
      other.platform == platform &&
      other.token == token;

  @override
  int get hashCode => Object.hash(platform, token);
}
