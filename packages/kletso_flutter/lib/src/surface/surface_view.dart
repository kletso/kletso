import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../blocks/blocks.dart';
import '../listenable_adapter.dart';
import '../markdown/plain_renderer.dart';
import '../markdown/renderer.dart';
import '../registry/build_context.dart';
import '../registry/dispatcher.dart';
import '../registry/registry.dart';
import '../registry/ui_bindings.dart';
import '../registry/url_policy.dart';
import '../theme/kletso_theme.dart';
import 'fallback.dart';

/// Renders one `kletso.ui/v1` surface through the component registry.
///
/// Precedence per node: host builder → SDK built-in → [KletsoFallback].
/// Limits (component count, depth, cycles, dangling ids) never throw; the
/// affected part renders the fallback text and unknown types are reported
/// through the client.
final class KletsoSurfaceView extends StatelessWidget {
  /// Renders [surface]. Pass [client] inside a live chat so actions reach the
  /// runtime; without it, non-local actions are only observed.
  const KletsoSurfaceView({
    required this.surface,
    super.key,
    this.client,
    this.registry,
    this.dispatcher,
    this.markdownRenderer = const KletsoPlainMarkdownRenderer(),
    this.limits = KletsoUiLimits.standard,
    this.streaming = false,
    this.bindingResolver,
  });

  /// The surface.
  final KletsoSurface surface;

  /// The live client (registry, dispatcher and allowlist come from it when
  /// [registry]/[dispatcher] are not given).
  final KletsoClient? client;

  /// Explicit registry (previews, tests).
  final KletsoComponentRegistry? registry;

  /// Explicit dispatcher (previews, tests).
  final KletsoActionDispatcher? dispatcher;

  /// Markdown renderer for `markdown` blocks.
  final KletsoMarkdownRenderer markdownRenderer;

  /// Limits to enforce while building.
  final KletsoUiLimits limits;

  /// Whether the parent message is still streaming.
  final bool streaming;

  /// Resolves `/host/...` bindings; defaults to the client's `ui.hostData`.
  final KletsoBindingResolver? bindingResolver;

  @override
  Widget build(BuildContext context) {
    final theme = KletsoTheme.of(context);
    final c = client;
    final reg =
        registry ?? (c == null ? KletsoComponentRegistry() : c.ui.components);
    final disp =
        dispatcher ??
        (c == null
            ? KletsoActionDispatcher(actions: KletsoActionRegistry())
            : c.ui.dispatcher);
    if (surface.components.length > limits.maxComponents) {
      return KletsoFallback(
        surface.fallbackText,
        reason: 'too many components',
      );
    }
    final renderer = _Renderer(
      surface: surface,
      theme: theme,
      registry: reg,
      dispatcher: disp,
      markdown: markdownRenderer,
      limits: limits,
      client: c,
      streaming: streaming,
      external: bindingResolver ?? c?.ui.resolveHostBinding,
    );
    Widget build() => Semantics(
      container: true,
      liveRegion: true,
      label: surface.fallbackText,
      child: renderer.build(context, surface.root, const <String>{}, 1),
    );
    if (c == null || bindingResolver != null) return build();
    // Rebuild when the host app changes the data surfaces bind to.
    return _HostDataListener(source: c.ui.hostData, builder: build);
  }
}

final class _Renderer {
  _Renderer({
    required this.surface,
    required this.theme,
    required this.registry,
    required this.dispatcher,
    required this.markdown,
    required this.limits,
    required this.client,
    required this.streaming,
    required this.external,
  });

  final KletsoSurface surface;
  final KletsoTheme theme;
  final KletsoComponentRegistry registry;
  final KletsoActionDispatcher dispatcher;
  final KletsoMarkdownRenderer markdown;
  final KletsoUiLimits limits;
  final KletsoClient? client;
  final bool streaming;
  final KletsoBindingResolver? external;
  final Set<String> _reportedUnknown = <String>{};

  Widget build(
    BuildContext context,
    String id,
    Set<String> ancestors,
    int depth,
  ) {
    final raw = surface.node(id);
    if (raw == null) {
      return KletsoFallback(
        surface.fallbackText,
        reason: 'missing component $id',
      );
    }
    if (ancestors.contains(id)) {
      return KletsoFallback(surface.fallbackText, reason: 'cycle at $id');
    }
    if (depth > limits.maxDepth) {
      return KletsoFallback(surface.fallbackText, reason: 'depth limit at $id');
    }
    final node = surface.resolveNode(raw, external: external);
    final ctx = _BuildContext(this, context, node, <String>{
      ...ancestors,
      id,
    }, depth);
    final host = registry.builderFor(node.type);
    if (host != null) {
      return KeyedSubtree(key: ValueKey<String>(id), child: host(ctx, node));
    }
    final builtin = kletsoBuiltinBuilder(node.type);
    if (builtin != null) {
      return KeyedSubtree(key: ValueKey<String>(id), child: builtin(ctx, node));
    }
    if (_reportedUnknown.add(node.type)) {
      client?.reportUnknownComponent(
        type: node.type,
        surfaceId: surface.surfaceId,
      );
    }
    return KletsoFallback(
      surface.fallbackText,
      reason: 'unknown type ${node.type}',
    );
  }
}

final class _BuildContext implements KletsoBuildContext {
  _BuildContext(this._r, this.context, this._node, this._ancestors, this.depth);

  final _Renderer _r;
  final KletsoNode _node;
  final Set<String> _ancestors;

  @override
  final BuildContext context;

  @override
  final int depth;

  @override
  KletsoTheme get theme => _r.theme;

  @override
  KletsoSurface get surface => _r.surface;

  @override
  JsonMap get data => _r.surface.data;

  @override
  KletsoUrlPolicy get urlPolicy => _r.dispatcher.urlPolicy;

  /// Markdown renderer (used by the `markdown` block).
  KletsoMarkdownRenderer get markdown => _r.markdown;

  /// Whether the message is streaming.
  bool get streaming => _r.streaming;

  @override
  Widget child(String id) => _r.build(context, id, _ancestors, depth + 1);

  @override
  List<Widget> children([String key = 'children']) {
    final ids = _node.childIds(key);
    final capped = ids.length > _r.limits.maxArrayLength
        ? ids.sublist(0, _r.limits.maxArrayLength)
        : ids;
    return capped.map(child).toList(growable: false);
  }

  @override
  Future<void> executeAction(
    String actionId, {
    JsonMap args = const <String, Object?>{},
  }) async {
    final action = _node.action(actionId);
    if (action == null) return;
    await execute(action, args: args);
  }

  @override
  Future<void> execute(
    KletsoAction action, {
    JsonMap args = const <String, Object?>{},
  }) => _r.dispatcher.execute(
    context: context,
    surface: _r.surface,
    node: _node,
    action: action,
    args: args,
  );

  @override
  Future<void> openUrl(String url) => _r.dispatcher.openUrl(url);
}

/// Internal access for built-in blocks to renderer-level services.
extension KletsoBuildContextInternal on KletsoBuildContext {
  /// The markdown renderer, when this context comes from [KletsoSurfaceView].
  KletsoMarkdownRenderer get markdownRenderer => this is _BuildContext
      ? (this as _BuildContext).markdown
      : const KletsoPlainMarkdownRenderer();

  /// Whether the owning message is still streaming.
  bool get isStreaming =>
      this is _BuildContext && (this as _BuildContext).streaming;
}

final class _HostDataListener extends StatefulWidget {
  const _HostDataListener({required this.source, required this.builder});
  final KletsoValueListenable<JsonMap> source;
  final Widget Function() builder;
  @override
  State<_HostDataListener> createState() => _HostDataListenerState();
}

final class _HostDataListenerState extends State<_HostDataListener> {
  late KletsoListenable<JsonMap> _listenable = widget.source.asFlutter();

  @override
  void didUpdateWidget(_HostDataListener old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) {
      _listenable.dispose();
      _listenable = widget.source.asFlutter();
    }
  }

  @override
  void dispose() {
    _listenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _listenable,
    builder: (_, _) => widget.builder(),
  );
}
