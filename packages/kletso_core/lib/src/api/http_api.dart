import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import '../config.dart';
import '../exceptions.dart';
import '../model/conversation.dart';
import '../model/notification.dart';
import '../session.dart';
import 'api.dart';

/// [KletsoApi] over HTTP with `package:http`. Works on every platform
/// (`BrowserClient` on the web).
final class KletsoHttpApi implements KletsoApi {
  /// Creates an API client. Inject [client] in tests (`MockClient`).
  KletsoHttpApi(this.config, {http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _timeout = timeout ?? config.connectTimeout;

  /// SDK configuration (base URL, publishable key).
  final KletsoConfig config;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  bool _closed = false;

  Uri _url(String path, [Map<String, String>? query]) => config.apiRoot.replace(
    path: '${config.apiRoot.path}$path',
    queryParameters: query,
  );

  Map<String, String> _headers(String bearer, {String? userToken}) =>
      <String, String>{
        'Authorization': 'Bearer $bearer',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'X-Kletso-User-Token': ?userToken,
      };

  Future<Object?> _send(
    String method,
    Uri url,
    Map<String, String> headers, {
    Object? body,
  }) async {
    if (_closed) throw const KletsoStateException('api closed');
    final request = http.Request(method, url)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_timeout);
    } on TimeoutException catch (e) {
      throw KletsoTimeoutException('$method $url timed out', cause: e);
    } on http.ClientException catch (e) {
      throw KletsoNetworkException(e.message, cause: e);
    }
    final response = await http.Response.fromStream(streamed);
    final requestId = response.headers['kletso-request-id'];
    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException catch (e) {
        if (response.statusCode < 400) {
          throw KletsoProtocolException(
            'non-JSON response from $url',
            cause: e,
          );
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw _error(response.statusCode, decoded, requestId, response.headers);
  }

  KletsoException _error(
    int status,
    Object? body,
    String? requestId,
    Map<String, String> headers,
  ) {
    var code = 'internal';
    var message = 'HTTP $status';
    if (body is Map && body['error'] is Map) {
      final err = (body['error']! as Map).cast<String, Object?>();
      code = err['code'] as String? ?? code;
      message = err['message'] as String? ?? message;
    }
    switch (status) {
      case 401:
        return KletsoAuthException(message, expired: code == 'token_expired');
      case 403:
        return KletsoAuthException(message);
      case 429:
        final retryAfter = headers['retry-after'];
        final seconds = retryAfter == null ? null : int.tryParse(retryAfter);
        return KletsoRateLimitException(
          message,
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      default:
        return KletsoServerException(
          message,
          code: code,
          requestId: requestId,
          statusCode: status,
          retryable: status >= 500,
        );
    }
  }

  @override
  Future<KletsoSessionBootstrap> createSession({
    required String agentId,
    required KletsoDevice device,
    String? userToken,
    String? visitorId,
    JsonMap context = const <String, Object?>{},
  }) async {
    final body = await _send(
      'POST',
      _url('/sessions'),
      _headers(config.publishableKey, userToken: userToken),
      body: <String, Object?>{
        'agentId': agentId,
        'environment': config.environment.wire,
        'visitorId': ?visitorId,
        'context': context,
        'device': device.toJson(),
      },
    );
    try {
      return KletsoSessionBootstrap.fromJson(body);
    } on KletsoSchemaException catch (e) {
      throw KletsoProtocolException(e.message, cause: e);
    }
  }

  @override
  Future<KletsoSession> refreshSession(
    KletsoSession current, {
    String? userToken,
  }) async {
    final body = await _send(
      'POST',
      _url('/sessions/refresh'),
      _headers(current.token),
      body: <String, Object?>{'userToken': ?userToken},
    );
    if (body is Map && body['session'] is Map) {
      return KletsoSession.fromJson(
        (body['session']! as Map).cast<String, Object?>(),
      );
    }
    throw const KletsoProtocolException('refresh response has no session');
  }

  @override
  Future<void> deleteSession(KletsoSession session) =>
      _send('DELETE', _url('/sessions/current'), _headers(session.token));

  @override
  Future<void> updateContext(
    KletsoSession session,
    JsonMap context, {
    required bool replace,
  }) => _send(
    replace ? 'PUT' : 'PATCH',
    _url('/sessions/current/context'),
    _headers(session.token),
    body: <String, Object?>{'context': context},
  );

  @override
  Future<List<KletsoConversation>> listConversations(
    KletsoSession session,
  ) async {
    final body = await _send(
      'GET',
      _url('/conversations'),
      _headers(session.token),
    );
    final items = body is Map ? body['conversations'] : body;
    if (items is! List) return const <KletsoConversation>[];
    return items
        .whereType<Map<Object?, Object?>>()
        .map((m) => KletsoConversation.fromJson(m.cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<KletsoConversation> createConversation(
    KletsoSession session, {
    String? agentId,
    String? title,
  }) async {
    final body = await _send(
      'POST',
      _url('/conversations'),
      _headers(session.token),
      body: <String, Object?>{'agentId': ?agentId, 'title': ?title},
    );
    if (body is Map && body['conversation'] is Map) {
      return KletsoConversation.fromJson(
        (body['conversation']! as Map).cast<String, Object?>(),
      );
    }
    throw const KletsoProtocolException('create response has no conversation');
  }

  @override
  Future<List<KletsoEventEnvelope>> listEvents(
    KletsoSession session,
    String conversationId, {
    int after = 0,
    int limit = 200,
  }) async {
    final body = await _send(
      'GET',
      _url('/conversations/$conversationId/events', <String, String>{
        'after': '$after',
        'limit': '$limit',
      }),
      _headers(session.token),
    );
    final items = body is Map ? body['events'] : body;
    if (items is! List) return const <KletsoEventEnvelope>[];
    final out = <KletsoEventEnvelope>[];
    for (final item in items) {
      try {
        out.add(KletsoEventEnvelope.fromJson(item));
      } on KletsoSchemaException {
        // Skip malformed entries; the rest of the log is still useful.
        continue;
      }
    }
    return out;
  }

  @override
  Future<void> postMessage(
    KletsoSession session,
    String conversationId,
    KletsoMessageFrame frame,
  ) => _send(
    'POST',
    _url('/conversations/$conversationId/messages'),
    _headers(session.token),
    body: <String, Object?>{
      'text': frame.text,
      'value': frame.value,
      'clientId': frame.clientId,
    },
  );

  @override
  Future<void> postAction(
    KletsoSession session,
    String conversationId,
    KletsoActionFrame frame,
  ) => _send(
    'POST',
    _url('/conversations/$conversationId/actions'),
    _headers(session.token),
    body: <String, Object?>{
      'surfaceId': frame.surfaceId,
      'componentId': frame.componentId,
      'actionId': frame.actionId,
      'value': frame.value,
      'clientId': frame.clientId,
    },
  );

  @override
  Future<void> postTrigger(KletsoSession session, KletsoClientFrame frame) {
    final body = switch (frame) {
      KletsoTrackFrame(:final name, :final properties) => <String, Object?>{
        'name': name,
        'properties': properties,
      },
      KletsoScreenFrame(:final name) => <String, Object?>{
        'name': name,
        'screen': name,
      },
      _ => throw ArgumentError.value(frame, 'frame', 'not a trigger frame'),
    };
    return _send('POST', _url('/events'), _headers(session.token), body: body);
  }

  @override
  Future<void> registerPushToken(
    KletsoSession session,
    KletsoPushToken token,
  ) => _send(
    'PUT',
    _url('/sessions/current/push-token'),
    _headers(session.token),
    body: token.toJson(),
  );

  @override
  Future<void> unregisterPushToken(KletsoSession session) => _send(
    'DELETE',
    _url('/sessions/current/push-token'),
    _headers(session.token),
  );

  @override
  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }
}
