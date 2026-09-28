import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

final config = KletsoConfig(
  publishableKey: 'kl_pub_abc',
  agentId: 'agt_1',
  baseUrl: Uri.parse('https://api.test'),
  logLevel: KletsoLogLevel.none,
);

const bootstrapJson = <String, Object?>{
  'session': {
    'id': 'ses_1',
    'token': 'kst_1',
    'expiresAt': '2026-09-28T13:00:00Z',
  },
  'endUser': {'id': 'eu_1', 'anonymous': false},
  'agent': {
    'id': 'agt_1',
    'versionId': 'agv_1',
    'name': 'Acme',
    'greeting': 'Hi',
    'allowedComponents': ['acme.productCard'],
  },
  'theme': {'primary': '#FF6A2B'},
  'minClient': '0.1.0',
  'realtime': {'url': 'wss://api.test/v1/realtime'},
  'allowedUrlHosts': ['acme.com'],
};

void main() {
  test(
    'createSession sends key, user token, device and parses the bootstrap',
    () async {
      late http.Request seen;
      final api = KletsoHttpApi(
        config,
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode(bootstrapJson),
            200,
            headers: {'kletso-request-id': 'req_1'},
          );
        }),
      );
      final b = await api.createSession(
        agentId: 'agt_1',
        device: const KletsoDevice(platform: 'test'),
        userToken: 'jwt',
        visitorId: 'anon_1',
        context: {'plan': 'pro'},
      );
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.test/v1/sessions');
      expect(seen.headers['Authorization'], 'Bearer kl_pub_abc');
      expect(seen.headers['X-Kletso-User-Token'], 'jwt');
      final body = jsonDecode(seen.body) as Map<String, Object?>;
      expect(body['agentId'], 'agt_1');
      expect(body['visitorId'], 'anon_1');
      expect((body['device'] as Map)['platform'], 'test');
      expect((body['context'] as Map)['plan'], 'pro');
      expect(b.session.token, 'kst_1');
      expect(b.session.expiresAt, DateTime.utc(2026, 9, 28, 13));
      expect(b.endUser.anonymous, isFalse);
      expect(b.agent.allowedComponents, ['acme.productCard']);
      expect(b.realtimeUrl.scheme, 'wss');
      expect(b.allowedUrlHosts, ['acme.com']);
      expect(b.theme['primary'], '#FF6A2B');
      expect(b.withSession(b.session).agent.name, 'Acme');
      expect(
        b.session.expiresWithin(
          const Duration(minutes: 5),
          DateTime.utc(2026, 9, 28, 12, 56),
        ),
        isTrue,
      );
      expect(
        b.session.expiresWithin(
          const Duration(minutes: 5),
          DateTime.utc(2026, 9, 28, 12),
        ),
        isFalse,
      );
      api.close();
    },
  );

  test('error envelopes map to typed exceptions', () async {
    Future<KletsoHttpApi> apiWith(
      int status,
      Map<String, Object?> body, [
      Map<String, String> headers = const {},
    ]) async => KletsoHttpApi(
      config,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          status,
          headers: {'kletso-request-id': 'req_9', ...headers},
        ),
      ),
    );
    const err = {
      'error': {'code': 'invalid_request', 'message': 'orderId is required'},
    };
    final s = KletsoSession(
      id: 's',
      token: 'kst_1',
      expiresAt: DateTime.utc(2027),
    );

    await expectLater(
      (await apiWith(400, err)).listConversations(s),
      throwsA(
        isA<KletsoServerException>()
            .having((e) => e.code, 'code', 'invalid_request')
            .having((e) => e.requestId, 'requestId', 'req_9')
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.retryable, 'retryable', false),
      ),
    );
    await expectLater(
      (await apiWith(500, {
        'error': {'code': 'internal', 'message': 'x'},
      })).listConversations(s),
      throwsA(
        isA<KletsoServerException>().having(
          (e) => e.retryable,
          'retryable',
          true,
        ),
      ),
    );
    await expectLater(
      (await apiWith(401, {
        'error': {'code': 'unauthorized', 'message': 'bad key'},
      })).listConversations(s),
      throwsA(
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', false),
      ),
    );
    await expectLater(
      (await apiWith(401, {
        'error': {'code': 'token_expired', 'message': 'old'},
      })).listConversations(s),
      throwsA(
        isA<KletsoAuthException>().having((e) => e.expired, 'expired', true),
      ),
    );
    await expectLater(
      (await apiWith(
        429,
        {
          'error': {'code': 'rate_limited', 'message': 'slow'},
        },
        {'retry-after': '7'},
      )).listConversations(s),
      throwsA(
        isA<KletsoRateLimitException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 7),
        ),
      ),
    );
    await expectLater(
      (await apiWith(502, {})).listConversations(s),
      throwsA(
        isA<KletsoServerException>().having(
          (e) => e.message,
          'message',
          'HTTP 502',
        ),
      ),
    );
  });

  test(
    'network and timeout errors are typed; bad JSON is a protocol error',
    () async {
      final s = KletsoSession(
        id: 's',
        token: 'kst_1',
        expiresAt: DateTime.utc(2027),
      );
      final down = KletsoHttpApi(
        config,
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      await expectLater(
        down.listConversations(s),
        throwsA(isA<KletsoNetworkException>()),
      );
      final slow = KletsoHttpApi(
        config,
        client: MockClient(
          (_) => Future<http.Response>.delayed(
            const Duration(seconds: 2),
            () => http.Response('{}', 200),
          ),
        ),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        slow.listConversations(s),
        throwsA(isA<KletsoTimeoutException>()),
      );
      final garbage = KletsoHttpApi(
        config,
        client: MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectLater(
        garbage.listConversations(s),
        throwsA(isA<KletsoProtocolException>()),
      );
      final noSession = KletsoHttpApi(
        config,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        noSession.createSession(
          agentId: 'a',
          device: const KletsoDevice(platform: 't'),
        ),
        throwsA(isA<KletsoProtocolException>()),
      );
      await expectLater(
        noSession.refreshSession(s),
        throwsA(isA<KletsoProtocolException>()),
      );
      await expectLater(
        noSession.createConversation(s),
        throwsA(isA<KletsoProtocolException>()),
      );
      noSession.close();
      await expectLater(
        noSession.listConversations(s),
        throwsA(isA<KletsoStateException>()),
      );
    },
  );

  test('conversation and event endpoints', () async {
    final s = KletsoSession(
      id: 's',
      token: 'kst_1',
      expiresAt: DateTime.utc(2027),
    );
    final calls = <http.Request>[];
    final api = KletsoHttpApi(
      config,
      client: MockClient((req) async {
        calls.add(req);
        final path = req.url.path;
        if (path.endsWith('/conversations') && req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'conversations': [
                {
                  'id': 'conv_1',
                  'agentId': 'agt_1',
                  'status': 'open',
                  'createdAt': '2026-09-28T12:00:00Z',
                  'lastSeq': 3,
                },
              ],
            }),
            200,
          );
        }
        if (path.endsWith('/conversations') && req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'conversation': {
                'id': 'conv_2',
                'agentId': 'agt_1',
                'title': 'T',
                'createdAt': '2026-09-28T12:00:00Z',
              },
            }),
            201,
          );
        }
        if (path.endsWith('/events')) {
          return http.Response(
            jsonEncode({
              'events': [
                KletsoFixtures.eventsConversation20! as List,
                'garbage',
              ].expand((e) => e is List ? e.take(3) : [e]).toList(),
            }),
            200,
          );
        }
        if (path.endsWith('/refresh')) {
          return http.Response(
            jsonEncode({
              'session': {
                'id': 's',
                'token': 'kst_2',
                'expiresAt': '2026-09-28T14:00:00Z',
              },
            }),
            200,
          );
        }
        return http.Response('', 204);
      }),
    );
    final list = await api.listConversations(s);
    expect(list.single.id, 'conv_1');
    expect(list.single.lastSeq, 3);
    final created = await api.createConversation(
      s,
      agentId: 'agt_1',
      title: 'T',
    );
    expect(created.id, 'conv_2');
    final events = await api.listEvents(s, 'conv_1', after: 0, limit: 10);
    expect(events, hasLength(3), reason: 'malformed entries are skipped');
    expect(calls.last.url.queryParameters, {'after': '0', 'limit': '10'});
    final refreshed = await api.refreshSession(s, userToken: 'jwt2');
    expect(refreshed.token, 'kst_2');
    expect(jsonDecode(calls.last.body), {'userToken': 'jwt2'});
    await api.deleteSession(s);
    expect(calls.last.method, 'DELETE');
    await api.updateContext(s, {'a': 1}, replace: true);
    expect(calls.last.method, 'PUT');
    await api.updateContext(s, {'a': 1}, replace: false);
    expect(calls.last.method, 'PATCH');
    await api.postMessage(
      s,
      'conv_1',
      const KletsoMessageFrame(clientId: 'c1', text: 'hi'),
    );
    expect(calls.last.url.path, '/v1/conversations/conv_1/messages');
    expect(jsonDecode(calls.last.body), {
      'text': 'hi',
      'value': null,
      'clientId': 'c1',
    });
    await api.postAction(
      s,
      'conv_1',
      const KletsoActionFrame(
        surfaceId: 's',
        componentId: 'c',
        actionId: 'a',
        clientId: 'c2',
        value: 1,
      ),
    );
    expect(calls.last.url.path, '/v1/conversations/conv_1/actions');
    await api.postTrigger(
      s,
      const KletsoTrackFrame(name: 'cart_abandoned', properties: {'v': 1}),
    );
    expect(calls.last.url.path, '/v1/events');
    await api.postTrigger(s, const KletsoScreenFrame(name: 'checkout'));
    expect((jsonDecode(calls.last.body) as Map)['screen'], 'checkout');
    expect(
      () => api.postTrigger(s, const KletsoPingFrame()),
      throwsArgumentError,
    );
    await api.registerPushToken(
      s,
      const KletsoPushToken(platform: KletsoPushPlatform.fcm, token: 'fcm-1'),
    );
    expect(calls.last.method, 'PUT');
    expect(calls.last.url.path, '/v1/sessions/current/push-token');
    expect(jsonDecode(calls.last.body), {'platform': 'fcm', 'token': 'fcm-1'});
    await api.unregisterPushToken(s);
    expect(calls.last.method, 'DELETE');
    expect(calls.last.url.path, '/v1/sessions/current/push-token');
    expect(
      calls.every((c) => c.headers['Authorization'] == 'Bearer kst_1'),
      isTrue,
    );
    api.close();
  });
}
