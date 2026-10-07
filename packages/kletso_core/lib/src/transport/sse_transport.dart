import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import '../api/api.dart';
import '../exceptions.dart';
import '../session.dart';
import 'sse_parser.dart';
import 'transport.dart';

/// [KletsoTransport] for environments that block WebSockets: downstream is a
/// `text/event-stream` `GET /v1/conversations/:id/events?stream=1&after=N`
/// with the token in the `Authorization` header; upstream frames become REST
/// calls through [KletsoApi]. `ping` is a no-op (the server sends `: ping`
/// comments to keep the stream alive), `switch` reopens the stream.
final class KletsoSseTransport implements KletsoTransport {
  /// Creates a transport. [client] is used for the stream; [api] for
  /// upstream frames. [apiRoot] is the `/v1` root, e.g. from
  /// `KletsoConfig.apiRoot`.
  KletsoSseTransport({
    required KletsoApi api,
    required Uri apiRoot,
    http.Client? client,
    Duration handshakeTimeout = const Duration(seconds: 10),
    int maxFrameBytes = 256 * 1024,
  }) : _api = api,
       _apiRoot = apiRoot,
       _client = client ?? http.Client(),
       _handshakeTimeout = handshakeTimeout,
       _maxFrameBytes = maxFrameBytes;

  final KletsoApi _api;
  final Uri _apiRoot;
  final http.Client _client;
  final Duration _handshakeTimeout;
  final int _maxFrameBytes;

  @override
  String get name => 'sse';

  @override
  Future<KletsoSocket> open(KletsoTransportRequest request) async {
    final conversationId = request.conversationId;
    if (conversationId == null) {
      throw const KletsoProtocolException(
        'SSE transport needs a conversation to attach to',
      );
    }
    final url = _apiRoot.replace(
      path: '${_apiRoot.path}/conversations/$conversationId/events',
      queryParameters: <String, String>{
        'after': '${request.after}',
        'stream': '1',
      },
    );
    final req = http.Request('GET', url)
      ..headers['Authorization'] = 'Bearer ${request.token}'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';
    final http.StreamedResponse response;
    try {
      response = await _client.send(req).timeout(_handshakeTimeout);
    } on TimeoutException catch (e) {
      throw KletsoTimeoutException('SSE connect timed out', cause: e);
    } on http.ClientException catch (e) {
      throw KletsoNetworkException(e.message, cause: e);
    }
    if (response.statusCode == 401) {
      throw const KletsoAuthException('session rejected');
    }
    if (response.statusCode == 403) {
      throw const KletsoAuthException('session expired', expired: true);
    }
    if (response.statusCode >= 400) {
      throw KletsoServerException(
        'SSE stream returned ${response.statusCode}',
        code: response.statusCode == 429 ? 'rate_limited' : 'internal',
        statusCode: response.statusCode,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }
    final socket = _SseSocket(
      response,
      request,
      conversationId,
      _api,
      _maxFrameBytes,
    );
    try {
      await socket._ready.future.timeout(_handshakeTimeout);
    } on TimeoutException catch (e) {
      await socket.close();
      throw KletsoTimeoutException('no ready event on SSE stream', cause: e);
    }
    return socket;
  }
}

final class _SseSocket implements KletsoSocket {
  _SseSocket(
    this._response,
    this._request,
    this._conversationId,
    this._api,
    this._maxFrameBytes,
  ) : _session = KletsoSession(
        id: '',
        token: _request.token,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ) {
    _sub = _parser
        .bind(_response.stream)
        .listen(
          _onEvent,
          onError: _onError,
          onDone: () => _finish(const KletsoCloseInfo(null, 'stream ended')),
          cancelOnError: false,
        );
  }

  final http.StreamedResponse _response;
  final KletsoTransportRequest _request;
  final String _conversationId;
  final KletsoApi _api;
  final int _maxFrameBytes;
  final KletsoSession _session;
  final KletsoSseParser _parser = KletsoSseParser();
  late final StreamSubscription<KletsoSseEvent> _sub;
  final StreamController<KletsoServerFrame> _frames =
      StreamController<KletsoServerFrame>();
  final Completer<KletsoCloseInfo> _done = Completer<KletsoCloseInfo>();
  final Completer<void> _ready = Completer<void>();
  int _readySeq = 0;
  bool _closed = false;

  @override
  int get readySeq => _readySeq;

  @override
  Stream<KletsoServerFrame> get frames => _frames.stream;

  @override
  Future<KletsoCloseInfo> get done => _done.future;

  void _onEvent(KletsoSseEvent sse) {
    if (_closed) return;
    if (sse.data.length > _maxFrameBytes) {
      _frames.addError(
        KletsoProtocolException('SSE event exceeds $_maxFrameBytes bytes'),
      );
      return;
    }
    final Object? json;
    try {
      json = jsonDecode(sse.data);
    } on FormatException catch (e) {
      _frames.addError(KletsoProtocolException('invalid SSE JSON', cause: e));
      return;
    }
    // The server wraps frames as `event: <t>` + `data: <frame json>`, or sends
    // bare envelopes with `event: event`. Accept both.
    final KletsoServerFrame frame;
    try {
      if (json is Map && json.containsKey('t')) {
        frame = KletsoServerFrame.fromJson(json);
      } else if (sse.event == 'ready' && json is Map) {
        frame = KletsoReadyFrame(
          seq: (json['seq'] as num?)?.toInt() ?? 0,
          conversationId: json['conversationId'] as String?,
        );
      } else if (sse.event == 'error' && json is Map) {
        frame = KletsoErrorFrame(
          code: json['code'] as String? ?? 'internal',
          message: json['message'] as String? ?? '',
          retryable: json['retryable'] as bool? ?? false,
        );
      } else {
        frame = KletsoEventFrame(KletsoEventEnvelope.fromJson(json));
      }
    } on KletsoSchemaException catch (e) {
      _frames.addError(KletsoProtocolException(e.message, cause: e));
      return;
    }
    if (!_ready.isCompleted) {
      if (frame is KletsoReadyFrame) {
        _readySeq = frame.seq;
        _ready.complete();
        return;
      }
      // Servers that never send `ready` implicitly accept with the first
      // event; treat the request cursor as the ready seq.
      _readySeq = _request.after;
      _ready.complete();
    }
    _frames.add(frame);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    if (!_ready.isCompleted) {
      _ready.completeError(KletsoNetworkException('$error', cause: error));
    }
    _frames.addError(
      KletsoNetworkException('$error', cause: error),
      stackTrace,
    );
  }

  void _finish(KletsoCloseInfo info) {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) {
      _ready.completeError(KletsoNetworkException('stream closed: $info'));
    }
    unawaited(_sub.cancel());
    unawaited(_frames.close());
    if (!_done.isCompleted) _done.complete(info);
  }

  @override
  bool get supportsBinary => false;

  @override
  Stream<KletsoAudioFrame> get audio => const Stream<KletsoAudioFrame>.empty();

  @override
  Future<void> sendAudio(KletsoAudioFrame frame) async {
    throw const KletsoNetworkException('voice needs the WebSocket transport');
  }

  @override
  Future<void> send(KletsoClientFrame frame) async {
    if (_closed) throw const KletsoNetworkException('stream is closed');
    switch (frame) {
      case KletsoMessageFrame():
        await _api.postMessage(_session, _conversationId, frame);
      case KletsoActionFrame():
        await _api.postAction(_session, _conversationId, frame);
      case KletsoContextFrame(:final merge, :final replace):
        await _api.updateContext(
          _session,
          merge ?? replace ?? const <String, Object?>{},
          replace: replace != null,
        );
      case KletsoTrackFrame() || KletsoScreenFrame():
        await _api.postTrigger(_session, frame);
      case KletsoSwitchFrame():
        // The connection reopens the transport for a new conversation.
        _finish(const KletsoCloseInfo(KletsoCloseCodes.normal, 'switch'));
      case KletsoAuthFrame() || KletsoTypingFrame() || KletsoPingFrame():
        // Auth is the header; typing/ping have no REST equivalent.
        break;
      case KletsoVoiceStartFrame() ||
          KletsoVoiceStopFrame() ||
          KletsoVoiceCommitFrame() ||
          KletsoVoicePlayedFrame() ||
          KletsoVoiceTextFrame():
        // Voice needs a bidirectional socket (D79); surface it as an error
        // frame so the voice controller ends the session cleanly.
        _frames.add(
          const KletsoErrorFrame(
            code: 'voice_unavailable',
            message: 'voice needs the WebSocket transport',
          ),
        );
    }
  }

  @override
  Future<void> close([
    int code = KletsoCloseCodes.normal,
    String reason = '',
  ]) async {
    _finish(KletsoCloseInfo(code, reason));
  }
}
