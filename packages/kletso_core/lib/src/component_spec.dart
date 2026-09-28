import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

/// Declares a custom component type next to the widget that renders it:
/// what the model may put in `props`, how to describe it to the model, and
/// which actions it carries. `dart run kletso_flutter:sync` collects specs
/// into a manifest for the dashboard, so the render_ui tool schema and the
/// Flutter builder never drift apart.
///
/// Declare specs in a file that imports only `package:kletso_core` (no
/// Flutter) so the sync command can run it with plain `dart`.
@immutable
final class KletsoComponentSpec {
  /// Creates a spec. [type] is namespaced (`acme.productCard`); [props] is a
  /// JSON Schema (Draft 2020-12 subset: object/array/string/number/boolean/
  /// enum, no `$ref`).
  const KletsoComponentSpec({
    required this.type,
    required this.description,
    required this.props,
    this.example = const <String, Object?>{},
    this.actions = const <String>[],
    this.version = 1,
  });

  /// Namespaced type name.
  final String type;

  /// One or two sentences telling the model when to use this component.
  final String description;

  /// JSON Schema for `props`.
  final JsonMap props;

  /// Example props shown in the dashboard and used in the model prompt.
  final JsonMap example;

  /// Action ids the widget knows how to fire (`view`, `add`).
  final List<String> actions;

  /// Bump when the schema changes incompatibly.
  final int version;

  /// Wire form for the components manifest.
  JsonMap toJson() => <String, Object?>{
    'type': type,
    'description': description,
    'props': props,
    if (example.isNotEmpty) 'example': example,
    if (actions.isNotEmpty) 'actions': actions,
    'version': version,
  };
}
