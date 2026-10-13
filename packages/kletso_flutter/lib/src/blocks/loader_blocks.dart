// Component loaders (D88): what the chat shows while a `render_ui` call is
// still streaming (`ui.pending`) or when a surface asks for placeholders
// (`loading` block with `for`). Hosts register a loader per component type;
// everything else falls back to [KletsoShimmer].
import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../registry/registry.dart';
import '../theme/kletso_theme.dart';

/// Layout types that never get a loader of their own: their children do.
const Set<String> kletsoLayoutTypes = <String>{
  KletsoBuiltinTypes.column,
  KletsoBuiltinTypes.row,
  KletsoBuiltinTypes.divider,
};

/// Most placeholders shown for one pending surface.
const int kletsoMaxLoaders = 6;

/// The loader for [type]: the host's, else a generic [KletsoShimmer].
Widget kletsoLoader(
  BuildContext context, {
  required KletsoTheme theme,
  required String type,
  KletsoComponentRegistry? registry,
  String? id,
  int index = 0,
}) {
  final host = registry?.loaderFor(type);
  final ctx = KletsoLoaderContext(
    context: context,
    theme: theme,
    type: type,
    id: id,
    index: index,
  );
  return host != null ? host(ctx) : KletsoShimmer(theme: theme);
}

/// Placeholders for one streaming surface: one loader per announced
/// non-layout component (in order, capped), or a single generic one while
/// nothing is known yet.
final class KletsoPendingSurfaceView extends StatelessWidget {
  /// Creates the view.
  const KletsoPendingSurfaceView({
    required this.pending,
    required this.theme,
    super.key,
    this.registry,
  });

  /// The `ui.pending` payload.
  final KletsoUiPending pending;

  /// Theme for the generic loader.
  final KletsoTheme theme;

  /// Host loaders (the client's component registry).
  final KletsoComponentRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final items = pending.components
        .where((c) => !kletsoLayoutTypes.contains(c.type))
        .take(kletsoMaxLoaders)
        .toList();
    final children = <Widget>[];
    if (items.isEmpty) {
      children.add(
        kletsoLoader(context, theme: theme, type: '', registry: registry),
      );
    } else {
      for (var i = 0; i < items.length; i++) {
        if (i > 0) children.add(const SizedBox(height: 8));
        children.add(
          KeyedSubtree(
            key: ValueKey<String>(
              'loader_${pending.toolCallId}_${items[i].id}',
            ),
            child: kletsoLoader(
              context,
              theme: theme,
              type: items[i].type,
              id: items[i].id,
              index: i,
              registry: registry,
            ),
          ),
        );
      }
    }
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Generic placeholder: a card-shaped block with three pulsing bars. Static
/// when the platform asks for reduced motion.
final class KletsoShimmer extends StatefulWidget {
  /// Creates the placeholder.
  const KletsoShimmer({required this.theme, super.key, this.height = 72});

  /// Theme (surface and line colours, radius).
  final KletsoTheme theme;

  /// Height of the block.
  final double height;

  @override
  State<KletsoShimmer> createState() => _KletsoShimmerState();
}

final class _KletsoShimmerState extends State<KletsoShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    Widget bar(double widthFactor) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: t.line,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.borderRadiusMd,
          border: Border.all(color: t.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[bar(0.55), bar(0.9), bar(0.7)],
        ),
      ),
    );
  }
}
