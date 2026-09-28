import 'package:flutter/widgets.dart';

import '../theme/kletso_theme.dart';

/// Renders untrusted markdown from the agent. Implementations must render
/// links only (no inline HTML, no scripts) and route link taps through
/// [KletsoMarkdownRequest.onLinkTap] so the allowlist applies.
abstract interface class KletsoMarkdownRenderer {
  /// Builds the widget for [request].
  Widget build(BuildContext context, KletsoMarkdownRequest request);
}

/// Everything a renderer needs for one markdown block.
final class KletsoMarkdownRequest {
  /// Creates a request.
  const KletsoMarkdownRequest({
    required this.markdown,
    required this.theme,
    required this.onLinkTap,
    this.streaming = false,
    this.allowImage,
  });

  /// The markdown source.
  final String markdown;

  /// Theme roles for text, code and link colours.
  final KletsoTheme theme;

  /// Called with the raw href; the SDK applies the allowlist and opens it.
  final void Function(String url) onLinkTap;

  /// `true` while deltas are still arriving.
  final bool streaming;

  /// Whether an image with this URL may be loaded (allowlist). `null`
  /// disallows images.
  final bool Function(String url)? allowImage;
}
