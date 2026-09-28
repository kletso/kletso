import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import '../model/conversation.dart';
import '../model/notification.dart';
import '../session.dart';

/// The REST side of the runtime (`/v1`). Implemented by `KletsoHttpApi`
/// against the network and by the fake backend for tests and demos.
abstract interface class KletsoApi {
  /// `POST /v1/sessions`.
  Future<KletsoSessionBootstrap> createSession({
    required String agentId,
    required KletsoDevice device,
    String? userToken,
    String? visitorId,
    JsonMap context = const <String, Object?>{},
  });

  /// `POST /v1/sessions/refresh`; [userToken] re-verifies a renewed host JWT.
  Future<KletsoSession> refreshSession(
    KletsoSession current, {
    String? userToken,
  });

  /// `DELETE /v1/sessions/current`.
  Future<void> deleteSession(KletsoSession session);

  /// `PUT`/`PATCH /v1/sessions/current/context`.
  Future<void> updateContext(
    KletsoSession session,
    JsonMap context, {
    required bool replace,
  });

  /// `GET /v1/conversations`.
  Future<List<KletsoConversation>> listConversations(KletsoSession session);

  /// `POST /v1/conversations`.
  Future<KletsoConversation> createConversation(
    KletsoSession session, {
    String? agentId,
    String? title,
  });

  /// `GET /v1/conversations/:id/events?after=`.
  Future<List<KletsoEventEnvelope>> listEvents(
    KletsoSession session,
    String conversationId, {
    int after = 0,
    int limit = 200,
  });

  /// `POST /v1/conversations/:id/messages` (used by the SSE transport).
  Future<void> postMessage(
    KletsoSession session,
    String conversationId,
    KletsoMessageFrame frame,
  );

  /// `POST /v1/conversations/:id/actions` (used by the SSE transport).
  Future<void> postAction(
    KletsoSession session,
    String conversationId,
    KletsoActionFrame frame,
  );

  /// `POST /v1/events` (track/screen triggers over HTTP).
  Future<void> postTrigger(KletsoSession session, KletsoClientFrame frame);

  /// `PUT /v1/sessions/current/push-token`: lets the runtime reach this
  /// device with `app.notify` events while the app is in the background.
  Future<void> registerPushToken(KletsoSession session, KletsoPushToken token);

  /// `DELETE /v1/sessions/current/push-token`.
  Future<void> unregisterPushToken(KletsoSession session);

  /// Releases sockets. The instance is unusable afterwards.
  void close();
}
