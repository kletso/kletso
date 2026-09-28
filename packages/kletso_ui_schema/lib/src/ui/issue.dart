import 'package:meta/meta.dart';

/// What went wrong with a surface during validation.
enum KletsoUiIssueCode {
  /// The document is not a structurally valid `kletso.ui/v1` surface (not
  /// JSON, not an object, wrong `schema`, missing required field).
  invalidSchema(fatal: true),

  /// `root` does not name a component.
  missingRoot(fatal: true),

  /// More components than the limit allows.
  tooManyComponents(fatal: true),

  /// The tree from root to leaf is deeper than the limit.
  depthExceeded(fatal: true),

  /// A component is its own ancestor.
  cycle(fatal: true),

  /// The serialized surface is larger than the byte limit.
  oversize(fatal: true),

  /// A string exceeds the length limit.
  stringTooLong(fatal: true),

  /// An array exceeds the length limit.
  arrayTooLong(fatal: true),

  /// `fallbackText` is missing or empty.
  missingFallback(fatal: true),

  /// A child id does not name a component (the child is skipped).
  danglingChild(fatal: false),

  /// A `button` has no actions (it renders disabled).
  buttonWithoutAction(fatal: false),

  /// A binding points at nothing in `data` (the prop renders empty).
  unresolvedBinding(fatal: false),

  /// A component type is neither built-in nor in the supplied known set
  /// (it renders the fallback).
  unknownComponent(fatal: false),

  /// A component id is never reachable from the root (it is ignored).
  unreachableComponent(fatal: false);

  const KletsoUiIssueCode({required this.fatal});

  /// `true` when a surface with this issue must not be rendered at all;
  /// `false` for issues the renderer degrades gracefully around.
  final bool fatal;
}

/// One validation finding.
@immutable
final class KletsoUiIssue {
  /// Creates an issue.
  const KletsoUiIssue(this.code, this.message, {this.componentId, this.path});

  /// What kind of problem.
  final KletsoUiIssueCode code;

  /// Human-readable detail.
  final String message;

  /// The component involved, when there is one.
  final String? componentId;

  /// Location inside the surface document, when known.
  final String? path;

  /// Shortcut for `code.fatal`.
  bool get fatal => code.fatal;

  @override
  String toString() =>
      '${code.name}${componentId == null ? '' : '[$componentId]'}: $message';
}
