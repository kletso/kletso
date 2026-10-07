import 'dart:async';
import 'dart:math';

import 'package:kletso_core/kletso_core.dart';

/// A transport the test drives by hand: each `open` hands out the next
/// scripted outcome (a socket or an error) and exposes the socket so the test
/// can push frames and close it.
final class ScriptedTransport implements KletsoTransport {
  final List<Object> _outcomes = <Object>[];

  /// Every socket handed out, oldest first.
  final List<ScriptedSocket> sockets = <ScriptedSocket>[];

  /// Every request seen by `open`.
  final List<KletsoTransportRequest> requests = <KletsoTransportRequest>[];

  /// Next `open` succeeds with a socket reporting [readySeq].
  void willOpen({int readySeq = 0}) => _outcomes.add(readySeq);

  /// Next `open` throws [e].
  void willFail(KletsoException e) => _outcomes.add(e);

  /// The most recent socket.
  ScriptedSocket get current => sockets.last;

  @override
  String get name => 'scripted';

  @override
  Future<KletsoSocket> open(KletsoTransportRequest request) async {
    requests.add(request);
    await Future<void>.value();
    if (_outcomes.isEmpty) {
      throw const KletsoNetworkException('no scripted outcome');
    }
    final next = _outcomes.removeAt(0);
    if (next is KletsoException) throw next;
    final socket = ScriptedSocket(next as int);
    sockets.add(socket);
    return socket;
  }
}

/// Socket controlled by the test.
final class ScriptedSocket implements KletsoSocket {
  ScriptedSocket(this.readySeq);

  @override
  final int readySeq;
  final StreamController<KletsoServerFrame> _frames =
      StreamController<KletsoServerFrame>();
  final Completer<KletsoCloseInfo> _done = Completer<KletsoCloseInfo>();

  /// Frames the connection sent.
  final List<KletsoClientFrame> sent = <KletsoClientFrame>[];

  /// Whether the socket ended.
  bool closed = false;

  /// Close code, once closed.
  int? closeCode;

  /// When set, `send` throws as if the socket were broken.
  bool failSends = false;

  @override
  Stream<KletsoServerFrame> get frames => _frames.stream;

  @override
  Future<KletsoCloseInfo> get done => _done.future;

  /// Audio frames the connection sent (voice).
  final List<KletsoAudioFrame> sentAudio = <KletsoAudioFrame>[];
  final StreamController<KletsoAudioFrame> _audio =
      StreamController<KletsoAudioFrame>();

  @override
  bool get supportsBinary => true;

  @override
  Stream<KletsoAudioFrame> get audio => _audio.stream;

  @override
  Future<void> sendAudio(KletsoAudioFrame frame) async {
    if (closed) throw const KletsoNetworkException('socket closed');
    sentAudio.add(frame);
  }

  /// Delivers an assistant audio frame.
  void pushAudio(KletsoAudioFrame frame) => _audio.add(frame);

  /// Delivers a server frame.
  void push(KletsoServerFrame frame) => _frames.add(frame);

  /// Delivers a stream error.
  void pushError(Object error) => _frames.addError(error);

  /// Delivers an event envelope with [seq].
  void pushEvent(
    int seq, {
    String? id,
    String type = 'agent.typing',
    String conversationId = 'conv_1',
  }) => push(
    KletsoEventFrame(
      KletsoEventEnvelope(
        id: id ?? 'evt_$seq',
        seq: seq,
        type: type,
        ts: DateTime.utc(2026, 9, 28),
        conversationId: conversationId,
      ),
    ),
  );

  /// Ends the socket as the server would.
  void serverClose(int? code, [String reason = '']) {
    if (closed) return;
    closed = true;
    closeCode = code;
    unawaited(_frames.close());
    _done.complete(KletsoCloseInfo(code, reason));
  }

  @override
  Future<void> send(KletsoClientFrame frame) async {
    if (closed || failSends) throw const KletsoNetworkException('closed');
    sent.add(frame);
  }

  @override
  Future<void> close([
    int code = KletsoCloseCodes.normal,
    String reason = '',
  ]) async => serverClose(code, reason);
}

/// `nextInt` always returns the maximum, so backoff delays equal their
/// ceilings and timing assertions are exact.
final class MaxRandom implements Random {
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 1;
  @override
  int nextInt(int max) => max - 1;
}

/// `nextInt` always returns 0, so backoff never waits.
final class ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

/// Test config with short, exact timings.
KletsoConfig testConfig({
  Duration heartbeatInterval = const Duration(seconds: 25),
  int outboundQueueLimit = 3,
  KletsoTransportMode transport = KletsoTransportMode.webSocket,
}) => KletsoConfig(
  publishableKey: 'kl_pub_test',
  agentId: 'agt_1',
  logLevel: KletsoLogLevel.none,
  backoffBase: const Duration(milliseconds: 500),
  backoffCap: const Duration(seconds: 30),
  heartbeatInterval: heartbeatInterval,
  heartbeatTimeout: const Duration(seconds: 10),
  outboundQueueLimit: outboundQueueLimit,
  transport: transport,
);
