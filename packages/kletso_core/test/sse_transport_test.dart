import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

final class RecordingApi implements KletsoApi {
  final List<String> calls = <String>[];
  @override
  Future<KletsoSessionBootstrap> createSession({
    required String agentId,
    required KletsoDevice device,
    String? userToken,
    String? visitorId,
    JsonMap context = const {},
  }) => throw UnimplementedError();
  @override
  Future<KletsoSession> refreshSession(
    KletsoSession current, {
    String? userToken,
  }) => throw UnimplementedError();
  @override
  Future<void> deleteSession(KletsoSession session) =>
      throw UnimplementedError();
  @override
  Future<void> updateContext(
    KletsoSession session,
    JsonMap context, {
    required bool replace,
  }) async =>
      calls.add('context:${replace ? 'replace' : 'merge'}:${session.token}');
  @override
  Future<List<KletsoConversation>> listConversations(KletsoSession session) =>
      throw UnimplementedError();
  @override
  Future<KletsoConversation> createConversation(
    KletsoSession session, {
    String? agentId,
    String? title,
  }) => throw UnimplementedError();
  @override
  Future<List<KletsoEventEnvelope>> listEvents(
    KletsoSession session,
    String conversationId, {
    int after = 0,
    int limit = 200,
  }) => throw UnimplementedError();
  @override
  Future<void> postMessage(
    KletsoSession session,
    String conversationId,
    KletsoMessageFrame frame,
  ) async => calls.add('message:$conversationId:${frame.clientId}');
  @override
  Future<void> postAction(
    KletsoSession session,
    String conversationId,
    KletsoActionFrame frame,
  ) async => calls.add('action:$conversationId:${frame.actionId}');
  @override
  Future<void> postTrigger(
    KletsoSession session,
    KletsoClientFrame frame,
  ) async => calls.add('trigger:${frame.t}');
  @override
  Future<void> registerPushToken(
    KletsoSession session,
    KletsoPushToken token,
  ) async => calls.add('push:${token.platform.wire}');
  @override
  Future<void> unregisterPushToken(KletsoSession session) async =>
      calls.add('push:none');
  @override
  void close() {}
}

void main() {
  final apiRoot = Uri.parse('https://api.test/v1');
  final req = KletsoTransportRequest(
    realtimeUrl: Uri.parse('wss://x'),
    token: 'kst_1',
    conversationId: 'conv_1',
    after: 2,
  );
  final log = (KletsoFixtures.eventsConversation20! as List)
      .cast<Map<String, Object?>>();

  String sse(String event, Object data, [int? id]) =>
      '${id == null ? '' : 'id: $id\n'}event: $event\ndata: ${jsonEncode(data)}\n\n';

  test(
    'opens with bearer header, handles ready, events, comments, chunk splits and sends via REST',
    () async {
      late http.BaseRequest seen;
      final body = StreamController<List<int>>();
      final api = RecordingApi();
      final t = KletsoSseTransport(
        api: api,
        apiRoot: apiRoot,
        client: MockClient.streaming((request, _) async {
          seen = request;
          return http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      expect(t.name, 'sse');
      final opening = t.open(req);
      await Future<void>.delayed(Duration.zero);
      expect(
        seen.url.toString(),
        'https://api.test/v1/conversations/conv_1/events?after=2&stream=1',
      );
      expect(seen.headers['Authorization'], 'Bearer kst_1');
      expect(seen.headers['Accept'], 'text/event-stream');
      final readyText =
          ': hello\n${sse('ready', {'seq': 41, 'conversationId': 'conv_1'})}';
      body.add(utf8.encode(readyText.substring(0, 20)));
      body.add(utf8.encode(readyText.substring(20)));
      final socket = await opening;
      expect(socket.readySeq, 41);
      final frames = <KletsoServerFrame>[];
      final errors = <Object>[];
      socket.frames.listen(frames.add, onError: errors.add);
      body.add(
        utf8.encode(sse('event', {'t': 'event', 'event': log[1]}, 2)),
      ); // wrapped frame
      body.add(utf8.encode(sse('event', log[2], 3))); // bare envelope
      body.add(
        utf8.encode(sse('error', {'code': 'rate_limited', 'message': 'slow'})),
      );
      body.add(utf8.encode(sse('message', 'not an object')));
      body.add(utf8.encode('data: {broken\n\n'));
      await Future<void>.delayed(Duration.zero);
      expect(frames.map((f) => f.t), ['event', 'event', 'error']);
      expect(errors, hasLength(2));

      await socket.send(const KletsoMessageFrame(clientId: 'c1', text: 'hi'));
      await socket.send(
        const KletsoActionFrame(
          surfaceId: 's',
          componentId: 'c',
          actionId: 'go',
          clientId: 'c2',
        ),
      );
      await socket.send(const KletsoContextFrame.merge({'a': 1}));
      await socket.send(const KletsoContextFrame.replace({'a': 1}));
      await socket.send(const KletsoTrackFrame(name: 'x'));
      await socket.send(const KletsoScreenFrame(name: 'y'));
      await socket.send(const KletsoPingFrame());
      await socket.send(const KletsoTypingFrame());
      expect(api.calls, [
        'message:conv_1:c1',
        'action:conv_1:go',
        'context:merge:kst_1',
        'context:replace:kst_1',
        'trigger:track',
        'trigger:screen',
      ]);
      // switch ends the stream so the connection reopens for the new conversation
      await socket.send(const KletsoSwitchFrame(conversationId: 'conv_2'));
      final info = await socket.done;
      expect(info.code, KletsoCloseCodes.normal);
      expect(info.reason, 'switch');
      await expectLater(
        socket.send(const KletsoPingFrame()),
        throwsA(isA<KletsoNetworkException>()),
      );
      await body.close();
    },
  );

  test(
    'implicit ready: first event accepts the stream with the request cursor',
    () async {
      final body = StreamController<List<int>>();
      final t = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(body.stream, 200),
        ),
      );
      final opening = t.open(req);
      await Future<void>.delayed(Duration.zero);
      body.add(utf8.encode(sse('event', log[3], 4)));
      final socket = await opening;
      expect(socket.readySeq, 2);
      final first = await socket.frames.first;
      expect(first, isA<KletsoEventFrame>());
      await body.close();
      expect((await socket.done).code, isNull);
    },
  );

  test('HTTP status codes map to typed errors', () async {
    Future<void> expectStatus(int status, Matcher m) async {
      final t = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        client: MockClient.streaming(
          (_, _) async =>
              http.StreamedResponse(const Stream<List<int>>.empty(), status),
        ),
      );
      await expectLater(t.open(req), throwsA(m));
    }

    await expectStatus(
      401,
      isA<KletsoAuthException>().having((e) => e.expired, 'expired', false),
    );
    await expectStatus(
      403,
      isA<KletsoAuthException>().having((e) => e.expired, 'expired', true),
    );
    await expectStatus(
      429,
      isA<KletsoServerException>().having(
        (e) => e.code,
        'code',
        'rate_limited',
      ),
    );
    await expectStatus(
      500,
      isA<KletsoServerException>().having(
        (e) => e.retryable,
        'retryable',
        true,
      ),
    );
  });

  test(
    'network, timeout, missing conversation and stream close before ready',
    () async {
      final down = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        client: MockClient.streaming(
          (_, _) async => throw http.ClientException('refused'),
        ),
      );
      await expectLater(down.open(req), throwsA(isA<KletsoNetworkException>()));
      final slow = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        handshakeTimeout: const Duration(milliseconds: 20),
        client: MockClient.streaming(
          (_, _) => Future<http.StreamedResponse>.delayed(
            const Duration(seconds: 1),
            () => http.StreamedResponse(const Stream<List<int>>.empty(), 200),
          ),
        ),
      );
      await expectLater(slow.open(req), throwsA(isA<KletsoTimeoutException>()));
      final quiet = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        handshakeTimeout: const Duration(milliseconds: 20),
        client: MockClient.streaming(
          (_, _) async =>
              http.StreamedResponse(StreamController<List<int>>().stream, 200),
        ),
      );
      await expectLater(
        quiet.open(req),
        throwsA(isA<KletsoTimeoutException>()),
      );
      final noConv = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        client: MockClient.streaming(
          (_, _) async => throw StateError('unreachable'),
        ),
      );
      await expectLater(
        noConv.open(
          KletsoTransportRequest(
            realtimeUrl: Uri.parse('wss://x'),
            token: 'kst_1',
          ),
        ),
        throwsA(isA<KletsoProtocolException>()),
      );
      final ended = KletsoSseTransport(
        api: RecordingApi(),
        apiRoot: apiRoot,
        client: MockClient.streaming(
          (_, _) async =>
              http.StreamedResponse(const Stream<List<int>>.empty(), 200),
        ),
      );
      await expectLater(
        ended.open(req),
        throwsA(isA<KletsoNetworkException>()),
      );
    },
  );
}
