import 'dart:convert';

import 'package:meta/meta.dart';

import '../errors.dart';
import '../json_utils.dart';
import 'action.dart';
import 'binding.dart';
import 'catalog.dart';
import 'issue.dart';
import 'limits.dart';
import 'node.dart';

/// A `kletso.ui/v1` surface document: flat components keyed by id, a root,
/// a data model and the plain-text fallback every client can show.
///
/// Construction is liberal (unknown types and props are preserved); use
/// [validate] or [parse] to find out whether a document may be rendered.
@immutable
final class KletsoSurface {
  /// Creates a surface.
  KletsoSurface({
    required this.surfaceId,
    required this.root,
    required Map<String, KletsoNode> components,
    required this.fallbackText,
    JsonMap data = const <String, Object?>{},
  }) : components = Map<String, KletsoNode>.unmodifiable(components),
       data = freezeMap(data);

  /// Parses a surface from decoded JSON. Throws [KletsoSchemaException] on
  /// structural problems (wrong `schema`, missing required fields, a
  /// component that is not an object). Content problems are reported by
  /// [validate], not here.
  factory KletsoSurface.fromJson(Object? json, {String path = r'$'}) {
    final map = requireMap(json, path);
    final schema = requireString(map, 'schema', path);
    if (schema != schemaVersion) {
      throw KletsoSchemaException(
        'unsupported schema "$schema" (expected $schemaVersion)',
        path: '$path/schema',
      );
    }
    final rawComponents = map['components'];
    if (rawComponents is! Map) {
      throw KletsoSchemaException(
        '"components" must be an object',
        path: '$path/components',
      );
    }
    final components = <String, KletsoNode>{};
    for (final entry in rawComponents.entries) {
      final id = entry.key;
      if (id is! String || id.isEmpty) {
        throw KletsoSchemaException(
          'component ids must be non-empty strings',
          path: '$path/components',
        );
      }
      components[id] = KletsoNode.fromJson(
        id,
        entry.value,
        path: '$path/components/$id',
      );
    }
    return KletsoSurface(
      surfaceId: requireString(map, 'surfaceId', path),
      root: requireString(map, 'root', path),
      components: components,
      data: freezeMap(optionalMap(map, 'data')),
      fallbackText: requireString(map, 'fallbackText', path),
    );
  }

  /// The exact schema marker this package implements.
  static const String schemaVersion = 'kletso.ui/v1';

  /// Decodes and validates a raw JSON [text] the way an SDK must: byte limit
  /// before decoding, structure, then content limits.
  ///
  /// Never throws for bad input; a rejected result still carries whatever
  /// `fallbackText` could be recovered so the caller can show it.
  static KletsoSurfaceResult parse(
    String text, {
    KletsoUiLimits limits = KletsoUiLimits.standard,
    Set<String> knownTypes = const <String>{},
  }) {
    final bytes = utf8.encode(text).length;
    if (bytes > limits.maxBytes) {
      return KletsoSurfaceRejected(<KletsoUiIssue>[
        KletsoUiIssue(
          KletsoUiIssueCode.oversize,
          'surface is $bytes bytes, limit ${limits.maxBytes}',
        ),
      ]);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return KletsoSurfaceRejected(<KletsoUiIssue>[
        KletsoUiIssue(
          KletsoUiIssueCode.invalidSchema,
          'not JSON: ${e.message}',
        ),
      ]);
    }
    return parseJson(decoded, limits: limits, knownTypes: knownTypes);
  }

  /// Validates already-decoded JSON. Like [parse] but without the byte check
  /// (the caller is expected to have done it before decoding).
  static KletsoSurfaceResult parseJson(
    Object? json, {
    KletsoUiLimits limits = KletsoUiLimits.standard,
    Set<String> knownTypes = const <String>{},
  }) {
    final KletsoSurface surface;
    try {
      surface = KletsoSurface.fromJson(json);
    } on KletsoSchemaException catch (e) {
      final fallback = json is Map ? json['fallbackText'] : null;
      return KletsoSurfaceRejected(<KletsoUiIssue>[
        KletsoUiIssue(KletsoUiIssueCode.invalidSchema, e.message, path: e.path),
      ], fallbackText: fallback is String ? fallback : null);
    }
    final issues = surface.validate(limits: limits, knownTypes: knownTypes);
    if (issues.any((i) => i.fatal)) {
      return KletsoSurfaceRejected(issues, fallbackText: surface.fallbackText);
    }
    return KletsoSurfaceOk(surface, issues);
  }

  /// Schema marker, always [schemaVersion].
  String get schema => schemaVersion;

  /// Unique id assigned by the runtime; patches and actions reference it.
  final String surfaceId;

  /// Id of the component to render first.
  final String root;

  /// All components, keyed by id. Unmodifiable.
  final Map<String, KletsoNode> components;

  /// The data model bindings point into. Unmodifiable.
  final JsonMap data;

  /// Plain-text rendition shown by clients that cannot render the surface.
  final String fallbackText;

  /// The root node, or `null` when [root] is dangling.
  KletsoNode? get rootNode => components[root];

  /// Looks up a component by id.
  KletsoNode? node(String id) => components[id];

  /// Resolves [binding] against [data].
  Object? resolve(KletsoBinding binding) => binding.resolve(data);

  /// Prefix of binding paths that the host app supplies (`/host/cart/total`).
  /// They are resolved by [KletsoBindingResolver] first and by the surface
  /// `data` (as a default) second.
  static const String hostPathPrefix = '/host/';

  /// Returns [node] with every top-level binding prop replaced by the value
  /// it points at. Paths under [hostPathPrefix] ask [external] first; any
  /// binding that is still unresolved after `data` also asks [external].
  /// Unresolved bindings are removed so typed getters fall back to their
  /// defaults. Non-binding props are untouched.
  KletsoNode resolveNode(KletsoNode node, {KletsoBindingResolver? external}) {
    var changed = false;
    final resolved = <String, Object?>{};
    for (final entry in node.props.entries) {
      final binding = KletsoBinding.tryParse(entry.value);
      if (binding == null) {
        resolved[entry.key] = entry.value;
        continue;
      }
      changed = true;
      final value = resolveBinding(binding, external: external);
      if (value != null) resolved[entry.key] = value;
    }
    return changed ? node.withProps(resolved) : node;
  }

  /// Resolves one binding with the host-first rule described on
  /// [resolveNode].
  Object? resolveBinding(
    KletsoBinding binding, {
    KletsoBindingResolver? external,
  }) {
    if (external != null && binding.path.startsWith(hostPathPrefix)) {
      final fromHost = external(binding);
      if (fromHost != null) return fromHost;
    }
    final fromData = binding.resolve(data);
    if (fromData != null) return fromData;
    return external?.call(binding);
  }

  /// Applies a `ui.patch`: [data] is deep-merged (maps merge, everything else
  /// replaces), [components] replaces nodes by id and removes ids mapped to
  /// `null`. Returns a new surface; this one is unchanged. Structural errors
  /// in a replacement node throw [KletsoSchemaException].
  KletsoSurface patched({JsonMap? data, JsonMap? components}) {
    final mergedData = data == null ? this.data : _deepMerge(this.data, data);
    final nodes = Map<String, KletsoNode>.of(this.components);
    if (components != null) {
      for (final entry in components.entries) {
        if (entry.value == null) {
          nodes.remove(entry.key);
        } else {
          nodes[entry.key] = KletsoNode.fromJson(
            entry.key,
            entry.value,
            path: '\$/components/${entry.key}',
          );
        }
      }
    }
    return KletsoSurface(
      surfaceId: surfaceId,
      root: root,
      components: nodes,
      data: mergedData,
      fallbackText: fallbackText,
    );
  }

  static JsonMap _deepMerge(JsonMap base, JsonMap patch) {
    final out = <String, Object?>{...base};
    for (final e in patch.entries) {
      final existing = out[e.key];
      final incoming = e.value;
      if (existing is Map && incoming is Map) {
        out[e.key] = _deepMerge(
          existing.cast<String, Object?>(),
          incoming.cast<String, Object?>(),
        );
      } else {
        out[e.key] = incoming;
      }
    }
    return out;
  }

  /// Ids reachable from [root] through `children` lists (including tab and
  /// accordion item children), in depth-first
  /// order, each at most once. Cycles are cut silently.
  List<String> get reachableIds {
    final seen = <String>{};
    final order = <String>[];
    void visit(String id) {
      if (!seen.add(id)) return;
      final n = components[id];
      if (n == null) return;
      order.add(id);
      n.allChildIds.forEach(visit);
    }

    visit(root);
    return order;
  }

  /// Checks content rules and limits. Structural rules are enforced by
  /// [fromJson]. The result is empty for a fully conforming surface; fatal
  /// issues mean the surface must not be rendered.
  List<KletsoUiIssue> validate({
    KletsoUiLimits limits = KletsoUiLimits.standard,
    Set<String> knownTypes = const <String>{},
  }) {
    final issues = <KletsoUiIssue>[];
    if (fallbackText.trim().isEmpty) {
      issues.add(
        const KletsoUiIssue(
          KletsoUiIssueCode.missingFallback,
          'fallbackText is required',
          path: r'$/fallbackText',
        ),
      );
    }
    if (components.length > limits.maxComponents) {
      issues.add(
        KletsoUiIssue(
          KletsoUiIssueCode.tooManyComponents,
          '${components.length} components, limit ${limits.maxComponents}',
        ),
      );
    }
    if (!components.containsKey(root)) {
      issues.add(
        KletsoUiIssue(
          KletsoUiIssueCode.missingRoot,
          'root "$root" is not a component',
          path: r'$/root',
        ),
      );
    }
    _walkStrings(toJson(), r'$', limits, issues);

    final visited = <String>{};
    final stack = <String>[];
    var depthReported = false;
    void visit(String id, int depth, String? parent) {
      final n = components[id];
      if (n == null) {
        issues.add(
          KletsoUiIssue(
            KletsoUiIssueCode.danglingChild,
            'child "$id" of "$parent" is not a component',
            componentId: parent,
          ),
        );
        return;
      }
      if (stack.contains(id)) {
        issues.add(
          KletsoUiIssue(
            KletsoUiIssueCode.cycle,
            'component "$id" is its own ancestor via ${stack.join(' > ')}',
            componentId: id,
          ),
        );
        return;
      }
      if (depth > limits.maxDepth) {
        if (!depthReported) {
          depthReported = true;
          issues.add(
            KletsoUiIssue(
              KletsoUiIssueCode.depthExceeded,
              'component "$id" is at depth $depth, limit ${limits.maxDepth}',
              componentId: id,
            ),
          );
        }
        return;
      }
      final firstVisit = visited.add(id);
      if (firstVisit) _checkNode(n, knownTypes, issues);
      stack.add(id);
      for (final child in n.allChildIds) {
        visit(child, depth + 1, id);
      }
      stack.removeLast();
    }

    if (components.containsKey(root)) visit(root, 1, null);
    for (final id in components.keys) {
      if (!visited.contains(id) && !depthReported) {
        issues.add(
          KletsoUiIssue(
            KletsoUiIssueCode.unreachableComponent,
            'component "$id" is not reachable from the root',
            componentId: id,
          ),
        );
      }
    }
    return issues;
  }

  void _checkNode(
    KletsoNode n,
    Set<String> knownTypes,
    List<KletsoUiIssue> issues,
  ) {
    if (!KletsoBuiltinTypes.isBuiltin(n.type) && !knownTypes.contains(n.type)) {
      issues.add(
        KletsoUiIssue(
          KletsoUiIssueCode.unknownComponent,
          'unknown component type "${n.type}"',
          componentId: n.id,
        ),
      );
    }
    if (n.type == KletsoBuiltinTypes.button &&
        n.actions.every((a) => a is KletsoUnknownAction)) {
      issues.add(
        KletsoUiIssue(
          KletsoUiIssueCode.buttonWithoutAction,
          'button "${n.id}" has no usable action',
          componentId: n.id,
        ),
      );
    }
    for (final entry in n.props.entries) {
      final binding = KletsoBinding.tryParse(entry.value);
      if (binding != null && binding.resolve(data) == null) {
        issues.add(
          KletsoUiIssue(
            KletsoUiIssueCode.unresolvedBinding,
            'prop "${entry.key}" binds to "${binding.path}" which is not in data',
            componentId: n.id,
            path: entry.key,
          ),
        );
      }
    }
  }

  static void _walkStrings(
    Object? value,
    String path,
    KletsoUiLimits limits,
    List<KletsoUiIssue> issues,
  ) {
    if (value is String) {
      if (value.length > limits.maxStringLength) {
        issues.add(
          KletsoUiIssue(
            KletsoUiIssueCode.stringTooLong,
            'string of ${value.length} chars, limit ${limits.maxStringLength}',
            path: path,
          ),
        );
      }
    } else if (value is List) {
      if (value.length > limits.maxArrayLength) {
        issues.add(
          KletsoUiIssue(
            KletsoUiIssueCode.arrayTooLong,
            'array of ${value.length} items, limit ${limits.maxArrayLength}',
            path: path,
          ),
        );
      }
      for (var i = 0; i < value.length; i++) {
        _walkStrings(value[i], '$path/$i', limits, issues);
      }
    } else if (value is Map) {
      for (final e in value.entries) {
        _walkStrings(e.value, '$path/${e.key}', limits, issues);
      }
    }
  }

  /// Returns a copy with the given fields replaced.
  KletsoSurface copyWith({
    String? surfaceId,
    String? root,
    Map<String, KletsoNode>? components,
    JsonMap? data,
    String? fallbackText,
  }) => KletsoSurface(
    surfaceId: surfaceId ?? this.surfaceId,
    root: root ?? this.root,
    components: components ?? this.components,
    data: data ?? this.data,
    fallbackText: fallbackText ?? this.fallbackText,
  );

  /// Wire form.
  JsonMap toJson() => <String, Object?>{
    'schema': schema,
    'surfaceId': surfaceId,
    'root': root,
    'components': <String, Object?>{
      for (final e in components.entries) e.key: e.value.toJson(),
    },
    if (data.isNotEmpty) 'data': data,
    'fallbackText': fallbackText,
  };

  /// Compact JSON text of [toJson].
  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is KletsoSurface && jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(surfaceId, root, components.length);

  @override
  String toString() =>
      'KletsoSurface($surfaceId, root: $root, ${components.length} components)';
}

/// Supplies values for bindings the surface data does not hold (host app
/// state such as `/host/cart/total`). Return `null` when unknown.
typedef KletsoBindingResolver = Object? Function(KletsoBinding binding);

/// Outcome of [KletsoSurface.parse].
@immutable
sealed class KletsoSurfaceResult {
  const KletsoSurfaceResult(this.issues);

  /// Every finding, fatal or not.
  final List<KletsoUiIssue> issues;

  /// Text to show when the surface cannot be rendered, if any was recovered.
  String? get fallbackText;
}

/// The surface may be rendered. [issues] may still contain non-fatal findings
/// the renderer degrades around (unknown types, dangling children).
final class KletsoSurfaceOk extends KletsoSurfaceResult {
  /// Creates a successful result.
  const KletsoSurfaceOk(this.surface, super.issues);

  /// The validated surface.
  final KletsoSurface surface;

  @override
  String get fallbackText => surface.fallbackText;
}

/// The surface must not be rendered; show [fallbackText] when present.
final class KletsoSurfaceRejected extends KletsoSurfaceResult {
  /// Creates a rejected result.
  const KletsoSurfaceRejected(super.issues, {this.fallbackText});

  @override
  final String? fallbackText;

  /// The fatal findings.
  List<KletsoUiIssue> get fatalIssues =>
      issues.where((i) => i.fatal).toList(growable: false);
}
