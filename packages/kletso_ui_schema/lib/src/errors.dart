/// Thrown when a wire payload does not have the structure the protocol
/// requires (missing field, wrong type, wrong `schema` marker).
///
/// Parsers in this package are liberal about *content* (unknown component
/// types, unknown action kinds and unknown event types are preserved, not
/// rejected) but strict about *shape*: a payload that cannot be read at all
/// throws this exception so the caller can surface a protocol error instead of
/// rendering garbage.
final class KletsoSchemaException implements Exception {
  /// Creates an exception for a structural problem at [path].
  const KletsoSchemaException(this.message, {this.path = r'$'});

  /// Human-readable description of the problem.
  final String message;

  /// JSON-pointer-like location of the offending value, `$` for the root.
  final String path;

  @override
  String toString() => 'KletsoSchemaException($path): $message';
}
