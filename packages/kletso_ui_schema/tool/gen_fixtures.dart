// Writes the generated fixtures: the 20-message conversation log and the
// invalid surfaces that break a size limit. Run after changing the script or
// any valid UI fixture it embeds, then `dart run tool/embed.dart`.
//
// Usage: dart run tool/gen_fixtures.dart
import 'dart:convert';
import 'dart:io';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';

void main() {
  final root = Directory.current.path;
  File(
    '$root/fixtures/events/conversation_20.json',
  ).writeAsStringSync('${KletsoConversationScript().toJsonString()}\n');
  const encoder = JsonEncoder.withIndent('  ');
  for (final entry in KletsoFixtureGenerators.all().entries) {
    File(
      '$root/fixtures/ui/invalid/${entry.key}',
    ).writeAsStringSync('${encoder.convert(entry.value)}\n');
  }
  stdout.writeln(
    'wrote conversation_20.json and ${KletsoFixtureGenerators.all().length} invalid fixtures',
  );
}
