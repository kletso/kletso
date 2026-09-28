import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import '../config.dart';
import '../exceptions.dart';
import '../log.dart';
import '../transport/transport.dart';
import '../value_listenable.dart';
import 'backoff.dart';
import 'connection_state.dart';

/// Called when the server reports the session token expired (4403). Return
/// the new token, or `null` to give up.
typedef KletsoTokenRefresher = Future<String?> Function();

/// Owns one realtime connection: the reconnect loop with jittered backoff,
/// first-frame auth (delegated to the transport), heartbeat, `seq` replay and
/// dedupe, and a bounded outbound queue that flushes after `ready`.
///
/// It knows nothing about messages or conversations; `KletsoClient` reduces
/// the [events] it emits.
final class KletsoConnection {
  /// Creates a connection over [transport].
  KletsoConnection({
    required KletsoTransport transport,
    required KletsoConfig config,
    required KletsoLog log,
    required Uri realtimeUrl,
    required String token,
    KletsoTokenRefresher? onTokenExpired,
    Random? random,
  }) : _transport = transport,
       _config = config,
       _log = log,
       _realtimeUrl = realtimeUrl,
       _token = token,
       _onTokenExpired = onTokenExpired,
       _backoff = KletsoBackoff(
         base: config.backoffBase,
         cap: config.backoffCap,
         random: random,
       );

  final KletsoTransport _transport;
  final KletsoConfig _config;
  final KletsoLog _log;
  final Uri _realtimeUrl;
  final KletsoBackoff _backoff;
  final KletsoTokenRefresher? _onTokenExpired;

  String _token;
  String? _conversationId;
  int _lastSeq = 0;
  final LinkedHashSet<String> _seenIds = LinkedHashSet<String>();

  final KletsoValueNotifier<KletsoConnectionState> _state =
      KletsoValueNotifier<KletsoConnectionState>(KletsoConnectionState.closed);
  final StreamController<KletsoEventEnvelope> _events =
      StreamController<KletsoEventEnvelope>.broadcast();
  final StreamController<KletsoException> _errors =
      StreamController<KletsoException>.broadcast();
  final StreamController<KletsoReadyFrame> _readies =
      StreamController<KletsoReadyFrame>.broadcast();

  final Queue<KletsoClientFrame> _queue = Queue<KletsoClientFrame>();
  KletsoSocket? _socket;
  StreamSubscription<KletsoServerFrame>? _frameSub;
  Timer? _heartbeat;
  Timer? _pongTimer;
  Future<void>? _loop;
  Completer<void>? _firstOpen;
  bool _wantConnected = false;
  bool _disposed = false;

  /// Current state.
  KletsoValueListenable<KletsoConnectionState> get state => _state;

  /// Deduplicated envelopes in `seq` order.
  Stream<KletsoEventEnvelope> get events => _events.stream;

  /// Errors the loop handled (reconnects, dropped frames, rate limits).
  Stream<KletsoException> get errors => _errors.stream;

  /// `ready` frames, including those after a `switch`.
  Stream<KletsoReadyFrame> get readies => _readies.stream;

  /// Highest `seq` received for the attached conversation.
  int get lastSeq => _lastSeq;

  /// The attached conversation, if any.
  String? get conversationId => _conversationId;

  /// Frames waiting for the next `ready`.
  int get queuedFrames => _queue.length;

  /// Whether [connect] was called and [disconnect] was not.
  bool get wantsConnection => _wantConnected;

  /// Points the connection at [conversationId], resuming after [after].
  /// When open, sends a `switch` frame; otherwise the next handshake attaches.
  void attach(String conversationId, {int after = 0}) {
    if (_conversationId == conversationId) return;
    _conversationId = conversationId;
    _lastSeq = after;
    _seenIds.clear();
    final socket = _socket;
    if (socket != null && _state.value == KletsoConnectionState.open) {
      unawaited(
        _safeSend(
          socket,
          KletsoSwitchFrame(conversationId: conversationId, after: after),
        ),
      );
    }
  }

  /// Replaces the token used for the next handshake (after a refresh).
  void updateToken(String token) => _token = token;

  /// Starts the loop. Completes when the first `ready` arrives; throws the
  /// handshake error when authentication fails permanently.
  Future<void> connect() {
    _checkNotDisposed();
    if (_wantConnected) return _firstOpen?.future ?? Future<void>.value();
    _wantConnected = true;
    final first = _firstOpen = Completer<void>();
    _loop = _run();
    return first.future;
  }

  /// Stops the loop and closes the socket. Queued frames are kept for the
  /// next [connect] unless [clearQueue] is set.
  Future<void> disconnect({bool clearQueue = false}) async {
    _wantConnected = false;
    _sleeper?.call();
    if (clearQueue) _queue.clear();
    final socket = _socket;
    if (socket != null) await socket.close(KletsoCloseCodes.normal, 'client');
    await _loop;
    _setState(KletsoConnectionState.closed, 'disconnect');
  }

  /// Queues [frame]; it is sent immediately when open, otherwise after the
  /// next `ready`. The queue holds at most `outboundQueueLimit` frames; the
  /// oldest is dropped (and reported on [errors]) beyond that.
  void send(KletsoClientFrame frame) {
    _checkNotDisposed();
    final socket = _socket;
    if (socket != null && _state.value == KletsoConnectionState.open) {
      unawaited(_safeSend(socket, frame));
      return;
    }
    _queue.add(frame);
    if (_queue.length > _config.outboundQueueLimit) {
      final dropped = _queue.removeFirst();
      final id = switch (dropped) {
        KletsoMessageFrame(:final clientId) => clientId,
        KletsoActionFrame(:final clientId) => clientId,
        _ => dropped.t,
      };
      _errors.add(
        KletsoQueueOverflowException(
          'outbound queue full; dropped ${dropped.t}',
          droppedClientId: id,
        ),
      );
    }
  }

  /// Releases everything. Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _wantConnected = false;
    _sleeper?.call();
    _stopHeartbeat();
    final socket = _socket;
    if (socket != null) {
      await socket.close(KletsoCloseCodes.goingAway, 'dispose');
    }
    await _loop; // the loop drains and cancels its own frame subscription

    _queue.clear();
    _state.dispose();
    await _events.close();
    await _errors.close();
    await _readies.close();
  }

  // ---- loop -----------------------------------------------------------------

  Future<void> _run() async {
    var attempt = 0;
    while (_wantConnected && !_disposed) {
      _setState(
        attempt == 0
            ? KletsoConnectionState.connecting
            : KletsoConnectionState.reconnecting,
        attempt == 0 ? null : 'attempt $attempt',
      );
      final KletsoSocket socket;
      try {
        socket = await _transport.open(
          KletsoTransportRequest(
            realtimeUrl: _realtimeUrl,
            token: _token,
            conversationId: _conversationId,
            after: _lastSeq,
          ),
        );
      } on KletsoAuthException catch (e) {
        if (e.expired && await _refreshToken()) {
          attempt++;
          continue;
        }
        _fail(e);
        return;
      } on KletsoException catch (e, s) {
        _log.warning('${_transport.name} open failed: $e', e, s);
        _errors.add(e);
        attempt++;
        if (!await _sleep(_backoff.next())) return;
        continue;
      }
      if (!_wantConnected || _disposed) {
        await socket.close(KletsoCloseCodes.normal, 'cancelled');
        return;
      }
      _backoff.reset();
      _socket = socket;
      _onReady(
        KletsoReadyFrame(seq: socket.readySeq, conversationId: _conversationId),
      );
      _setState(KletsoConnectionState.open);
      _firstOpen?.complete();
      _firstOpen = null;
      _startHeartbeat(socket);
      await _flush(socket);
      final drained = Completer<void>();
      _frameSub = socket.frames.listen(
        (f) => _onFrame(socket, f),
        onError: _onFrameError,
        onDone: drained.complete,
        cancelOnError: false,
      );
      final info = await socket.done;
      // Frames buffered before the close are still in flight; apply them
      // before reconnecting or the replay cursor lags and we loop.
      await drained.future;
      _stopHeartbeat();
      unawaited(_frameSub?.cancel() ?? Future<void>.value());
      _frameSub = null;
      _socket = null;
      _log.info('${_transport.name} closed: $info');
      if (!_wantConnected || _disposed) return;
      _setState(KletsoConnectionState.reconnecting, 'closed: $info');
      switch (info.code) {
        case KletsoCloseCodes.authFailed:
          _fail(
            KletsoAuthException(
              info.reason.isEmpty ? 'authentication failed' : info.reason,
            ),
          );
          return;
        case KletsoCloseCodes.tokenExpired:
          if (!await _refreshToken()) return;
          attempt = 1;
          continue;
        default:
          _errors.add(
            KletsoNetworkException('connection lost ($info)', cause: info),
          );
          attempt = max(attempt, 1);
          if (!await _sleep(_backoff.next())) return;
      }
    }
    _setState(KletsoConnectionState.closed);
  }

  Future<bool> _refreshToken() async {
    final refresher = _onTokenExpired;
    if (refresher == null) {
      _fail(const KletsoAuthException('session expired', expired: true));
      return false;
    }
    try {
      final token = await refresher();
      if (token == null) {
        _fail(const KletsoAuthException('session expired', expired: true));
        return false;
      }
      _token = token;
      return true;
    } on Object catch (e, s) {
      _log.error('token refresh failed', e, s);
      _fail(KletsoAuthException('token refresh failed: $e', cause: e));
      return false;
    }
  }

  void _fail(KletsoException e) {
    _wantConnected = false;
    _errors.add(e);
    final first = _firstOpen;
    if (first != null && !first.isCompleted) first.completeError(e);
    _firstOpen = null;
    _setState(KletsoConnectionState.closed, e.message);
  }

  /// Sleeps for [delay] unless cancelled; returns `false` when the loop must
  /// stop.
  Future<bool> _sleep(Duration delay) async {
    _log.debug('backoff ${delay.inMilliseconds} ms');
    final completer = Completer<void>();
    final timer = Timer(delay, completer.complete);
    _sleeper = () {
      timer.cancel();
      if (!completer.isCompleted) completer.complete();
    };
    await completer.future;
    _sleeper = null;
    return _wantConnected && !_disposed;
  }

  void Function()? _sleeper;

  // ---- frames ---------------------------------------------------------------

  void _onFrame(KletsoSocket socket, KletsoServerFrame frame) {
    switch (frame) {
      case KletsoPongFrame():
        _pongTimer?.cancel();
        _pongTimer = null;
      case KletsoReadyFrame():
        _onReady(frame);
      case KletsoEventFrame(:final event):
        _onEvent(event);
      case KletsoErrorFrame(
        :final code,
        :final message,
        :final retryable,
        :final retryAfterMs,
      ):
        _errors.add(switch (code) {
          'rate_limited' => KletsoRateLimitException(
            message,
            retryAfter: retryAfterMs == null
                ? null
                : Duration(milliseconds: retryAfterMs),
          ),
          'unauthorized' => KletsoAuthException(message),
          _ => KletsoServerException(message, code: code, retryable: retryable),
        });
      case KletsoUnknownServerFrame(:final t):
        _log.debug('ignoring unknown frame "$t"');
    }
  }

  void _onReady(KletsoReadyFrame ready) {
    if (ready.conversationId != null &&
        ready.conversationId != _conversationId) {
      // A late ready for a conversation we already left; ignore.
      return;
    }
    if (ready.seq < _lastSeq) {
      // The server has less than we do (new conversation, or it lost state):
      // trust the server and let it replay from its cursor.
      _lastSeq = ready.seq;
      _seenIds.clear();
    }
    _readies.add(ready);
  }

  void _onEvent(KletsoEventEnvelope event) {
    if (_conversationId != null && event.conversationId != _conversationId) {
      _log.debug(
        'dropping event for other conversation ${event.conversationId}',
      );
      return;
    }
    if (event.seq <= _lastSeq || _seenIds.contains(event.id)) {
      _log.debug('duplicate #${event.seq} ${event.id}');
      return;
    }
    _lastSeq = event.seq;
    _seenIds.add(event.id);
    if (_seenIds.length > 1000) _seenIds.remove(_seenIds.first);
    _events.add(event);
  }

  void _onFrameError(Object error, StackTrace stackTrace) {
    final e = error is KletsoException
        ? error
        : KletsoProtocolException('$error', cause: error);
    _log.warning('frame error: $e', error, stackTrace);
    _errors.add(e);
  }

  Future<void> _flush(KletsoSocket socket) async {
    while (_queue.isNotEmpty && _socket == socket) {
      final frame = _queue.removeFirst();
      if (!await _safeSend(socket, frame)) {
        _queue.addFirst(frame);
        return;
      }
    }
  }

  Future<bool> _safeSend(KletsoSocket socket, KletsoClientFrame frame) async {
    try {
      await socket.send(frame);
      return true;
    } on KletsoException catch (e) {
      _log.warning('send failed, requeueing ${frame.t}: $e');
      if (frame is! KletsoPingFrame && frame is! KletsoTypingFrame) {
        _queue.addFirst(frame);
      }
      _errors.add(e);
      return false;
    }
  }

  // ---- heartbeat ------------------------------------------------------------

  void _startHeartbeat(KletsoSocket socket) {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(_config.heartbeatInterval, (_) {
      if (_socket != socket) return;
      unawaited(_safeSend(socket, const KletsoPingFrame()));
      _pongTimer?.cancel();
      _pongTimer = Timer(_config.heartbeatTimeout, () {
        if (_socket != socket) return;
        _log.warning(
          'no pong within ${_config.heartbeatTimeout}; reconnecting',
        );
        unawaited(socket.close(KletsoCloseCodes.heartbeatTimeout, 'no pong'));
      });
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  // ---- misc -----------------------------------------------------------------

  void _setState(KletsoConnectionState next, [String? reason]) {
    if (_disposed) return;
    if (_state.value != next) {
      _log.info(
        'connection ${_state.value.name} → ${next.name}'
        '${reason == null ? '' : ' ($reason)'}',
      );
    }
    _state.value = next;
  }

  void _checkNotDisposed() {
    if (_disposed) throw const KletsoStateException('connection disposed');
  }
}
