import 'dart:io';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:test/test.dart';

void main() {
  test('embedded.g.dart is up to date with schemas/ and fixtures/', () {
    final result = Process.runSync('dart', [
      'run',
      'tool/embed.dart',
      '--check',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('generated fixtures on disk match the generators', () {
    final result = Process.runSync('dart', ['run', 'tool/gen_fixtures.dart']);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final check = Process.runSync('dart', [
      'run',
      'tool/embed.dart',
      '--check',
    ]);
    expect(check.exitCode, 0, reason: 'fixtures changed: ${check.stderr}');
  });

  test('schemas decode and declare 2020-12', () {
    for (final stem in KletsoSchemas.all.keys) {
      final s = KletsoSchemas.json(stem);
      expect(s[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
      expect(s[r'$id'], 'https://kletso.ai/schemas/$stem.json');
    }
    expect(
      KletsoSchemas.all.keys,
      containsAll(['kletso.ui.v1', 'kletso.events.v1', 'kletso.realtime.v1']),
    );
  });

  test('typed fixture getters decode', () {
    expect(KletsoFixtures.flightCard, isA<Map<String, Object?>>());
    expect(KletsoFixtures.eventsConversation20, isA<List<Object?>>());
    expect(KletsoFixtures.notEmbedded, ['ui/invalid/oversize.json']);
    expect(KletsoFixtures.all.length, greaterThanOrEqualTo(24));
  });
}
