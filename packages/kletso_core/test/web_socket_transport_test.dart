import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';
import 'package:web_socket/web_socket.dart';

final class FakeWebSocket implements WebSocket {
  final StreamController<WebSocketEvent> _events =
      StreamController<WebSocketEvent>();
  final List<String> sent = <String>[];
  int? closeCode;
  String? closeReason;
  bool closed = false;

  @override
  Stream<WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => 'kletso.v1';

  void serverText(Object json) =>
      _events.add(TextDataReceived(jsonEncode(json)));
  void serverRaw(String text) => _events.add(TextDataReceived(text));
  void serverClose(int? code, String reason) {
    _events.add(CloseReceived(code, reason));
    unawaited(_events.close());
  }

  @override
  void sendText(String s) {
    if (closed) throw WebSocketConnectionClosed();
    sent.add(s);
  }

  @override
  void sendBytes(Uint8List b) => throw UnimplementedError();

  @override
  Future<void> close([int? code, String? reason]) async {
    if (closed) throw WebSocketConnectionClosed();
    closed = true;
    closeCode = code;
    closeReason = reason;
    unawaited(_events.close());
  }
}

void main() {
  final url = Uri.parse('wss://api.test/v1/realtime');
  final req = KletsoTransportRequest(
    realtimeUrl: url,
    token: 'kst_1',
    conversationId: 'conv_1',
    after: 4,
  );

  (KletsoWebSocketTransport, FakeWebSocket) transport({
    Duration timeout = const Duration(seconds: 5),
    List<String>? protocols,
  }) {
    final ws = FakeWebSocket();
    final t = KletsoWebSocketTransport(
      handshakeTimeout: timeout,
      connect: (uri, {Iterable<String>? protocols}) async {
        expect(uri, url);
        expect(protocols, ['kletso.v1']);
        return ws;
      },
    );
    return (t, ws);
  }

  test('sends auth as the first frame and resolves on ready', () async {
    final (t, ws) = transport();
    expect(t.name, 'ws');
    final opening = t.open(req);
    await Future<void>.delayed(Duration.zero);
    expect(jsonDecode(ws.sent.single), {
      't': 'auth',
      'token': 'kst_1',
      'conversationId': 'conv_1',
      'after': 4,
    });
    ws.serverText({'t': 'ready', 'seq': 9});
    final socket = await opening;
    expect(socket.readySeq, 9);
    final frames = <KletsoServerFrame>[];
    final errors = <Object>[];
    socket.frames.listen(frames.add, onError: errors.add);
    ws.serverText({'t': 'pong'});
    ws.serverText({
      't': 'event',
      'event': (KletsoFixtures.eventsConversation20! as List)[1],
    });
    ws.serverRaw('{not json');
    ws.serverText({
      't': 'event',
      'event': {'nope': 1},
    });
    ws.serverText({'t': 'mystery'});
    ws.serverRaw('x' * (256 * 1024 + 1));
    ws._events.add(BinaryDataReceived(Uint8List(3)));
    await Future<void>.delayed(Duration.zero);
    expect(frames.map((f) => f.t), ['pong', 'event', 'mystery']);
    expect(errors, hasLength(4));
    expect(errors.every((e) => e is KletsoProtocolException), isTrue);
    await socket.send(const KletsoPingFrame());
    expect(jsonDecode(ws.sent.last), {'t': 'ping'});
    ws.serverClose(1001, 'deploy');
    final info = await socket.done;
    expect(info.code, 1001);
    expect(info.reason, 'deploy');
    expect(info.isNormal, isTrue);
    await expectLater(
      socket.send(const KletsoPingFrame()),
      throwsA(isA<KletsoNetworkException>()),
    );
    await socket.close(); // idempotent
  });

  test('error frame before ready → typed auth/server error', () async {
    for (final (code, matcher) in <(String, Matcher)>[
      (
        'unauthorized',
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', false),
      ),
      (
        'token_expired',
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', true),
      ),
      ('rate_limited', isA<KletsoServerException>()),
    ]) {
      final (t, ws) = transport();
      final opening = t.open(req);
      await Future<void>.delayed(Duration.zero);
      ws.serverText({'t': 'error', 'code': code, 'message': 'm'});
      await expectLater(opening, throwsA(matcher));
    }
  });

  test('close during handshake maps 4401/4403/other', () async {
    for (final (code, matcher) in <(int, Matcher)>[
      (
        4401,
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', false),
      ),
      (
        4403,
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', true),
      ),
      (1006, isA<KletsoNetworkException>()),
    ]) {
      final (t, ws) = transport();
      final opening = t.open(req);
      await Future<void>.delayed(Duration.zero);
      ws.serverClose(code, '');
      await expectLater(opening, throwsA(matcher));
    }
  });

  test('handshake timeout closes the socket with 4000', () async {
    final (t, ws) = transport(timeout: const Duration(milliseconds: 30));
    await expectLater(t.open(req), throwsA(isA<KletsoTimeoutException>()));
    expect(ws.closed, isTrue);
    expect(ws.closeCode, KletsoCloseCodes.heartbeatTimeout);
  });

  test('connect failures are typed', () async {
    final failing = KletsoWebSocketTransport(
      connect: (uri, {Iterable<String>? protocols}) async =>
          throw WebSocketException('refused'),
    );
    await expectLater(
      failing.open(req),
      throwsA(isA<KletsoNetworkException>()),
    );
    final slow = KletsoWebSocketTransport(
      handshakeTimeout: const Duration(milliseconds: 20),
      connect: (uri, {Iterable<String>? protocols}) =>
          Future<WebSocket>.delayed(
            const Duration(seconds: 1),
            FakeWebSocket.new,
          ),
    );
    await expectLater(slow.open(req), throwsA(isA<KletsoTimeoutException>()));
  });

  test('client close sends the code and completes done', () async {
    final (t, ws) = transport();
    final opening = t.open(req);
    await Future<void>.delayed(Duration.zero);
    ws.serverText({'t': 'ready', 'seq': 0});
    final socket = await opening;
    await socket.close(KletsoCloseCodes.goingAway, 'bye');
    // browsers refuse client close codes outside 1000/3000–4999: 1001 goes
    // out as 1000, while the local close info keeps the requested code
    expect(ws.closeCode, 1000);
    expect((await socket.done).code, 1001);
  });

  test('stream error before ready fails the handshake', () async {
    final (t, ws) = transport();
    final opening = t.open(req);
    await Future<void>.delayed(Duration.zero);
    ws._events.addError(StateError('boom'));
    await expectLater(opening, throwsA(isA<KletsoNetworkException>()));
  });

  test(
    'KletsoAutoTransport falls back after two non-auth failures, never on auth',
    () async {
      var primaryCalls = 0;
      var fallbackCalls = 0;
      final primary = _Fn('ws', () async {
        primaryCalls++;
        throw const KletsoNetworkException('blocked');
      });
      final fallback = _Fn('sse', () async {
        fallbackCalls++;
        return _NoopSocket();
      });
      final auto = KletsoAutoTransport(primary: primary, fallback: fallback);
      expect(auto.name, 'ws');
      await expectLater(auto.open(req), throwsA(isA<KletsoNetworkException>()));
      expect(auto.usingFallback, isFalse);
      await expectLater(auto.open(req), throwsA(isA<KletsoNetworkException>()));
      expect(auto.usingFallback, isTrue);
      expect(auto.name, 'sse');
      await auto.open(req);
      expect((primaryCalls, fallbackCalls), (2, 1));

      final authFailing = KletsoAutoTransport(
        primary: _Fn('ws', () async => throw const KletsoAuthException('bad')),
        fallback: fallback,
      );
      await expectLater(
        authFailing.open(req),
        throwsA(isA<KletsoAuthException>()),
      );
      await expectLater(
        authFailing.open(req),
        throwsA(isA<KletsoAuthException>()),
      );
      expect(authFailing.usingFallback, isFalse);
    },
  );
}

final class _Fn implements KletsoTransport {
  _Fn(this.name, this._open);
  @override
  final String name;
  final Future<KletsoSocket> Function() _open;
  @override
  Future<KletsoSocket> open(KletsoTransportRequest request) => _open();
}

final class _NoopSocket implements KletsoSocket {
  @override
  int get readySeq => 0;
  @override
  Stream<KletsoServerFrame> get frames =>
      const Stream<KletsoServerFrame>.empty();
  @override
  Future<KletsoCloseInfo> get done => Completer<KletsoCloseInfo>().future;
  @override
  Future<void> send(KletsoClientFrame frame) async {}
  @override
  Future<void> close([int code = 1000, String reason = '']) async {}
}
