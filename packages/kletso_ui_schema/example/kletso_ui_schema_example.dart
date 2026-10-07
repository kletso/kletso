// Parse and validate a `kletso.ui/v1` surface, the JSON document a Kletso
// agent emits when it renders UI. Run with `dart run example/kletso_ui_schema_example.dart`.
import 'dart:io';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';

void main() {
  final json = <String, Object?>{
    'schema': 'kletso.ui/v1',
    'surfaceId': 'sfc_q2a7',
    'root': 'col',
    'fallbackText': 'Your ideal outing comes with…',
    'components': {
      'col': {
        'type': 'column',
        'props': {
          'children': ['q'],
        },
      },
      'q': {
        'type': 'ds.passportQuestion',
        'props': {
          'id': 'Q2',
          'step': 2,
          'total': 5,
          'text': 'Your ideal outing comes with…',
          'options': [
            {'label': 'Just me', 'emoji': '🧍'},
            {'label': 'My usual crew', 'emoji': '👯'},
          ],
        },
      },
    },
  };

  final surface = KletsoSurface.fromJson(json);
  stdout.writeln(
    'surface ${surface.surfaceId}: root=${surface.root}, '
    '${surface.components.length} components',
  );
  for (final entry in surface.components.entries) {
    stdout.writeln('  ${entry.key} → ${entry.value.type}');
  }

  // Structural problems surface as a typed exception with a JSON path.
  try {
    KletsoSurface.fromJson(<String, Object?>{...json, 'root': 'missing'});
  } on KletsoSchemaException catch (e) {
    stdout.writeln('rejected: $e');
  }
}
