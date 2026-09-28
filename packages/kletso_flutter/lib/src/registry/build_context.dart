import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kletso_core/kletso_core.dart';

import '../theme/kletso_theme.dart';
import 'url_policy.dart';

/// What a component builder gets besides its node: the Flutter context, the
/// theme, lazy child resolution, the surface data and a way to fire actions.
abstract interface class KletsoBuildContext {
  /// The Flutter build context.
  BuildContext get context;

  /// The theme in scope.
  KletsoTheme get theme;

  /// The surface being rendered.
  KletsoSurface get surface;

  /// The surface's data model (bindings are already resolved on the node).
  JsonMap get data;

  /// Nesting level of the current node (root is 1).
  int get depth;

  /// URL policy from the session (allowlist).
  KletsoUrlPolicy get urlPolicy;

  /// Renders the component with [id]. Missing ids, cycles and nodes beyond
  /// the depth limit render an accessible fallback instead of throwing.
  Widget child(String id);

  /// Renders every id listed under the current node's [key] prop.
  List<Widget> children([String key = 'children']);

  /// Fires the current node's action with [actionId]. [args] are merged into
  /// `local` args or become the value of `submit`/`agent` actions.
  Future<void> executeAction(String actionId, {JsonMap args});

  /// Fires an [action] that is not on the current node (list items carry
  /// their own actions).
  Future<void> execute(KletsoAction action, {JsonMap args});

  /// Opens [url] through the host's `onOpenUrl` after the allowlist check.
  Future<void> openUrl(String url);
}

/// Who asked for a local action to run.
enum KletsoActionOrigin {
  /// The user tapped something on a rendered surface.
  surface,

  /// The server sent an `app.command` event (opt-in).
  server,

  /// The user tapped an `app.notify` notification (or a silent one ran).
  notification,
}

/// Passed to `local` action handlers.
abstract interface class KletsoActionContext {
  /// A build context: the tapped widget's for [KletsoActionOrigin.surface],
  /// the host-provided one (`client.ui.contextProvider`) for server commands.
  BuildContext get context;

  /// Where the action came from.
  KletsoActionOrigin get origin;

  /// The surface the action came from; `null` for server commands.
  KletsoSurface? get surface;

  /// The component that carries the action; `null` for server commands.
  KletsoNode? get node;

  /// The action definition (synthesised for server commands).
  KletsoAction get action;

  /// The client, when the surface is rendered inside a live chat.
  KletsoClient? get client;
}
