import 'errors.dart';

/// A JSON object as decoded by `dart:convert`.
typedef JsonMap = Map<String, Object?>;

/// Reads [json] as a [JsonMap] or throws a [KletsoSchemaException].
JsonMap requireMap(Object? json, String path) {
  if (json is JsonMap) return json;
  if (json is Map) return json.cast<String, Object?>();
  throw KletsoSchemaException('expected an object', path: path);
}

/// Reads a required string field.
String requireString(JsonMap map, String key, String path) {
  final value = map[key];
  if (value is String) return value;
  throw KletsoSchemaException(
    value == null ? 'missing "$key"' : '"$key" must be a string',
    path: '$path/$key',
  );
}

/// Reads an optional string field; non-strings are treated as absent.
String? optionalString(JsonMap map, String key) {
  final value = map[key];
  return value is String ? value : null;
}

/// Reads a required integer field (accepts whole doubles).
int requireInt(JsonMap map, String key, String path) {
  final value = map[key];
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  throw KletsoSchemaException(
    value == null ? 'missing "$key"' : '"$key" must be an integer',
    path: '$path/$key',
  );
}

/// Reads an optional integer field; anything else is treated as absent.
int? optionalInt(JsonMap map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}

/// Reads an optional boolean field.
bool? optionalBool(JsonMap map, String key) {
  final value = map[key];
  return value is bool ? value : null;
}

/// Reads an optional object field; non-objects are treated as absent.
JsonMap? optionalMap(JsonMap map, String key) {
  final value = map[key];
  if (value is JsonMap) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

/// Reads an optional list field; non-lists are treated as absent.
List<Object?>? optionalList(JsonMap map, String key) {
  final value = map[key];
  return value is List ? value : null;
}

/// Deep structural equality for decoded JSON values.
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!jsonEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

/// Returns a deep, unmodifiable copy of a decoded JSON value.
Object? freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final e in value.entries) e.key as String: freezeJson(e.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(freezeJson));
  }
  return value;
}

/// Returns a deep, unmodifiable copy of a JSON object.
JsonMap freezeMap(Map<Object?, Object?>? value) =>
    value == null ? const <String, Object?>{} : freezeJson(value)! as JsonMap;
