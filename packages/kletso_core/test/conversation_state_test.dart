import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

void main() {
  final log = (KletsoFixtures.eventsConversation20! as List)
      .map(KletsoEventEnvelope.fromJson)
      .toList();

  test('reduces the 20-message fixture into 20 complete messages', () {
    final state = KletsoConversationState('conv_01J8DEMO000001');
    for (final e in log) {
      state.apply(e);
    }
    final messages = state.messages;
    expect(messages, hasLength(20));
    expect(messages.where((m) => m.isUser), hasLength(10));
    expect(messages.where((m) => m.isAssistant), hasLength(10));
    expect(
      messages.every((m) => m.status == KletsoMessageStatus.complete),
      isTrue,
    );
    expect(state.lastSeq, log.last.seq);
    expect(messages.first.text, startsWith('Hi! I\'m Acme'));
    expect(messages.first.costMicros, 1850);
    expect(messages.first.latencyMs, 1400);
    // surfaces attach to the assistant message of their turn
    final withSurfaces = messages.where((m) => m.surfaces.isNotEmpty).toList();
    expect(withSurfaces, hasLength(6));
    expect(withSurfaces.first.surfaces.single.surfaceId, 'sfc_01J8FLIGHT0001');
    expect(
      withSurfaces.first.text,
      'Here\'s the best option for tomorrow morning:',
    );
    // tool calls arrive before message.created and still land on the message
    expect(withSurfaces.first.toolCalls.single.name, 'search_flights');
    expect(
      withSurfaces.first.toolCalls.single.status,
      KletsoToolCallStatus.completed,
    );
    expect(withSurfaces.first.toolCalls.single.durationMs, 820);
    // the confirm turn: the asking message owns the call and the later
    // tool.completed (in the next turn) updates that same call by id
    final asking = messages.firstWhere(
      (m) => m.text.startsWith('I can cancel'),
    );
    expect(asking.surfaces.single.surfaceId, 'sfc_01J8CONFIRM001');
    expect(asking.toolCalls.single.id, 'call_01J8CANCEL0001');
    expect(asking.toolCalls.single.status, KletsoToolCallStatus.completed);
    final done = messages.firstWhere((m) => m.text.startsWith('Done.'));
    expect(
      done.toolCalls,
      isEmpty,
      reason: 'completion updated the earlier call',
    );
    // action-originated user turns carry their value and label
    final select = messages.firstWhere((m) => m.value != null && m.isUser);
    expect(select.text, 'Select ANA NH873');
    expect((select.value! as Map)['intent'], 'select_flight');
  });

  test(
    'ui.patch updates a rendered surface in place; bad patches are ignored',
    () {
      final state = KletsoConversationState('conv_1');
      KletsoEventEnvelope env(
        int seq,
        String type,
        Map<String, Object?> data,
      ) => KletsoEventEnvelope(
        id: 'evt_$seq',
        seq: seq,
        type: type,
        ts: DateTime.utc(2026),
        conversationId: 'conv_1',
        turnId: 'trn_1',
        data: data,
      );
      state.apply(
        env(1, 'message.created', {
          'messageId': 'msg_1',
          'role': 'assistant',
          'text': 'x',
        }),
      );
      state.apply(env(2, 'ui.render', {'surface': KletsoFixtures.tripPlan}));
      expect(
        state.apply(
          env(3, 'ui.patch', {
            'surfaceId': 'sfc_01J8TRIP000001',
            'data': {
              'plan': {'progress': 1.0},
            },
          }),
        ),
        isTrue,
      );
      final s = state.messages.single.surfaces.single;
      expect(s.resolveNode(s.node('progress')!).number('value'), 1.0);
      expect(
        (s.data['plan']! as Map)['detail'],
        '2 of 4 steps done',
        reason: 'deep merge keeps siblings',
      );
      expect(
        state.apply(env(4, 'ui.patch', {'surfaceId': 'sfc_nope', 'data': {}})),
        isFalse,
      );
      expect(
        state.apply(
          env(5, 'ui.patch', {
            'surfaceId': 'sfc_01J8TRIP000001',
            'components': {'progress': 'garbage'},
          }),
        ),
        isFalse,
      );
      expect(
        state.messages.single.surfaces.single.node('progress')!.type,
        'progress',
      );
    },
  );

  test('deltas stream, completed replaces text', () {
    final state = KletsoConversationState('conv_01J8DEMO000001');
    final created = log.firstWhere(
      (e) =>
          e.type == 'message.created' &&
          (e.payload as KletsoMessageCreated).role == KletsoRole.assistant,
    );
    state.apply(created);
    expect(state.messages.single.status, KletsoMessageStatus.streaming);
    final deltas = log
        .where((e) => e.type == 'message.delta' && e.turnId == created.turnId)
        .toList();
    state.apply(deltas.first);
    expect(
      state.messages.single.text,
      (deltas.first.payload as KletsoMessageDelta).text,
    );
    state.apply(deltas[1]);
    expect(
      state.messages.single.text.length,
      greaterThan((deltas.first.payload as KletsoMessageDelta).text.length),
    );
    final completed = log.firstWhere(
      (e) => e.type == 'message.completed' && e.turnId == created.turnId,
    );
    state.apply(completed);
    expect(
      state.messages.single.text,
      (completed.payload as KletsoMessageCompleted).text,
    );
    expect(state.messages.single.status, KletsoMessageStatus.complete);
    // re-applying is harmless
    expect(state.apply(created), isTrue);
    expect(state.messages, hasLength(1));
  });

  test('pending echo takes the server position', () {
    final state = KletsoConversationState('conv_1');
    state.addPending('c_1', 'typed early', null);
    KletsoEventEnvelope env(int seq, Map<String, Object?> data) =>
        KletsoEventEnvelope(
          id: 'evt_$seq',
          seq: seq,
          type: 'message.created',
          ts: DateTime.utc(2026),
          conversationId: 'conv_1',
          data: data,
        );
    state.apply(
      env(1, {'messageId': 'msg_greeting', 'role': 'assistant', 'text': 'hi'}),
    );
    state.apply(
      env(2, {
        'messageId': 'msg_user',
        'role': 'user',
        'text': 'typed early',
        'clientId': 'c_1',
      }),
    );
    expect(state.messages.map((m) => m.id), ['msg_greeting', 'msg_user']);
    expect(state.messages.last.status, KletsoMessageStatus.complete);
  });

  test(
    'pending user message is replaced by the echo with the same clientId, or failed',
    () {
      final state = KletsoConversationState('conv_1');
      state.addPending('c_1', 'hello', null);
      expect(state.messages.single.status, KletsoMessageStatus.pending);
      expect(state.messages.single.id, 'c_1');
      state.apply(
        KletsoEventEnvelope(
          id: 'evt_1',
          seq: 1,
          type: 'message.created',
          ts: DateTime.utc(2026),
          conversationId: 'conv_1',
          data: {
            'messageId': 'msg_1',
            'role': 'user',
            'text': 'hello',
            'clientId': 'c_1',
          },
        ),
      );
      expect(state.messages.single.id, 'msg_1');
      expect(state.messages.single.status, KletsoMessageStatus.complete);
      state.addPending('c_2', 'again', {'x': 1});
      state.failPending(
        'c_2',
        const KletsoErrorEvent(code: 'internal', message: 'x', retryable: true),
      );
      expect(state.messages.last.status, KletsoMessageStatus.failed);
      expect(state.messages.last.error!.code, 'internal');
      state.failPending(
        'nope',
        const KletsoErrorEvent(code: 'internal', message: 'x', retryable: true),
      );
    },
  );

  test(
    'rejected surfaces fall back to text; surfaces without a message get a synthetic one',
    () {
      final state = KletsoConversationState('conv_1');
      KletsoEventEnvelope env(
        int seq,
        String type,
        Map<String, Object?> data, {
        String turn = 'trn_1',
      }) => KletsoEventEnvelope(
        id: 'evt_$seq',
        seq: seq,
        type: type,
        ts: DateTime.utc(2026),
        conversationId: 'conv_1',
        turnId: turn,
        data: data,
      );
      expect(
        state.apply(
          env(1, 'ui.render', {'surface': KletsoFixtures.invalidCycle}),
        ),
        isTrue,
      );
      expect(state.messages.single.text, 'A surface that references itself.');
      expect(state.apply(env(2, 'ui.render', {'surface': 'garbage'})), isFalse);
      expect(
        state.apply(
          env(3, 'ui.render', {'surface': KletsoFixtures.chart}, turn: 'trn_2'),
        ),
        isTrue,
      );
      expect(state.messages.last.id, 'surface_sfc_01J8CHART00001');
      expect(state.messages.last.isAssistant, isTrue);
      // a later render in the same turn attaches to that synthetic message
      expect(
        state.apply(
          env(4, 'ui.render', {
            'surface': KletsoFixtures.quickReplies,
          }, turn: 'trn_2'),
        ),
        isTrue,
      );
      expect(state.messages.last.surfaces, hasLength(2));
      // an error in a turn marks its assistant message failed
      expect(
        state.apply(
          env(5, 'error', {
            'code': 'provider_error',
            'message': 'x',
            'retryable': true,
          }, turn: 'trn_2'),
        ),
        isTrue,
      );
      expect(state.messages.last.status, KletsoMessageStatus.failed);
      expect(
        state.apply(
          env(6, 'error', {
            'code': 'x',
            'message': 'x',
            'retryable': false,
          }, turn: 'trn_9'),
        ),
        isFalse,
      );
      // tool events with no assistant message ever created stay buffered per turn
      expect(
        state.apply(
          env(7, 'tool.started', {
            'toolCallId': 'call_1',
            'name': 't',
          }, turn: 'trn_3'),
        ),
        isFalse,
      );
      expect(
        state.apply(
          env(8, 'tool.completed', {
            'toolCallId': 'call_1',
            'name': 't',
            'durationMs': 1,
          }, turn: 'trn_3'),
        ),
        isFalse,
      );
      expect(
        state.apply(
          env(9, 'tool.failed', {
            'toolCallId': 'call_9',
            'name': 'u',
            'durationMs': 1,
            'error': {'code': 'e', 'message': 'boom'},
          }, turn: 'trn_3'),
        ),
        isFalse,
      );
      expect(
        state.apply(
          env(10, 'message.created', {
            'messageId': 'msg_3',
            'role': 'assistant',
            'text': '',
          }, turn: 'trn_3'),
        ),
        isTrue,
      );
      expect(state.messages.last.toolCalls.map((c) => c.status), [
        KletsoToolCallStatus.completed,
        KletsoToolCallStatus.failed,
      ]);
      expect(state.messages.last.toolCalls.last.error, 'boom');
      // unknown message ids are ignored
      expect(
        state.apply(
          env(11, 'message.delta', {'messageId': 'msg_404', 'text': 'x'}),
        ),
        isFalse,
      );
      expect(state.apply(env(12, 'agent.typing', {})), isFalse);
      expect(state.messages.last.toString(), contains('msg_3'));
    },
  );
}
