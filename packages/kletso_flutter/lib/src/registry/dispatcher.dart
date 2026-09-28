import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:meta/meta.dart';

import 'build_context.dart';
import 'registry.dart';
import 'url_policy.dart';

/// Called for `url` actions and markdown links after the allowlist check.
typedef KletsoOpenUrl = Future<void> Function(Uri uri);

/// Observes every action fired on a surface with the args the widget passed
/// (form values, extra local args); for analytics and tests.
typedef KletsoActionObserver =
    void Function(
      KletsoSurface surface,
      KletsoNode node,
      KletsoAction action,
      JsonMap args,
    );

/// Routes actions by kind: `local` to the host handler, `url` to the host's
/// opener, everything else to the client as an outbound frame.
final class KletsoActionDispatcher {
  /// Creates a dispatcher.
  KletsoActionDispatcher({
    required KletsoActionRegistry actions,
    this.client,
    this.onOpenUrl,
    this.urlPolicy = KletsoUrlPolicy.permissive,
    this.observer,
  }) : _actions = actions;

  final KletsoActionRegistry _actions;

  /// The live client; `null` in previews (non-local actions are then only
  /// observed).
  final KletsoClient? client;

  /// Host URL opener; when `null`, url actions are only observed.
  final KletsoOpenUrl? onOpenUrl;

  /// Allowlist.
  final KletsoUrlPolicy urlPolicy;

  /// Optional observer.
  final KletsoActionObserver? observer;

  /// Executes [action] from [node] in [surface]. Never throws for unknown
  /// kinds or missing handlers; those are reported through the client's
  /// event stream.
  Future<void> execute({
    required BuildContext context,
    required KletsoSurface surface,
    required KletsoNode node,
    required KletsoAction action,
    JsonMap args = const <String, Object?>{},
  }) async {
    observer?.call(surface, node, action, args);
    switch (action) {
      case KletsoLocalAction(:final name, args: final declared):
        final handler = _actions.handlerFor(name);
        final merged = <String, Object?>{...declared, ...args};
        if (handler != null) {
          await handler(
            merged,
            _ActionContext(context, surface, node, action, client),
          );
        }
        client?.reportLocalAction(
          name: name,
          args: merged,
          surfaceId: surface.surfaceId,
          componentId: node.id,
          actionId: action.id,
          handled: handler != null,
        );
      case KletsoAgentAction(:final value, :final label):
        await client?.send(
          KletsoOutbound.action(
            surfaceId: surface.surfaceId,
            componentId: node.id,
            actionId: action.id,
            value: value,
            label: label ?? node.stringOrNull('label'),
          ),
        );
      case KletsoSubmitAction(:final formId):
        await client?.send(
          KletsoOutbound.form(
            surfaceId: surface.surfaceId,
            componentId: node.id,
            actionId: action.id,
            formId: formId,
            values: args,
          ),
        );
      case KletsoConfirmAction(:final toolCallId, :final approve):
        await client?.send(
          KletsoOutbound.confirm(
            surfaceId: surface.surfaceId,
            componentId: node.id,
            actionId: action.id,
            toolCallId: toolCallId,
            approve: approve,
          ),
        );
      case KletsoWorkflowAction(:final workflowId, :final input):
        await client?.send(
          KletsoOutbound.action(
            surfaceId: surface.surfaceId,
            componentId: node.id,
            actionId: action.id,
            value: <String, Object?>{
              'workflowId': workflowId,
              'input': <String, Object?>{...input, ...args},
            },
            label: action.label ?? node.stringOrNull('label'),
          ),
        );
      case KletsoUrlAction(:final url):
        await openUrl(url);
      case KletsoUnknownAction():
        break;
    }
  }

  /// Opens [url] when the policy allows it.
  Future<void> openUrl(String url) async {
    final uri = urlPolicy.check(url);
    if (uri == null) return;
    await onOpenUrl?.call(uri);
  }
}

/// Runs a host-registered local action outside of a surface (server command).
/// Returns `false` when no handler is registered.
@internal
Future<bool> runLocalAction({
  required KletsoActionRegistry actions,
  required BuildContext context,
  required String name,
  required JsonMap args,
  KletsoClient? client,
  KletsoActionOrigin origin = KletsoActionOrigin.server,
}) async {
  final handler = actions.handlerFor(name);
  if (handler == null) return false;
  await handler(
    args,
    _ActionContext(
      context,
      null,
      null,
      KletsoLocalAction(id: 'command', name: name, args: args),
      client,
      origin: origin,
    ),
  );
  return true;
}

final class _ActionContext implements KletsoActionContext {
  const _ActionContext(
    this.context,
    this.surface,
    this.node,
    this.action,
    this.client, {
    this.origin = KletsoActionOrigin.surface,
  });

  @override
  final BuildContext context;
  @override
  final KletsoActionOrigin origin;
  @override
  final KletsoSurface? surface;
  @override
  final KletsoNode? node;
  @override
  final KletsoAction action;
  @override
  final KletsoClient? client;
}
