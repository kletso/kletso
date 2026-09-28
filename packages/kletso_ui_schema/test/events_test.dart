import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:test/test.dart';

void main() {
  notifyTests();
  final log = (KletsoFixtures.eventsConversation20! as List)
      .cast<Map<String, Object?>>();

  test('conversation_20 has 20 messages and contiguous seq', () {
    final envelopes = log.map(KletsoEventEnvelope.fromJson).toList();
    expect(
      envelopes.where((e) => e.type == KletsoEventTypes.messageCreated),
      hasLength(20),
    );
    for (var i = 0; i < envelopes.length; i++) {
      expect(envelopes[i].seq, i + 1);
      if (i > 0) expect(envelopes[i].ts.isAfter(envelopes[i - 1].ts), isTrue);
    }
    expect(envelopes.map((e) => e.id).toSet(), hasLength(envelopes.length));
    expect(envelopes.first.type, KletsoEventTypes.conversationCreated);
    expect(
      envelopes.map((e) => e.type).toSet(),
      containsAll(<String>[
        KletsoEventTypes.messageDelta,
        KletsoEventTypes.messageCompleted,
        KletsoEventTypes.toolStarted,
        KletsoEventTypes.toolCompleted,
        KletsoEventTypes.toolConfirmationRequired,
        KletsoEventTypes.uiRender,
        KletsoEventTypes.uiAction,
        KletsoEventTypes.agentTyping,
        KletsoEventTypes.handoffStarted,
        KletsoEventTypes.conversationUpdated,
      ]),
    );
  });

  test('the script equals the fixture on disk', () {
    final script = KletsoConversationScript().build();
    expect(script.map((e) => e.toJson()).toList(), log);
    expect(KletsoConversationScript().build(), hasLength(script.length));
  });

  test('every envelope round-trips and has a typed payload', () {
    for (final raw in log) {
      final e = KletsoEventEnvelope.fromJson(raw);
      expect(jsonEquals(e.toJson(), raw), isTrue, reason: '$raw');
      expect(KletsoEventEnvelope.fromJson(e.toJson()), e);
      expect(e.payload, isNot(isA<KletsoUnknownEvent>()));
      expect(e.toString(), contains(e.type));
    }
  });

  test('every ui.render surface in the log is a valid surface', () {
    final renders = log
        .map(KletsoEventEnvelope.fromJson)
        .where((e) => e.type == KletsoEventTypes.uiRender)
        .map((e) => e.payload as KletsoUiRender);
    expect(renders, hasLength(6));
    for (final r in renders) {
      final res = r.parse(knownTypes: {'acme.productCard'});
      expect(res, isA<KletsoSurfaceOk>(), reason: res.issues.join());
    }
  });

  test('streamed deltas concatenate to the completed text', () {
    final envelopes = log.map(KletsoEventEnvelope.fromJson).toList();
    final deltas = <String, StringBuffer>{};
    for (final e in envelopes) {
      switch (e.payload) {
        case KletsoMessageDelta(:final messageId, :final text):
          (deltas[messageId] ??= StringBuffer()).write(text);
        case KletsoMessageCompleted(:final messageId, :final text):
          expect(deltas[messageId].toString(), text);
        default:
          break;
      }
    }
    expect(deltas, hasLength(10));
  });

  test('typed payloads read their fields', () {
    KletsoEventEnvelope env(String type, Map<String, Object?> data) =>
        KletsoEventEnvelope(
          id: 'evt_1',
          seq: 1,
          type: type,
          ts: DateTime.utc(2026),
          conversationId: 'conv_1',
          data: data,
        );

    final created =
        env('message.created', {
              'messageId': 'msg_1',
              'role': 'user',
              'text': 'hi',
              'clientId': 'c_1',
            }).payload
            as KletsoMessageCreated;
    expect(created.role, KletsoRole.user);
    expect(created.clientId, 'c_1');

    final completed =
        env('message.completed', {
              'messageId': 'msg_1',
              'text': 'done',
              'usage': {'in': 10, 'out': 5, 'cachedIn': 3, 'reasoning': 1},
              'costMicros': 42,
              'latencyMs': 900,
              'finishReason': 'length',
            }).payload
            as KletsoMessageCompleted;
    expect(completed.inputTokens, 10);
    expect(completed.reasoningTokens, 1);
    expect(completed.finishReason, KletsoFinishReason.length);
    expect(completed.costMicros, 42);

    final failed =
        env('tool.failed', {
              'toolCallId': 'call_1',
              'name': 'x',
              'durationMs': 5,
              'error': {'code': 'timeout', 'message': 'slow'},
            }).payload
            as KletsoToolFinished;
    expect(failed.failed, isTrue);
    expect(failed.errorCode, 'timeout');

    final ok =
        env('tool.completed', {
              'toolCallId': 'call_1',
              'name': 'x',
              'durationMs': 5,
              'result': [1],
            }).payload
            as KletsoToolFinished;
    expect(ok.failed, isFalse);
    expect(ok.result, [1]);

    final wf =
        env('workflow.failed', {'runId': 'run_1', 'error': 'boom'}).payload
            as KletsoWorkflowEvent;
    expect(wf.status, KletsoWorkflowStatus.failed);
    expect(wf.error, 'boom');

    final ho =
        env('handoff.completed', {'target': 'inbox'}).payload
            as KletsoHandoffEvent;
    expect(ho.completed, isTrue);

    final tf =
        env('trigger.fired', {
              'triggerId': 't',
              'kind': 'screen',
              'name': 'checkout',
            }).payload
            as KletsoTriggerFired;
    expect(tf.kind, KletsoTriggerKind.screen);

    final err =
        env('error', {
              'code': 'provider_error',
              'message': 'x',
              'retryable': true,
            }).payload
            as KletsoErrorEvent;
    expect(err.retryable, isTrue);

    expect(env('agent.typing', {}).payload, isA<KletsoAgentTyping>());

    final conv =
        env('conversation.closed', {
              'conversation': {
                'id': 'conv_1',
                'agentId': 'agt_1',
                'status': 'closed',
                'createdAt': '2026-09-28T12:00:00Z',
                'lastSeq': 7,
              },
            }).payload
            as KletsoConversationEvent;
    expect(conv.conversation.status, KletsoConversationStatus.closed);
    expect(conv.conversation.lastSeq, 7);
    expect(conv.conversation.createdAt, DateTime.utc(2026, 9, 28, 12));
    expect(conv.conversation.toJson()['id'], 'conv_1');

    final confirmation =
        env('tool.confirmation_required', {
              'toolCallId': 'call_1',
              'name': 'cancel',
              'surface': KletsoFixtures.confirm,
            }).payload
            as KletsoToolConfirmationRequired;
    expect(confirmation.surface, isNotNull);
    final badConfirmation =
        env('tool.confirmation_required', {
              'toolCallId': 'call_1',
              'name': 'cancel',
              'surface': 'nope',
            }).payload
            as KletsoToolConfirmationRequired;
    expect(badConfirmation.surface, isNull);

    final action =
        env('ui.action', {
              'surfaceId': 's',
              'componentId': 'c',
              'actionId': 'a',
              'value': 1,
            }).payload
            as KletsoUiActionEvent;
    expect(action.value, 1);
  });

  test('missing fields fall back to defaults instead of throwing', () {
    final e = KletsoEventEnvelope(
      id: 'evt_1',
      seq: 1,
      type: 'message.completed',
      ts: DateTime.utc(2026),
      conversationId: 'conv_1',
    );
    final p = e.payload as KletsoMessageCompleted;
    expect(p.messageId, '');
    expect(p.finishReason, KletsoFinishReason.unknown);
    expect(p.inputTokens, 0);
    final conv =
        KletsoEventEnvelope(
              id: 'evt_1',
              seq: 1,
              type: 'conversation.created',
              ts: DateTime.utc(2026),
              conversationId: 'conv_1',
            ).payload
            as KletsoConversationEvent;
    expect(conv.conversation.id, '');
  });

  test('unknown enum values parse to unknown', () {
    expect(KletsoRole.parse('robot'), KletsoRole.unknown);
    expect(KletsoRole.parse(null), KletsoRole.unknown);
    expect(KletsoRole.parse('tool'), KletsoRole.tool);
    expect(
      KletsoConversationStatus.parse('archived'),
      KletsoConversationStatus.unknown,
    );
    expect(
      KletsoFinishReason.parse('tool_calls'),
      KletsoFinishReason.toolCalls,
    );
    expect(KletsoTriggerKind.parse('time'), KletsoTriggerKind.time);
    expect(KletsoWorkflowStatus.parse('paused'), KletsoWorkflowStatus.unknown);
    for (final r in KletsoRole.values) {
      expect(KletsoRole.parse(r.wire), r);
    }
  });

  test('unknown event types are tolerated', () {
    final e = KletsoEventEnvelope.fromJson({
      'id': 'evt_9',
      'seq': 9,
      'type': 'billing.invoice_ready',
      'ts': '2026-09-28T12:00:00Z',
      'conversationId': 'conv_1',
      'data': {'url': 'https://x'},
    });
    final p = e.payload as KletsoUnknownEvent;
    expect(p.type, 'billing.invoice_ready');
    expect(p.data['url'], 'https://x');
  });

  test('envelope structure errors throw with a path', () {
    expect(
      () => KletsoEventEnvelope.fromJson({'id': 'evt_1'}),
      throwsA(isA<KletsoSchemaException>()),
    );
    expect(
      () => KletsoEventEnvelope.fromJson({
        'id': 'evt_1',
        'seq': 1,
        'type': 'x.y',
        'ts': 'yesterday',
        'conversationId': 'conv_1',
        'data': <String, Object?>{},
      }),
      throwsA(
        isA<KletsoSchemaException>().having((e) => e.path, 'path', r'$/ts'),
      ),
    );
    expect(
      () => KletsoEventEnvelope.fromJson({
        'id': 'evt_1',
        'seq': 1.5,
        'type': 'x.y',
        'ts': '2026-09-28T12:00:00Z',
        'conversationId': 'conv_1',
        'data': <String, Object?>{},
      }),
      throwsA(
        isA<KletsoSchemaException>().having((e) => e.path, 'path', r'$/seq'),
      ),
    );
    expect(
      () => KletsoEventEnvelope.fromJson({
        'id': 'evt_1',
        'seq': 1,
        'type': 'x.y',
        'ts': '2026-09-28T12:00:00Z',
        'conversationId': 'conv_1',
        'data': <Object?>[],
      }),
      throwsA(isA<KletsoSchemaException>()),
    );
    // whole-number doubles (JS clients) are accepted as ints
    expect(
      KletsoEventEnvelope.fromJson({
        'id': 'evt_1',
        'seq': 2.0,
        'type': 'x.y',
        'ts': '2026-09-28T12:00:00Z',
        'conversationId': 'conv_1',
      }).seq,
      2,
    );
  });
}

void notifyTests() {
  Map<String, Object?> envelope(Map<String, Object?> data) => <String, Object?>{
    'id': 'evt_01J8NTF00001',
    'seq': 7,
    'type': 'app.notify',
    'ts': '2026-09-28T12:00:00Z',
    'conversationId': 'conv_01J8FAKE000001',
    'data': data,
  };

  test('app.notify parses every field and defaults the rest', () {
    final full = KletsoEventEnvelope.fromJson(
      envelope(<String, Object?>{
        'notificationId': 'ntf_01J8GEO1',
        'title': 'Welcome to Acme Shibuya',
        'body': 'Show this for 10% off today.',
        'channel': 'alert',
        'openChat': true,
        'action': <String, Object?>{
          'id': 'coupon',
          'kind': 'local',
          'name': 'open_coupon',
          'args': <String, Object?>{'code': 'SHIBUYA10'},
        },
        'surface': KletsoFixtures.quickReplies,
        'ttlSeconds': 12,
        'imageUrl': 'https://cdn.acme.com/store.jpg',
        'data': <String, Object?>{'storeId': 'st_1'},
      }),
    );
    final n = full.payload as KletsoAppNotification;
    expect(n.notificationId, 'ntf_01J8GEO1');
    expect(n.channel, KletsoNotificationChannel.alert);
    expect(n.openChat, isTrue);
    expect((n.action! as KletsoLocalAction).name, 'open_coupon');
    expect(n.parseSurface(), isA<KletsoSurfaceOk>());
    expect(n.ttl, const Duration(seconds: 12));
    expect(n.data, <String, Object?>{'storeId': 'st_1'});
    expect(n.toJson()['channel'], 'alert');
    expect(
      KletsoEventEnvelope.fromJson(envelope(n.toJson())).payload,
      isA<KletsoAppNotification>(),
    );

    final minimal =
        KletsoEventEnvelope.fromJson(
              envelope(<String, Object?>{
                'notificationId': 'ntf_2',
                'title': 'Hi',
                'channel': 'hologram',
              }),
            ).payload
            as KletsoAppNotification;
    expect(minimal.channel, KletsoNotificationChannel.banner);
    expect(minimal.openChat, isFalse);
    expect(minimal.action, isNull);
    expect(minimal.parseSurface(), isNull);
    expect(minimal.ttl, isNull);
    expect(minimal.toJson().containsKey('openChat'), isFalse);
  });
}
