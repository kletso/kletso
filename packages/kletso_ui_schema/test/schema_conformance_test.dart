import 'package:json_schema/json_schema.dart';
import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:test/test.dart';

/// Validates the fixtures against the JSON Schemas with an independent
/// validator, so the Dart models and the schemas cannot drift apart.
void main() {
  final refProvider = RefProvider.sync((String ref) {
    final stem = ref.split('/').last.replaceAll('.json', '');
    return KletsoSchemas.all.containsKey(stem)
        ? KletsoSchemas.json(stem)
        : null;
  });
  JsonSchema load(String stem) => JsonSchema.create(
    KletsoSchemas.json(stem),
    schemaVersion: SchemaVersion.draft2020_12,
    refProvider: refProvider,
  );
  final ui = load('kletso.ui.v1');
  final events = load('kletso.events.v1');
  final realtime = load('kletso.realtime.v1');

  group('kletso.ui/v1 schema', () {
    for (final path in KletsoFixtures.validSurfaces) {
      test('$path is valid', () {
        final r = ui.validate(KletsoFixtures.json(path));
        expect(r.isValid, isTrue, reason: r.errors.join('\n'));
      });
    }

    test('structurally broken fixtures fail the schema', () {
      for (final path in <String>[
        'ui/invalid/wrong_schema.json',
        'ui/invalid/missing_fallback.json',
        'ui/invalid/not_an_object.json',
        'ui/invalid/button_without_action.json',
        'ui/invalid/too_many_components.json',
        'ui/invalid/array_too_long.json',
        'ui/invalid/string_too_long.json',
      ]) {
        expect(
          ui.validate(KletsoFixtures.json(path)).isValid,
          isFalse,
          reason: path,
        );
      }
    });

    test('graph problems are beyond JSON Schema and pass it', () {
      // The schema cannot express cycles, depth or dangling ids; the Dart
      // validator (and the Worker) must catch these.
      for (final path in <String>[
        'ui/invalid/cycle.json',
        'ui/invalid/missing_root.json',
        'ui/invalid/dangling_child.json',
        'ui/invalid/depth_overflow.json',
        'ui/invalid/unknown_type.json',
      ]) {
        expect(
          ui.validate(KletsoFixtures.json(path)).isValid,
          isTrue,
          reason: path,
        );
      }
    });

    test('rejects http image sources and bad action shapes', () {
      final bad = KletsoSurface.fromJson(KletsoFixtures.hotelCard).toJson();
      final components = Map<String, Object?>.of(
        bad['components']! as Map<String, Object?>,
      );
      components['img1'] = {
        'type': 'image',
        'props': {'src': 'http://insecure.example/x.jpg', 'alt': 'x'},
      };
      bad['components'] = components;
      expect(ui.validate(bad).isValid, isFalse);

      final badAction = KletsoSurface.fromJson(
        KletsoFixtures.hotelCard,
      ).toJson();
      final c2 = Map<String, Object?>.of(
        badAction['components']! as Map<String, Object?>,
      );
      c2['b1'] = {
        'type': 'button',
        'props': {'label': 'x'},
        'actions': [
          {'id': 'a', 'kind': 'local'},
        ],
      };
      badAction['components'] = c2;
      expect(ui.validate(badAction).isValid, isFalse);
    });
  });

  group('kletso.events/v1 schema', () {
    test('conversation_20 events are valid', () {
      final log = KletsoFixtures.eventsConversation20! as List;
      for (final e in log) {
        final r = events.validate(e);
        expect(
          r.isValid,
          isTrue,
          reason: '${(e as Map)['seq']}: ${r.errors.join('\n')}',
        );
      }
    });

    test('app.notify data is validated', () {
      Map<String, Object?> env(Map<String, Object?> data) => <String, Object?>{
        'id': 'evt_1',
        'seq': 1,
        'type': 'app.notify',
        'ts': '2026-09-28T12:00:00Z',
        'conversationId': 'conv_1',
        'data': data,
      };
      final ok = events.validate(
        env(<String, Object?>{
          'notificationId': 'ntf_01',
          'title': 'Near the store',
          'channel': 'banner',
          'openChat': true,
          'ttlSeconds': 8,
          'action': <String, Object?>{
            'id': 'a',
            'kind': 'url',
            'url': 'https://acme.com',
          },
          'surface': KletsoFixtures.quickReplies,
        }),
      );
      expect(ok.isValid, isTrue, reason: ok.errors.join('\n'));
      expect(
        events.validate(env(<String, Object?>{'title': 'no id'})).isValid,
        isFalse,
      );
      expect(
        events
            .validate(
              env(<String, Object?>{
                'notificationId': 'ntf_1',
                'title': 'x',
                'channel': 'sms',
              }),
            )
            .isValid,
        isFalse,
        reason: 'unknown channel',
      );
    });

    test('bad envelopes fail', () {
      expect(events.validate({'id': 'evt_1'}).isValid, isFalse);
      expect(
        events.validate({
          'id': 'evt_1',
          'seq': 0,
          'type': 'message.delta',
          'ts': '2026-09-28T12:00:00Z',
          'conversationId': 'conv_1',
          'data': {'messageId': 'msg_1', 'text': 'x'},
        }).isValid,
        isFalse,
        reason: 'seq must be >= 1',
      );
      expect(
        events.validate({
          'id': 'evt_1',
          'seq': 1,
          'type': 'message.delta',
          'ts': '2026-09-28T12:00:00Z',
          'conversationId': 'conv_1',
          'data': {'messageId': 'msg_1'},
        }).isValid,
        isFalse,
        reason: 'delta needs text',
      );
    });
  });

  group('realtime schema', () {
    test('client frame fixtures are valid client frames', () {
      final def = realtime.resolvePath(Uri.parse('#/\$defs/clientFrame'));
      for (final f in KletsoFixtures.realtimeClientFrames! as List) {
        final r = def.validate(f);
        expect(r.isValid, isTrue, reason: '$f: ${r.errors.join('\n')}');
        expect(realtime.validate(f).isValid, isTrue);
      }
    });

    test('server frame fixtures are valid server frames', () {
      final def = realtime.resolvePath(Uri.parse('#/\$defs/serverFrame'));
      for (final f in KletsoFixtures.realtimeServerFrames! as List) {
        final r = def.validate(f);
        expect(r.isValid, isTrue, reason: '$f: ${r.errors.join('\n')}');
      }
    });

    test('a frame with an unknown t is not valid', () {
      expect(realtime.validate({'t': 'teleport'}).isValid, isFalse);
      expect(realtime.validate({'t': 'message', 'text': 'x'}).isValid, isFalse);
    });
  });
}
