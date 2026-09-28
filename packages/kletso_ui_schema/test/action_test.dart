import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:test/test.dart';

void main() {
  const cases = <Map<String, Object?>>[
    {
      'id': 'view',
      'kind': 'local',
      'name': 'open_hotel',
      'args': {'id': 'h_1'},
    },
    {
      'id': 'book',
      'kind': 'agent',
      'value': {'intent': 'book'},
      'label': 'Book',
    },
    {
      'id': 'run',
      'kind': 'workflow',
      'workflowId': 'wf_1',
      'input': {'a': 1},
    },
    {'id': 'open', 'kind': 'url', 'url': 'https://acme.com/h/1'},
    {'id': 'ok', 'kind': 'submit', 'formId': 'f1'},
    {'id': 'yes', 'kind': 'confirm', 'toolCallId': 'call_1', 'approve': true},
  ];
  const types = <Type>[
    KletsoLocalAction,
    KletsoAgentAction,
    KletsoWorkflowAction,
    KletsoUrlAction,
    KletsoSubmitAction,
    KletsoConfirmAction,
  ];

  for (var i = 0; i < cases.length; i++) {
    test('${cases[i]['kind']} round-trips', () {
      final a = KletsoAction.fromJson(cases[i]);
      expect(a.runtimeType, types[i]);
      expect(a.kind, cases[i]['kind']);
      expect(jsonEquals(a.toJson(), cases[i]), isTrue, reason: '${a.toJson()}');
      expect(KletsoAction.fromJson(a.toJson()), a);
      expect(a.isLocal, a is KletsoLocalAction);
      expect(a.toString(), contains(a.kind));
    });
  }

  test('minimal forms omit empty optional fields', () {
    expect(const KletsoLocalAction(id: 'a', name: 'n').toJson(), {
      'id': 'a',
      'kind': 'local',
      'name': 'n',
    });
    expect(const KletsoWorkflowAction(id: 'a', workflowId: 'w').toJson(), {
      'id': 'a',
      'kind': 'workflow',
      'workflowId': 'w',
    });
    expect(const KletsoAgentAction(id: 'a', value: null).toJson(), {
      'id': 'a',
      'kind': 'agent',
      'value': null,
    });
  });

  test('unknown kinds are preserved verbatim', () {
    const raw = {'id': 'x', 'kind': 'teleport', 'to': 'mars', 'label': 'Go'};
    final a = KletsoAction.fromJson(raw);
    expect(a, isA<KletsoUnknownAction>());
    expect(a.kind, 'teleport');
    expect(a.label, 'Go');
    expect(a.toJson(), raw);
  });

  test('missing required fields throw with the path', () {
    expect(
      () => KletsoAction.fromJson({'id': 'x', 'kind': 'local'}, path: 'p'),
      throwsA(
        isA<KletsoSchemaException>().having((e) => e.path, 'path', 'p/name'),
      ),
    );
    expect(
      () => KletsoAction.fromJson({'id': 'x', 'kind': 'agent'}),
      throwsA(isA<KletsoSchemaException>()),
    );
    expect(
      () => KletsoAction.fromJson({
        'id': 'x',
        'kind': 'confirm',
        'toolCallId': 'c',
      }),
      throwsA(isA<KletsoSchemaException>()),
    );
    expect(
      () => KletsoAction.fromJson({'kind': 'ping'}),
      throwsA(isA<KletsoSchemaException>()),
    );
    expect(
      () => KletsoAction.fromJson('nope'),
      throwsA(isA<KletsoSchemaException>()),
    );
  });

  test('url action exposes a parsed uri', () {
    expect(
      const KletsoUrlAction(id: 'a', url: 'https://acme.com/x').uri!.host,
      'acme.com',
    );
    expect(const KletsoUrlAction(id: 'a', url: '::').uri, isNull);
  });

  test('equality is structural', () {
    expect(
      const KletsoSubmitAction(id: 'a', formId: 'f'),
      const KletsoSubmitAction(id: 'a', formId: 'f'),
    );
    expect(
      const KletsoSubmitAction(id: 'a', formId: 'f').hashCode,
      const KletsoSubmitAction(id: 'a', formId: 'f').hashCode,
    );
    expect(
      const KletsoSubmitAction(id: 'a', formId: 'f'),
      isNot(equals(const KletsoSubmitAction(id: 'a', formId: 'g'))),
    );
  });
}
