// Writes the components manifest (kletso.components.json) from a Dart file
// that exports `const List<KletsoComponentSpec> kletsoComponents`.
//
// Usage: dart run kletso_flutter:sync [--file lib/kletso_components.dart] [--out kletso.components.json]
//
// The manifest is what the Kletso dashboard imports (Components page →
// "Sync from code"); pushing it directly with a secret key arrives with the
// runtime release.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var file = 'lib/kletso_components.dart';
  var out = 'kletso.components.json';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--file' && i + 1 < args.length) file = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) out = args[++i];
  }
  if (!File(file).existsSync()) {
    stderr.writeln(
      'kletso sync: $file not found. Declare your components there:\n'
      "  import 'package:kletso_flutter/kletso_flutter.dart';\n"
      '  const kletsoComponents = <KletsoComponentSpec>[ … ];',
    );
    exitCode = 2;
    return;
  }
  final source = File(file).readAsStringSync();
  if (source.contains('package:flutter/') ||
      source.contains('package:kletso_flutter/')) {
    stderr.writeln(
      'kletso sync: $file must import only package:kletso_core (no Flutter), '
      'so it can run with plain `dart`. KletsoComponentSpec lives in kletso_core.',
    );
    exitCode = 2;
    return;
  }
  // Generate a runner inside the project so package resolution applies.
  final tmp = Directory('.dart_tool/kletso_sync')..createSync(recursive: true);
  final entry = File('${tmp.path}/main.dart')
    ..writeAsStringSync('''
import 'dart:convert';
import '${File(file).absolute.uri}' as host;
void main() {
  final specs = host.kletsoComponents.map((s) => s.toJson()).toList();
  print(const JsonEncoder.withIndent('  ').convert({
    'schema': 'kletso.components/v1',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'components': specs,
  }));
}
''');
  final result = await Process.run('dart', [
    'run',
    entry.path,
  ], workingDirectory: Directory.current.path);
  tmp.deleteSync(recursive: true);
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exitCode = result.exitCode;
    return;
  }
  File(out).writeAsStringSync('${result.stdout}');
  final manifest = jsonDecode('${result.stdout}') as Map<String, Object?>;
  final count = (manifest['components']! as List).length;
  stdout.writeln(
    'kletso sync: wrote $out ($count components). Import it in the dashboard → Components → Sync from code.',
  );
}
