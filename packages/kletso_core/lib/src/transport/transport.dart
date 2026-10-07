import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

/// What a transport needs to attach to a conversation.
@immutable
final class KletsoTransportRequest {
  /// Creates a request.
  const KletsoTransportRequest({
    required this.realtimeUrl,
    required this.token,
    this.conversationId,
    this.after = 0,
  });

  /// Realtime endpoint from the session bootstrap.
  final Uri realtimeUrl;

  /// Session token; sent as the first frame (WebSocket) or bearer header
  /// (SSE), never in the URL.
  final String token;

  /// Conversation to attach to, or `null` for a session-only socket.
  final String? conversationId;

  /// Last `seq` the client holds; the server replays everything after it.
  final int after;

  /// Returns a copy with the given fields replaced.
  KletsoTransportRequest copyWith({
    Uri? realtimeUrl,
    String? token,
    String? conversationId,
    int? after,
  }) => KletsoTransportRequest(
    realtimeUrl: realtimeUrl ?? this.realtimeUrl,
    token: token ?? this.token,
    conversationId: conversationId ?? this.conversationId,
    after: after ?? this.after,
  );
}

/// Why a socket ended.
@immutable
final class KletsoCloseInfo {
  /// Creates close info.
  const KletsoCloseInfo(this.code, [this.reason = '']);

  /// WebSocket-style close code (see `KletsoCloseCodes`); `null` when the
  /// connection dropped without a close frame.
  final int? code;

  /// Server-provided reason, if any.
  final String reason;

  /// `true` for a clean local or server close (1000/1001).
  bool get isNormal =>
      code == KletsoCloseCodes.normal || code == KletsoCloseCodes.goingAway;

  @override
  String toString() =>
      'KletsoCloseInfo($code${reason.isEmpty ? '' : ', $reason'})';
}

/// One attached realtime session. Produced by [KletsoTransport.open] only
/// after the server acknowledged authentication, so [readySeq] is always
/// known.
abstract interface class KletsoSocket {
  /// The `seq` the server reported as current when it accepted the client.
  int get readySeq;

  /// Frames from the server, in order. The stream closes when the socket
  /// ends, and it must close **before** [done] completes so consumers can
  /// drain buffered frames (`KletsoConnection` relies on this).
  Stream<KletsoServerFrame> get frames;

  /// Completes when the socket has ended, however that happened.
  Future<KletsoCloseInfo> get done;

  /// Sends one frame. Throws `KletsoNetworkException` when the socket is no
  /// longer usable.
  Future<void> send(KletsoClientFrame frame);

  /// Whether this socket can carry voice audio (binary frames, D79). SSE
  /// cannot; the WebSocket and fake transports can.
  bool get supportsBinary;

  /// Audio frames from the server (assistant speech). Empty when
  /// [supportsBinary] is `false`. Closes with [frames].
  Stream<KletsoAudioFrame> get audio;

  /// Sends microphone audio. Throws `KletsoNetworkException` when the socket
  /// cannot carry binary frames or is closed.
  Future<void> sendAudio(KletsoAudioFrame frame);

  /// Closes the socket; [code] follows WebSocket semantics.
  Future<void> close([int code = KletsoCloseCodes.normal, String reason = '']);
}

/// Opens realtime sockets. Implementations: `KletsoWebSocketTransport`,
/// `KletsoSseTransport`, `KletsoAutoTransport`, and `FakeTransport` in `fake.dart`.
///
/// `open` performs the whole handshake (connect, authenticate, wait for the
/// server's `ready`). It throws `KletsoAuthException` for a rejected or
/// expired token, `KletsoTimeoutException` when the handshake stalls, and
/// `KletsoNetworkException` for everything else.
abstract interface class KletsoTransport {
  /// Connects and authenticates.
  Future<KletsoSocket> open(KletsoTransportRequest request);

  /// Short name for logs (`ws`, `sse`, `fake`).
  String get name;
}
