import 'dart:convert';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:test/test.dart';

void main() {
  group('valid fixtures', () {
    for (final path in KletsoFixtures.validSurfaces) {
      test('$path round-trips and validates', () {
        final json = KletsoFixtures.json(path);
        final surface = KletsoSurface.fromJson(json);
        expect(jsonEquals(surface.toJson(), json), isTrue, reason: 'toJson');
        expect(KletsoSurface.fromJson(surface.toJson()), equals(surface));
        final issues = surface.validate(knownTypes: {'acme.productCard'});
        expect(issues, isEmpty, reason: issues.join('\n'));
        final result = KletsoSurface.parse(
          KletsoFixtures.all[path]!,
          knownTypes: {'acme.productCard'},
        );
        expect(result, isA<KletsoSurfaceOk>());
      });
    }

    test('every built-in type appears in at least one valid fixture', () {
      final seen = <String>{};
      for (final path in KletsoFixtures.validSurfaces) {
        final s = KletsoSurface.fromJson(KletsoFixtures.json(path));
        seen.addAll(s.components.values.map((n) => n.type));
      }
      expect(seen, containsAll(KletsoBuiltinTypes.all));
    });

    test('fixture list covers the kickoff contract', () {
      expect(
        KletsoFixtures.validSurfaces,
        containsAll(<String>[
          'ui/valid/flight_card.json',
          'ui/valid/hotel_card.json',
          'ui/valid/product_cards.json',
          'ui/valid/chart.json',
          'ui/valid/form.json',
          'ui/valid/confirm.json',
        ]),
      );
    });
  });

  group('invalid fixtures (manifest)', () {
    final manifest =
        KletsoFixtures.json('ui/invalid/manifest.json') as Map<String, Object?>;
    final cases = (manifest['cases']! as List).cast<Map<String, Object?>>();

    test('manifest lists every file in fixtures/ui/invalid', () {
      final listed = cases.map((c) => 'ui/invalid/${c['file']}').toSet();
      for (final path in KletsoFixtures.invalidSurfaces) {
        expect(listed, contains(path));
      }
      for (final path in KletsoFixtures.notEmbedded) {
        expect(listed, contains(path));
      }
    });

    for (final c in cases) {
      final file = c['file']! as String;
      final expectCode = KletsoUiIssueCode.values.byName(c['code']! as String);
      final rejected = c['expect'] == 'rejected';
      test('$file → ${c['expect']} (${c['code']})', () {
        final path = 'ui/invalid/$file';
        final text = KletsoFixtures.all[path] ?? jsonEncode(_generated(file));
        final result = KletsoSurface.parse(text);
        expect(result.issues.map((i) => i.code), contains(expectCode));
        if (rejected) {
          expect(result, isA<KletsoSurfaceRejected>());
          expect(expectCode.fatal, isTrue);
        } else {
          expect(result, isA<KletsoSurfaceOk>());
          expect(expectCode.fatal, isFalse);
        }
      });
    }

    test('generated fixtures on disk equal the generators', () {
      // The embedded copies are canonical JSON of the files written by
      // tool/gen_fixtures.dart; the generators must still produce them.
      for (final entry in KletsoFixtureGenerators.all().entries) {
        final embedded = KletsoFixtures.all['ui/invalid/${entry.key}'];
        if (embedded == null) continue; // oversize is not embedded
        expect(jsonEquals(jsonDecode(embedded), entry.value), isTrue);
      }
    });

    test('rejected results keep the fallback text when it is readable', () {
      final r = KletsoSurface.parse(KletsoFixtures.invalidCycleText);
      expect(r, isA<KletsoSurfaceRejected>());
      expect(r.fallbackText, 'A surface that references itself.');
      final r2 = KletsoSurface.parse(KletsoFixtures.invalidWrongSchemaText);
      expect(r2.fallbackText, 'A v2 surface sent to a v1 client.');
    });

    test('non-JSON text is rejected without throwing', () {
      final r = KletsoSurface.parse('{not json');
      expect(r, isA<KletsoSurfaceRejected>());
      expect(r.issues.single.code, KletsoUiIssueCode.invalidSchema);
    });
  });

  group('limits', () {
    test('oversize is decided on bytes before decoding', () {
      final text = jsonEncode(KletsoFixtureGenerators.oversize());
      expect(utf8.encode(text).length, greaterThan(256 * 1024));
      final r = KletsoSurface.parse(text);
      expect(r.issues.single.code, KletsoUiIssueCode.oversize);
      // parseJson skips the byte check by design (caller already checked).
      expect(KletsoSurface.parseJson(jsonDecode(text)), isA<KletsoSurfaceOk>());
    });

    test('custom limits are honoured', () {
      final r = KletsoSurface.parseJson(
        KletsoFixtureGenerators.depthOverflow(depth: 5),
        limits: const KletsoUiLimits(maxDepth: 4),
      );
      expect(r, isA<KletsoSurfaceRejected>());
      final ok = KletsoSurface.parseJson(
        KletsoFixtureGenerators.depthOverflow(depth: 5),
        limits: const KletsoUiLimits(maxDepth: 5),
      );
      expect(ok, isA<KletsoSurfaceOk>());
    });

    test('exactly 500 components and depth 16 are allowed', () {
      expect(
        KletsoSurface.parseJson(
          KletsoFixtureGenerators.tooManyComponents(count: 500),
        ),
        isA<KletsoSurfaceOk>(),
      );
      expect(
        KletsoSurface.parseJson(
          KletsoFixtureGenerators.depthOverflow(depth: 16),
        ),
        isA<KletsoSurfaceOk>(),
      );
      expect(
        KletsoSurface.parseJson(
          KletsoFixtureGenerators.arrayTooLong(length: 200),
        ),
        isA<KletsoSurfaceOk>(),
      );
      expect(
        KletsoSurface.parseJson(
          KletsoFixtureGenerators.stringTooLong(length: 8192),
        ),
        isA<KletsoSurfaceOk>(),
      );
    });

    test('limits value semantics', () {
      const a = KletsoUiLimits();
      expect(a, KletsoUiLimits.standard);
      expect(a.copyWith(maxDepth: 3).maxDepth, 3);
      expect(a.copyWith(maxDepth: 3), isNot(equals(a)));
      expect(a.hashCode, KletsoUiLimits.standard.hashCode);
    });
  });

  group('structure', () {
    test('fromJson throws KletsoSchemaException with a path', () {
      expect(
        () =>
            KletsoSurface.fromJson(<String, Object?>{'schema': 'kletso.ui/v1'}),
        throwsA(
          isA<KletsoSchemaException>().having(
            (e) => e.path,
            'path',
            r'$/components',
          ),
        ),
      );
      expect(
        () => KletsoSurface.fromJson(<String, Object?>{
          'schema': 'kletso.ui/v1',
          'surfaceId': 's',
          'root': 'a',
          'components': <String, Object?>{'a': 'not an object'},
          'fallbackText': 'x',
        }),
        throwsA(
          isA<KletsoSchemaException>().having(
            (e) => e.toString(),
            'toString',
            contains(r'$/components/a'),
          ),
        ),
      );
    });

    test('unreachable components are reported but not fatal', () {
      final s = KletsoSurface.fromJson(<String, Object?>{
        'schema': 'kletso.ui/v1',
        'surfaceId': 's',
        'root': 'a',
        'components': <String, Object?>{
          'a': <String, Object?>{'type': 'divider'},
          'b': <String, Object?>{'type': 'divider'},
        },
        'fallbackText': 'x',
      });
      final issues = s.validate();
      expect(issues.single.code, KletsoUiIssueCode.unreachableComponent);
      expect(issues.single.componentId, 'b');
      expect(s.reachableIds, ['a']);
    });

    test('tab and accordion item children count as reachable', () {
      final trip = KletsoSurface.fromJson(KletsoFixtures.tripPlan);
      expect(
        trip.reachableIds,
        containsAll(['steps', 'faq', 'checkin', 'rate', 'rateBtn']),
      );
      expect(trip.node('tabs')!.allChildIds, [
        'steps',
        'faq',
        'rate',
        'rateBtn',
      ]);
      expect(trip.node('faq')!.allChildIds, ['checkin']);
      expect(trip.node('card')!.allChildIds, ['progress', 'tabs']);
    });

    test('reachableIds is depth-first and cuts cycles', () {
      final s = KletsoSurface.fromJson(KletsoFixtures.invalidCycle);
      expect(s.reachableIds, ['a', 'b', 'c']);
      final flight = KletsoSurface.fromJson(KletsoFixtures.flightCard);
      expect(flight.reachableIds.first, 'card');
      expect(flight.reachableIds.length, flight.components.length);
    });

    test('copyWith and equality', () {
      final s = KletsoSurface.fromJson(KletsoFixtures.hotelCard);
      expect(s.copyWith(), s);
      expect(s.copyWith(fallbackText: 'other'), isNot(equals(s)));
      expect(s.toString(), contains('sfc_01J8HOTEL00001'));
    });
  });

  group('patch', () {
    test(
      'deep-merges data, replaces and removes components, keeps the original',
      () {
        final trip = KletsoSurface.fromJson(KletsoFixtures.tripPlan);
        final patched = trip.patched(
          data: {
            'plan': {'progress': 1.0},
          },
          components: {
            'rate': {
              'type': 'text',
              'props': {'text': 'replaced'},
            },
            'rateBtn': null,
          },
        );
        expect(patched.data, {
          'plan': {'progress': 1.0, 'detail': '2 of 4 steps done'},
        });
        expect(patched.node('rate')!.type, 'text');
        expect(patched.node('rateBtn'), isNull);
        expect(trip.node('rateBtn'), isNotNull, reason: 'immutable');
        expect(trip.data['plan'], {
          'progress': 0.5,
          'detail': '2 of 4 steps done',
        });
        expect(
          patched.resolveNode(patched.node('progress')!).number('value'),
          1.0,
        );
        expect(patched.surfaceId, trip.surfaceId);
        expect(trip.patched(), trip);
        expect(
          () => trip.patched(components: {'x': 'not a node'}),
          throwsA(isA<KletsoSchemaException>()),
        );
      },
    );

    test('ui.patch envelope payload', () {
      final e = KletsoEventEnvelope.fromJson({
        'id': 'evt_p',
        'seq': 3,
        'type': 'ui.patch',
        'ts': '2026-09-28T12:00:00Z',
        'conversationId': 'conv_1',
        'data': {
          'surfaceId': 'sfc_1',
          'data': {'a': 1},
          'components': {'n': null},
        },
      });
      final p = e.payload as KletsoUiPatch;
      expect(p.surfaceId, 'sfc_1');
      expect(p.data, {'a': 1});
      expect(p.components, {'n': null});
    });
  });

  group('host bindings', () {
    test(
      'host paths ask the resolver first, data is the default, other paths fall back',
      () {
        final s = KletsoSurface.fromJson({
          'schema': 'kletso.ui/v1',
          'surfaceId': 's',
          'root': 'p',
          'components': {
            'p': {
              'type': 'progress',
              'props': {
                'value': {'path': '/host/cart/progress'},
                'label': {'path': '/labels/cart'},
                'detail': {'path': '/host/cart/label'},
              },
            },
          },
          'data': {
            'host': {
              'cart': {'progress': 0.1},
            },
            'labels': {'cart': 'Cart'},
          },
          'fallbackText': 'x',
        });
        Object? host(KletsoBinding b) => switch (b.path) {
          '/host/cart/progress' => 0.9,
          _ => null,
        };
        final withHost = s.resolveNode(s.node('p')!, external: host);
        expect(
          withHost.number('value'),
          0.9,
          reason: 'host wins over the surface default',
        );
        expect(withHost.string('label'), 'Cart');
        expect(withHost.has('detail'), isFalse, reason: 'unknown to both');
        final withoutHost = s.resolveNode(s.node('p')!);
        expect(
          withoutHost.number('value'),
          0.1,
          reason: 'surface default when no host',
        );
        Object? any(KletsoBinding b) => 'fallback';
        expect(
          s.resolveNode(s.node('p')!, external: any).string('detail'),
          'fallback',
        );
      },
    );
  });

  group('bindings', () {
    final flight = KletsoSurface.fromJson(KletsoFixtures.flightCard);

    test('resolveNode substitutes bound props', () {
      final raw = flight.node('price')!;
      expect(raw.binding('text'), const KletsoBinding('/flight/priceLabel'));
      expect(raw.string('text'), '');
      final resolved = flight.resolveNode(raw);
      expect(resolved.string('text'), '¥14,800');
      expect(resolved.string('style'), 'title');
      expect(
        identical(
          flight.resolveNode(flight.node('arrow')!),
          flight.node('arrow'),
        ),
        isTrue,
      );
    });

    test('unresolved bindings are dropped and reported', () {
      final s = flight.copyWith(data: const <String, Object?>{});
      final node = s.resolveNode(s.node('price')!);
      expect(node.has('text'), isFalse);
      final issues = s.validate();
      expect(
        issues.where((i) => i.code == KletsoUiIssueCode.unresolvedBinding),
        hasLength(7),
      );
      expect(issues.every((i) => !i.fatal), isTrue);
    });

    test('RFC 6901 pointer semantics', () {
      final data = <String, Object?>{
        'a': <String, Object?>{'b/c': 1, 'd~e': 2},
        'list': <Object?>[10, 20],
        '': 'empty key',
      };
      expect(const KletsoBinding('/a/b~1c').resolve(data), 1);
      expect(const KletsoBinding('/a/d~0e').resolve(data), 2);
      expect(const KletsoBinding('/list/1').resolve(data), 20);
      expect(const KletsoBinding('/list/2').resolve(data), isNull);
      expect(const KletsoBinding('/list/x').resolve(data), isNull);
      expect(const KletsoBinding('/').resolve(data), 'empty key');
      expect(const KletsoBinding('').resolve(data), same(data));
      expect(const KletsoBinding('/nope/deeper').resolve(data), isNull);
      expect(const KletsoBinding('/a/b~1c').tokens, ['a', 'b/c']);
      expect(KletsoBinding.isValidPointer('a/b'), isFalse);
      expect(KletsoBinding.isValidPointer('/a~'), isFalse);
      expect(KletsoBinding.isValidPointer('/a~2'), isFalse);
      expect(
        KletsoBinding.isBinding(<String, Object?>{'path': '/x', 'y': 1}),
        isFalse,
      );
      expect(KletsoBinding.tryParse('nope'), isNull);
      expect(const KletsoBinding('/x').toJson(), {'path': '/x'});
      expect(const KletsoBinding('/x'), const KletsoBinding('/x'));
      expect(const KletsoBinding('/x').toString(), 'KletsoBinding(/x)');
    });
  });

  group('node typed getters', () {
    test('never throw and use defaults', () {
      final n = KletsoNode(
        id: 'n',
        type: 'x',
        props: <String, Object?>{
          's': 'str',
          'n': 3,
          'b': true,
          'l': <Object?>[
            'a',
            1,
            <String, Object?>{'k': 'v'},
          ],
          'm': <String, Object?>{'k': 'v'},
          'wrong': 42,
        },
      );
      expect(n.string('s'), 'str');
      expect(n.string('wrong', fallback: 'd'), 'd');
      expect(n.stringOrNull('wrong'), isNull);
      expect(n.number('n'), 3);
      expect(n.number('s', fallback: 9), 9);
      expect(n.numberOrNull('s'), isNull);
      expect(n.boolean('b'), isTrue);
      expect(n.boolean('s', fallback: true), isTrue);
      expect(n.list('l'), hasLength(3));
      expect(n.list('missing'), isEmpty);
      expect(n.mapList('l'), [
        {'k': 'v'},
      ]);
      expect(n.map('m'), {'k': 'v'});
      expect(n.map('s'), isEmpty);
      expect(n.childIds('l'), ['a']);
      expect(n.childIds(), isEmpty);
      expect(n.prop('n'), 3);
      expect(n.has('zzz'), isFalse);
      expect(n.action('none'), isNull);
      expect(() => n.props['new'] = 1, throwsUnsupportedError);
      expect(n.toString(), 'KletsoNode(n: x)');
    });

    test('actions are looked up by id and preserved in toJson', () {
      final b = KletsoSurface.fromJson(KletsoFixtures.hotelCard).node('b1')!;
      expect(b.action('view'), isA<KletsoLocalAction>());
      expect(b.toJson()['actions'], hasLength(1));
      expect(KletsoNode.fromJson('b1', b.toJson()), b);
    });

    test('fromJson rejects non-object props', () {
      expect(
        () => KletsoNode.fromJson('x', <String, Object?>{
          'type': 't',
          'props': 1,
        }),
        throwsA(isA<KletsoSchemaException>()),
      );
      expect(
        () => KletsoNode.fromJson('x', <String, Object?>{'props': {}}),
        throwsA(isA<KletsoSchemaException>()),
      );
    });
  });
}

Map<String, Object?> _generated(String file) =>
    KletsoFixtureGenerators.all()[file]!;
