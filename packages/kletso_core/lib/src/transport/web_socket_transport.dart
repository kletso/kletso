import 'dart:async';
import 'dart:convert';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:web_socket/web_socket.dart';

import '../exceptions.dart';
import 'transport.dart';

/// Opens a [WebSocket] and connects to the socket factory; injectable so
/// tests can supply a fake without a network.
typedef KletsoWebSocketConnector =
    Future<WebSocket> Function(Uri url, {Iterable<String>? protocols});

/// [KletsoTransport] over `package:web_socket` (IO, browser and Cupertino
/// implementations, Wasm-ready). Authenticates with a first `auth` frame and
/// resolves once `ready` arrives.
final class KletsoWebSocketTransport implements KletsoTransport {
  /// Creates a transport. [connect] defaults to [WebSocket.connect].
  KletsoWebSocketTransport({
    Duration handshakeTimeout = const Duration(seconds: 10),
    int maxFrameBytes = 256 * 1024,
    KletsoWebSocketConnector? connect,
  }) : _handshakeTimeout = handshakeTimeout,
       _maxFrameBytes = maxFrameBytes,
       _connect = connect ?? WebSocket.connect;

  final Duration _handshakeTimeout;
  final int _maxFrameBytes;
  final KletsoWebSocketConnector _connect;

  @override
  String get name => 'ws';

  @override
  Future<KletsoSocket> open(KletsoTransportRequest request) async {
    final WebSocket ws;
    try {
      ws = await _connect(
        request.realtimeUrl,
        protocols: const <String>['kletso.v1'],
      ).timeout(_handshakeTimeout);
    } on TimeoutException catch (e) {
      throw KletsoTimeoutException('websocket handshake timed out', cause: e);
    } on WebSocketException catch (e) {
      throw KletsoNetworkException(e.message, cause: e);
    }
    final socket = _WebSocketSocket(ws, _maxFrameBytes);
    try {
      final ready = await socket
          ._handshake(
            KletsoAuthFrame(
              token: request.token,
              conversationId: request.conversationId,
              after: request.after,
            ),
          )
          .timeout(_handshakeTimeout);
      socket._readySeq = ready.seq;
      return socket;
    } on TimeoutException catch (e) {
      await socket.close(KletsoCloseCodes.heartbeatTimeout, 'auth timeout');
      throw KletsoTimeoutException('no ready frame after auth', cause: e);
    }
  }
}

final class _WebSocketSocket implements KletsoSocket {
  _WebSocketSocket(this._ws, this._maxFrameBytes) {
    _sub = _ws.events.listen(
      _onEvent,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final WebSocket _ws;
  final int _maxFrameBytes;
  late final StreamSubscription<WebSocketEvent> _sub;
  final StreamController<KletsoServerFrame> _frames =
      StreamController<KletsoServerFrame>();
  final Completer<KletsoCloseInfo> _done = Completer<KletsoCloseInfo>();
  Completer<KletsoReadyFrame>? _ready;
  int _readySeq = 0;
  bool _closed = false;

  @override
  int get readySeq => _readySeq;

  @override
  Stream<KletsoServerFrame> get frames => _frames.stream;

  @override
  Future<KletsoCloseInfo> get done => _done.future;

  Future<KletsoReadyFrame> _handshake(KletsoAuthFrame auth) {
    final completer = _ready = Completer<KletsoReadyFrame>();
    _ws.sendText(jsonEncode(auth.toJson()));
    return completer.future;
  }

  void _onEvent(WebSocketEvent event) {
    if (_closed) return;
    switch (event) {
      case TextDataReceived(:final text):
        _onText(text);
      case BinaryDataReceived():
        _frames.addError(
          const KletsoProtocolException('binary frames are not supported'),
        );
      case CloseReceived(:final code, :final reason):
        _finish(KletsoCloseInfo(code, reason));
    }
  }

  void _onText(String text) {
    if (text.length > _maxFrameBytes) {
      _frames.addError(
        KletsoProtocolException(
          'frame of ${text.length} chars exceeds $_maxFrameBytes bytes',
        ),
      );
      return;
    }
    final KletsoServerFrame frame;
    try {
      frame = KletsoServerFrame.fromJson(jsonDecode(text));
    } on FormatException catch (e) {
      _frames.addError(KletsoProtocolException('invalid JSON frame', cause: e));
      return;
    } on KletsoSchemaException catch (e) {
      _frames.addError(KletsoProtocolException(e.message, cause: e));
      return;
    }
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      if (frame is KletsoReadyFrame) {
        ready.complete(frame);
        return;
      }
      if (frame is KletsoErrorFrame) {
        ready.completeError(_authError(frame));
        return;
      }
    }
    _frames.add(frame);
  }

  KletsoException _authError(KletsoErrorFrame frame) => switch (frame.code) {
    'unauthorized' => KletsoAuthException(frame.message),
    'token_expired' => KletsoAuthException(frame.message, expired: true),
    _ => KletsoServerException(
      frame.message,
      code: frame.code,
      retryable: frame.retryable,
    ),
  };

  void _onError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(KletsoNetworkException('$error', cause: error));
    }
    _frames.addError(
      KletsoNetworkException('$error', cause: error),
      stackTrace,
    );
  }

  void _onDone() => _finish(const KletsoCloseInfo(null, 'socket closed'));

  void _finish(KletsoCloseInfo info) {
    if (_closed) return;
    _closed = true;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(switch (info.code) {
        KletsoCloseCodes.authFailed => KletsoAuthException(
          info.reason.isEmpty ? 'authentication failed' : info.reason,
        ),
        KletsoCloseCodes.tokenExpired => KletsoAuthException(
          info.reason.isEmpty ? 'token expired' : info.reason,
          expired: true,
        ),
        _ => KletsoNetworkException('closed during auth: $info'),
      });
    }
    unawaited(_frames.close());
    unawaited(_sub.cancel());
    if (!_done.isCompleted) _done.complete(info);
  }

  @override
  Future<void> send(KletsoClientFrame frame) async {
    if (_closed) throw const KletsoNetworkException('socket is closed');
    try {
      _ws.sendText(jsonEncode(frame.toJson()));
    } on WebSocketConnectionClosed catch (e) {
      _finish(const KletsoCloseInfo(null, 'send after close'));
      throw KletsoNetworkException('socket closed', cause: e);
    }
  }

  @override
  Future<void> close([
    int code = KletsoCloseCodes.normal,
    String reason = '',
  ]) async {
    if (_closed) return;
    _finish(KletsoCloseInfo(code, reason));
    // Browsers only let a client close with 1000 or 3000–4999; anything else
    // (e.g. 1001 going away) throws on the web platform.
    final wireCode = code == 1000 || (code >= 3000 && code <= 4999)
        ? code
        : 1000;
    try {
      await _ws.close(wireCode, reason);
    } on WebSocketConnectionClosed {
      // Already gone.
    } on ArgumentError {
      // Platform refused the code; the socket is being torn down anyway.
    }
  }
}
