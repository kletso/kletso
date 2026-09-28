import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

import 'support/scripted_transport.dart';

KletsoConnection connection(
  ScriptedTransport t, {
  KletsoConfig? config,
  KletsoTokenRefresher? onTokenExpired,
}) => KletsoConnection(
  transport: t,
  config: config ?? testConfig(),
  log: KletsoLog(KletsoLogLevel.none),
  realtimeUrl: Uri.parse('wss://x/v1/realtime'),
  token: 'kst_1',
  onTokenExpired: onTokenExpired,
  random: MaxRandom(),
);

void main() {
  test('connect opens, reports ready seq and dedupes events', () {
    fakeAsync((async) {
      final t = ScriptedTransport()..willOpen(readySeq: 5);
      final c = connection(t)..attach('conv_1', after: 5);
      final states = <KletsoConnectionState>[];
      c.state.addListener(() => states.add(c.state.value));
      final seqs = <int>[];
      c.events.listen((e) => seqs.add(e.seq));
      unawaited(c.connect());
      async.flushMicrotasks();
      expect(states, [
        KletsoConnectionState.connecting,
        KletsoConnectionState.open,
      ]);
      expect(t.requests.single.after, 5);
      expect(t.requests.single.conversationId, 'conv_1');
      t.current
        ..pushEvent(6)
        ..pushEvent(7)
        ..pushEvent(7)
        ..pushEvent(6)
        ..pushEvent(8, id: 'evt_7') // new seq, seen id
        ..pushEvent(9, conversationId: 'conv_other')
        ..pushEvent(9);
      async.flushMicrotasks();
      expect(seqs, [6, 7, 9]);
      expect(c.lastSeq, 9);
      unawaited(c.dispose());
      async.flushMicrotasks();
    });
  });

  test(
    'queued frames flush in order after ready; overflow drops the oldest',
    () {
      fakeAsync((async) {
        final t = ScriptedTransport()..willOpen();
        final c = connection(t);
        final errors = <KletsoException>[];
        c.errors.listen(errors.add);
        c
          ..send(const KletsoMessageFrame(clientId: 'a', text: '1'))
          ..send(const KletsoMessageFrame(clientId: 'b', text: '2'))
          ..send(const KletsoMessageFrame(clientId: 'c', text: '3'))
          ..send(const KletsoMessageFrame(clientId: 'd', text: '4'));
        expect(c.queuedFrames, 3);
        async.flushMicrotasks();
        expect(
          errors.single,
          isA<KletsoQueueOverflowException>().having(
            (e) => e.droppedClientId,
            'dropped',
            'a',
          ),
        );
        unawaited(c.connect());
        async.flushMicrotasks();
        expect(t.current.sent.map((f) => (f as KletsoMessageFrame).clientId), [
          'b',
          'c',
          'd',
        ]);
        // open: frames go straight out
        c.send(const KletsoTypingFrame());
        async.flushMicrotasks();
        expect(t.current.sent.last, isA<KletsoTypingFrame>());
        expect(c.queuedFrames, 0);
        unawaited(c.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test('heartbeat pings; a missing pong closes with 4000 and reconnects', () {
    fakeAsync((async) {
      final t = ScriptedTransport()
        ..willOpen(readySeq: 0)
        ..willOpen(readySeq: 3);
      final c = connection(t)..attach('conv_1');
      unawaited(c.connect());
      async.flushMicrotasks();
      final first = t.current;
      first.pushEvent(1);
      first.pushEvent(2);
      first.pushEvent(3);
      async.elapse(const Duration(seconds: 25));
      expect(first.sent.whereType<KletsoPingFrame>(), hasLength(1));
      first.push(const KletsoPongFrame());
      async.elapse(const Duration(seconds: 25));
      expect(first.sent.whereType<KletsoPingFrame>(), hasLength(2));
      // no pong this time
      async.elapse(const Duration(seconds: 10));
      expect(first.closed, isTrue);
      expect(first.closeCode, KletsoCloseCodes.heartbeatTimeout);
      expect(c.state.value, KletsoConnectionState.reconnecting);
      // backoff: MaxRandom → exactly the 500 ms ceiling
      async.elapse(const Duration(milliseconds: 499));
      expect(t.sockets, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(t.sockets, hasLength(2));
      expect(t.requests.last.after, 3, reason: 'resumes with the last seq');
      expect(c.state.value, KletsoConnectionState.open);
      unawaited(c.dispose());
      async.flushMicrotasks();
    });
  });

  test(
    'backoff grows 500 → 1000 → 2000 and resets after a successful open',
    () {
      fakeAsync((async) {
        final t = ScriptedTransport()
          ..willFail(const KletsoNetworkException('down'))
          ..willFail(const KletsoNetworkException('down'))
          ..willFail(const KletsoTimeoutException('slow'))
          ..willOpen()
          ..willFail(const KletsoNetworkException('down'))
          ..willOpen();
        final c = connection(t);
        final errors = <KletsoException>[];
        c.errors.listen(errors.add);
        unawaited(c.connect());
        async.flushMicrotasks();
        expect(t.requests, hasLength(1));
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(t.requests, hasLength(2));
        async.elapse(const Duration(milliseconds: 1000));
        async.flushMicrotasks();
        expect(t.requests, hasLength(3));
        async.elapse(const Duration(milliseconds: 2000));
        async.flushMicrotasks();
        expect(t.requests, hasLength(4));
        expect(c.state.value, KletsoConnectionState.open);
        expect(errors, hasLength(3));
        // drop → one failure → next delay is back at the 500 ms base
        t.current.serverClose(1006);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(t.requests, hasLength(5));
        async.elapse(const Duration(milliseconds: 1000));
        async.flushMicrotasks();
        expect(t.requests, hasLength(6));
        expect(c.state.value, KletsoConnectionState.open);
        unawaited(c.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test('4403 asks for a new token and reconnects with it; 4401 stops', () {
    fakeAsync((async) {
      final t = ScriptedTransport()
        ..willOpen()
        ..willOpen()
        ..willOpen();
      var refreshes = 0;
      final c = connection(
        t,
        onTokenExpired: () async {
          refreshes++;
          return 'kst_fresh$refreshes';
        },
      );
      final errors = <KletsoException>[];
      c.errors.listen(errors.add);
      unawaited(c.connect());
      async.flushMicrotasks();
      t.current.serverClose(KletsoCloseCodes.tokenExpired, 'expired');
      async.flushMicrotasks();
      expect(refreshes, 1);
      expect(t.requests.last.token, 'kst_fresh1');
      expect(c.state.value, KletsoConnectionState.open);
      // expired during the handshake itself
      t.current.serverClose(1006);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      expect(c.state.value, KletsoConnectionState.open);
      t.current.serverClose(KletsoCloseCodes.authFailed, 'bad key');
      async.flushMicrotasks();
      expect(c.state.value, KletsoConnectionState.closed);
      expect(
        errors.last,
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', false),
      );
      expect(c.wantsConnection, isFalse);
      unawaited(c.dispose());
      async.flushMicrotasks();
    });
  });

  test(
    'expired token during first handshake with no refresher fails connect()',
    () {
      fakeAsync((async) {
        final t = ScriptedTransport()
          ..willFail(const KletsoAuthException('expired', expired: true));
        final c = connection(t);
        Object? error;
        unawaited(c.connect().catchError((Object e) => error = e));
        async.flushMicrotasks();
        expect(error, isA<KletsoAuthException>());
        expect(c.state.value, KletsoConnectionState.closed);
        unawaited(c.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test('refresher failure surfaces as auth error', () {
    fakeAsync((async) {
      final t = ScriptedTransport()..willOpen();
      final c = connection(
        t,
        onTokenExpired: () async => throw StateError('no backend'),
      );
      final errors = <KletsoException>[];
      c.errors.listen(errors.add);
      unawaited(c.connect());
      async.flushMicrotasks();
      t.current.serverClose(KletsoCloseCodes.tokenExpired);
      async.flushMicrotasks();
      expect(errors.single, isA<KletsoAuthException>());
      expect(c.state.value, KletsoConnectionState.closed);
      unawaited(c.dispose());
      async.flushMicrotasks();
    });
  });

  test(
    'disconnect during backoff returns promptly; dispose stops everything',
    () {
      fakeAsync((async) {
        final t = ScriptedTransport()
          ..willFail(const KletsoNetworkException('down'));
        final c = connection(t);
        unawaited(c.connect());
        async.flushMicrotasks();
        expect(c.state.value, KletsoConnectionState.connecting);
        var disconnected = false;
        unawaited(c.disconnect().then((_) => disconnected = true));
        async.flushMicrotasks();
        expect(disconnected, isTrue);
        expect(c.state.value, KletsoConnectionState.closed);
        expect(t.requests, hasLength(1));
        async.elapse(const Duration(minutes: 1));
        expect(t.requests, hasLength(1), reason: 'loop stopped');
        unawaited(c.dispose());
        async.flushMicrotasks();
        expect(
          () => c.send(const KletsoPingFrame()),
          throwsA(isA<KletsoStateException>()),
        );
        expect(() => c.connect(), throwsA(isA<KletsoStateException>()));
      });
    },
  );

  test(
    'attach while open sends switch; a lower ready seq resets the cursor',
    () {
      fakeAsync((async) {
        final t = ScriptedTransport()..willOpen();
        final c = connection(t)..attach('conv_1');
        final readies = <KletsoReadyFrame>[];
        c.readies.listen(readies.add);
        unawaited(c.connect());
        async.flushMicrotasks();
        t.current.pushEvent(1);
        t.current.pushEvent(2);
        async.flushMicrotasks();
        expect(c.lastSeq, 2);
        c.attach('conv_2', after: 0);
        async.flushMicrotasks();
        expect(
          t.current.sent.last,
          const KletsoSwitchFrame(conversationId: 'conv_2', after: 0),
        );
        t.current.push(
          const KletsoReadyFrame(seq: 0, conversationId: 'conv_2'),
        );
        t.current.pushEvent(1, conversationId: 'conv_2');
        async.flushMicrotasks();
        expect(c.lastSeq, 1);
        expect(readies.map((r) => r.conversationId), ['conv_1', 'conv_2']);
        c.attach('conv_2'); // no-op
        expect(t.current.sent.whereType<KletsoSwitchFrame>(), hasLength(1));
        unawaited(c.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test(
    'error frames and stream errors are reported, unknown frames ignored',
    () {
      fakeAsync((async) {
        final t = ScriptedTransport()..willOpen();
        final c = connection(t);
        final errors = <KletsoException>[];
        c.errors.listen(errors.add);
        unawaited(c.connect());
        async.flushMicrotasks();
        t.current
          ..push(
            const KletsoErrorFrame(
              code: 'rate_limited',
              message: 'slow',
              retryAfterMs: 1500,
            ),
          )
          ..push(const KletsoErrorFrame(code: 'unauthorized', message: 'nope'))
          ..push(
            const KletsoErrorFrame(
              code: 'invalid_request',
              message: 'bad',
              retryable: false,
            ),
          )
          ..push(
            const KletsoUnknownServerFrame('hint', <String, Object?>{
              't': 'hint',
            }),
          )
          ..pushError(const KletsoProtocolException('garbage'))
          ..pushError(StateError('boom'));
        async.flushMicrotasks();
        expect(errors, hasLength(5));
        expect(
          errors[0],
          isA<KletsoRateLimitException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(milliseconds: 1500),
          ),
        );
        expect(errors[1], isA<KletsoAuthException>());
        expect(
          errors[2],
          isA<KletsoServerException>().having(
            (e) => e.code,
            'code',
            'invalid_request',
          ),
        );
        expect(errors[3], isA<KletsoProtocolException>());
        expect(errors[4], isA<KletsoProtocolException>());
        expect(c.state.value, KletsoConnectionState.open);
        unawaited(c.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test('send failure requeues the frame for the next socket', () {
    fakeAsync((async) {
      final t = ScriptedTransport()
        ..willOpen()
        ..willOpen();
      final c = connection(t);
      unawaited(c.connect());
      async.flushMicrotasks();
      final first = t.current;
      first.failSends = true; // send() throws, socket not yet closed
      c.send(const KletsoMessageFrame(clientId: 'x', text: 'hi'));
      async.flushMicrotasks();
      expect(c.queuedFrames, 1);
      first.serverClose(1006);
      async.elapse(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      expect(
        t.current.sent.single,
        const KletsoMessageFrame(clientId: 'x', text: 'hi'),
      );
      unawaited(c.dispose());
      async.flushMicrotasks();
    });
  });

  test('connect twice returns the same future; disconnect keeps the queue', () {
    fakeAsync((async) {
      final t = ScriptedTransport()
        ..willOpen()
        ..willOpen();
      final c = connection(t);
      final f1 = c.connect();
      final f2 = c.connect();
      expect(identical(f1, f2), isTrue);
      async.flushMicrotasks();
      unawaited(c.disconnect());
      async.flushMicrotasks();
      c.send(const KletsoTypingFrame());
      expect(c.queuedFrames, 1);
      unawaited(c.connect());
      async.flushMicrotasks();
      expect(t.current.sent.single, isA<KletsoTypingFrame>());
      unawaited(c.dispose());
      async.flushMicrotasks();
    });
  });
}
