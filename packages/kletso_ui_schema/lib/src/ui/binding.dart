import 'package:meta/meta.dart';

import '../json_utils.dart';

/// A reference from a component prop into the surface `data` model, written
/// on the wire as `{ "path": "/json/pointer" }` (RFC 6901).
@immutable
final class KletsoBinding {
  /// Creates a binding to [path].
  const KletsoBinding(this.path);

  /// The JSON pointer, e.g. `/hotel/priceLabel`. The empty string is the
  /// whole data object.
  final String path;

  /// Returns `true` when [value] has the wire shape of a binding: an object
  /// whose only key is `path` with a string value.
  static bool isBinding(Object? value) =>
      value is Map &&
      value.length == 1 &&
      value['path'] is String &&
      isValidPointer(value['path'] as String);

  /// Returns `true` when [pointer] is syntactically an RFC 6901 pointer.
  static bool isValidPointer(String pointer) {
    if (pointer.isEmpty) return true;
    if (!pointer.startsWith('/')) return false;
    for (var i = 0; i < pointer.length; i++) {
      if (pointer.codeUnitAt(i) == 0x7E /* ~ */ ) {
        if (i + 1 >= pointer.length) return false;
        final next = pointer.codeUnitAt(i + 1);
        if (next != 0x30 && next != 0x31) return false;
      }
    }
    return true;
  }

  /// Parses a binding from its wire form; returns `null` when [value] is not
  /// a binding.
  static KletsoBinding? tryParse(Object? value) =>
      isBinding(value) ? KletsoBinding((value as Map)['path'] as String) : null;

  /// The reference tokens of [path], unescaped.
  List<String> get tokens => path.isEmpty
      ? const <String>[]
      : path
            .substring(1)
            .split('/')
            .map((t) => t.replaceAll('~1', '/').replaceAll('~0', '~'))
            .toList(growable: false);

  /// Resolves this binding against [data]; returns `null` when any token is
  /// missing or the shapes do not match. Never throws.
  Object? resolve(Object? data) {
    Object? current = data;
    for (final token in tokens) {
      if (current is Map) {
        if (!current.containsKey(token)) return null;
        current = current[token];
      } else if (current is List) {
        final index = int.tryParse(token);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Wire form.
  JsonMap toJson() => <String, Object?>{'path': path};

  @override
  bool operator ==(Object other) =>
      other is KletsoBinding && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'KletsoBinding($path)';
}
