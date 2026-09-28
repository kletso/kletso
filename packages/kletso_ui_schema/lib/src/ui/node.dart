import 'package:meta/meta.dart';

import '../errors.dart';
import '../json_utils.dart';
import 'action.dart';
import 'binding.dart';

/// One component in a surface: a type, a bag of props and its actions.
///
/// Props are kept as decoded JSON. The typed getters never throw and return
/// the supplied default when the prop is absent, has the wrong type or is an
/// unresolved binding. Use [KletsoSurface.resolveNode] to substitute bindings
/// with values from the surface data first.
@immutable
final class KletsoNode {
  /// Creates a node.
  KletsoNode({
    required this.id,
    required this.type,
    JsonMap props = const <String, Object?>{},
    List<KletsoAction> actions = const <KletsoAction>[],
  }) : props = freezeMap(props),
       actions = List<KletsoAction>.unmodifiable(actions);

  /// Parses a node with the given [id] from its wire form.
  factory KletsoNode.fromJson(String id, Object? json, {String path = r'$'}) {
    final map = requireMap(json, path);
    final type = requireString(map, 'type', path);
    final rawActions = optionalList(map, 'actions') ?? const <Object?>[];
    final actions = <KletsoAction>[];
    for (var i = 0; i < rawActions.length; i++) {
      actions.add(
        KletsoAction.fromJson(rawActions[i], path: '$path/actions/$i'),
      );
    }
    final rawProps = map['props'];
    if (rawProps != null && rawProps is! Map) {
      throw KletsoSchemaException('"props" must be an object', path: path);
    }
    return KletsoNode(
      id: id,
      type: type,
      props: rawProps == null
          ? const <String, Object?>{}
          : (rawProps as Map).cast<String, Object?>(),
      actions: actions,
    );
  }

  /// The component id (key in the surface's `components` map).
  final String id;

  /// Component type; built-in name or namespaced custom type.
  final String type;

  /// Decoded props, unmodifiable.
  final JsonMap props;

  /// Actions in declaration order, unmodifiable.
  final List<KletsoAction> actions;

  /// The raw value of [key] or `null`.
  Object? prop(String key) => props[key];

  /// Returns `true` when [key] is present.
  bool has(String key) => props.containsKey(key);

  /// The binding at [key], or `null` when the prop is a literal or absent.
  KletsoBinding? binding(String key) => KletsoBinding.tryParse(props[key]);

  /// String prop or [fallback].
  String string(String key, {String fallback = ''}) {
    final value = props[key];
    return value is String ? value : fallback;
  }

  /// Nullable string prop.
  String? stringOrNull(String key) {
    final value = props[key];
    return value is String ? value : null;
  }

  /// Numeric prop or [fallback].
  num number(String key, {num fallback = 0}) {
    final value = props[key];
    return value is num ? value : fallback;
  }

  /// Nullable numeric prop.
  num? numberOrNull(String key) {
    final value = props[key];
    return value is num ? value : null;
  }

  /// Boolean prop or [fallback].
  bool boolean(String key, {bool fallback = false}) {
    final value = props[key];
    return value is bool ? value : fallback;
  }

  /// List prop or an empty list.
  List<Object?> list(String key) {
    final value = props[key];
    return value is List ? value : const <Object?>[];
  }

  /// List prop filtered to objects, for `items`, `fields`, `series`, `rows`.
  List<JsonMap> mapList(String key) => list(
    key,
  ).whereType<Map<Object?, Object?>>().map(freezeMap).toList(growable: false);

  /// Object prop or an empty map.
  JsonMap map(String key) {
    final value = props[key];
    if (value is JsonMap) return value;
    if (value is Map) return value.cast<String, Object?>();
    return const <String, Object?>{};
  }

  /// The child ids listed under [key] (`children` by default).
  List<String> childIds([String key = 'children']) =>
      list(key).whereType<String>().toList(growable: false);

  /// Every child id this node references: `props.children` plus the
  /// `children` list of each entry in `props.items` (tabs, accordion).
  /// Validators and renderers walk the tree with this.
  List<String> get allChildIds {
    final out = <String>[...childIds()];
    for (final item in mapList('items')) {
      final children = item['children'];
      if (children is List) out.addAll(children.whereType<String>());
    }
    return out;
  }

  /// The action with [actionId] or `null`.
  KletsoAction? action(String actionId) {
    for (final a in actions) {
      if (a.id == actionId) return a;
    }
    return null;
  }

  /// Returns a copy with [props] replaced.
  KletsoNode withProps(JsonMap props) =>
      KletsoNode(id: id, type: type, props: props, actions: actions);

  /// Wire form (without the id, which is the map key).
  JsonMap toJson() => <String, Object?>{
    'type': type,
    if (props.isNotEmpty) 'props': props,
    if (actions.isNotEmpty)
      'actions': actions.map((a) => a.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is KletsoNode &&
      other.id == id &&
      jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(id, type, props.length, actions.length);

  @override
  String toString() => 'KletsoNode($id: $type)';
}
