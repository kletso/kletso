import 'package:meta/meta.dart';

/// Size and shape limits for a `kletso.ui/v1` surface.
///
/// The defaults are the protocol limits from `docs/v1/04-ui-protocol.md`.
/// The runtime enforces them before an event is emitted; clients enforce them
/// again before decoding or building anything, because bot output is untrusted.
@immutable
final class KletsoUiLimits {
  /// Creates a limit set; every value defaults to the protocol limit.
  const KletsoUiLimits({
    this.maxComponents = 500,
    this.maxDepth = 16,
    this.maxBytes = 256 * 1024,
    this.maxStringLength = 8 * 1024,
    this.maxArrayLength = 200,
  });

  /// The protocol defaults.
  static const KletsoUiLimits standard = KletsoUiLimits();

  /// Maximum number of entries in `components`.
  final int maxComponents;

  /// Maximum number of nesting levels from the root to a leaf (root is 1).
  final int maxDepth;

  /// Maximum size of the serialized surface in UTF-8 bytes.
  final int maxBytes;

  /// Maximum length, in UTF-16 code units, of any string anywhere in the
  /// surface (props, data, fallback text).
  final int maxStringLength;

  /// Maximum length of any array anywhere in the surface.
  final int maxArrayLength;

  /// Returns a copy with the given fields replaced.
  KletsoUiLimits copyWith({
    int? maxComponents,
    int? maxDepth,
    int? maxBytes,
    int? maxStringLength,
    int? maxArrayLength,
  }) => KletsoUiLimits(
    maxComponents: maxComponents ?? this.maxComponents,
    maxDepth: maxDepth ?? this.maxDepth,
    maxBytes: maxBytes ?? this.maxBytes,
    maxStringLength: maxStringLength ?? this.maxStringLength,
    maxArrayLength: maxArrayLength ?? this.maxArrayLength,
  );

  @override
  bool operator ==(Object other) =>
      other is KletsoUiLimits &&
      other.maxComponents == maxComponents &&
      other.maxDepth == maxDepth &&
      other.maxBytes == maxBytes &&
      other.maxStringLength == maxStringLength &&
      other.maxArrayLength == maxArrayLength;

  @override
  int get hashCode => Object.hash(
    maxComponents,
    maxDepth,
    maxBytes,
    maxStringLength,
    maxArrayLength,
  );
}
