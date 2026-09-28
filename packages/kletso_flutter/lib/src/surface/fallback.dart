import 'package:flutter/material.dart';

import '../theme/kletso_theme.dart';

/// Accessible plain-text stand-in for a surface (or part of one) that cannot
/// be rendered: unknown type, depth or cycle problem, rejected document.
final class KletsoFallback extends StatelessWidget {
  /// Creates a fallback showing [text].
  const KletsoFallback(this.text, {super.key, this.reason});

  /// The surface's `fallbackText` (or a component-level hint).
  final String text;

  /// Developer-facing reason, exposed in semantics only.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Semantics(
      label: reason == null ? text : '$text ($reason)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: t.borderRadiusSm,
          border: Border.all(color: t.line),
        ),
        child: Text(text, style: t.body),
      ),
    );
  }
}
