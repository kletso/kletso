import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:meta/meta.dart';

import '../launcher/presentation.dart';
import '../notifications/notification_host.dart';
import '../theme/kletso_theme.dart';
import 'build_context.dart';
import 'dispatcher.dart';
import 'registry.dart';
import 'url_policy.dart';

/// Flutter-side state attached to a [KletsoClient]: registered components
/// and actions, the URL opener and the markdown renderer. Obtained through
/// `client.ui`; one per client, created on first use.
final class KletsoUi {
  KletsoUi._(this.client) {
    _commands = client.events.listen(_onEvent, onDone: dispose);
  }

  /// Releases the command subscription; called when the client's event
  /// stream closes (client disposed).
  void dispose() {
    unawaited(_commands.cancel());
    unawaited(_commandResults.close());
    unawaited(_notificationResults.close());
    hostData.dispose();
  }

  late final StreamSubscription<KletsoEvent> _commands;

  /// Supplies a [BuildContext] for actions that do not come from a tap
  /// (server commands). Hosts set this to `navigatorKey.currentContext`.
  BuildContext? Function()? contextProvider;

  /// Set by `open()` so [close] can dismiss the sheet or route.
  @internal
  VoidCallback? closeHandler;

  /// App state that surfaces may bind to under `/host/...` paths, e.g.
  /// `{ "path": "/host/cart/total" }`. Changing it rebuilds rendered
  /// surfaces; the value never leaves the device.
  final KletsoValueNotifier<JsonMap> hostData = KletsoValueNotifier<JsonMap>(
    const <String, Object?>{},
  );

  /// Resolves `/host/...` bindings against [hostData].
  Object? resolveHostBinding(KletsoBinding binding) {
    if (!binding.path.startsWith(KletsoSurface.hostPathPrefix)) return null;
    return KletsoBinding(
      binding.path.substring(KletsoSurface.hostPathPrefix.length - 1),
    ).resolve(hostData.value);
  }

  /// Names of server commands that ran, ignored or lacked a handler; for
  /// analytics and tests.
  final StreamController<KletsoCommandResult> _commandResults =
      StreamController<KletsoCommandResult>.broadcast();

  /// Outcome of every `app.command` seen.
  Stream<KletsoCommandResult> get commandResults => _commandResults.stream;

  /// Closes the chat if it is open (sheet or full-screen route).
  void close() => closeHandler?.call();

  /// Shows `system`-channel notifications in the OS tray. `null` (default)
  /// or a `false` return falls back to the in-app banner.
  KletsoSystemNotifier? systemNotifier;

  final StreamController<KletsoNotificationResult> _notificationResults =
      StreamController<KletsoNotificationResult>.broadcast();

  /// What happened to every notification the host widget handled.
  Stream<KletsoNotificationResult> get notificationResults =>
      _notificationResults.stream;

  /// Reports an outcome (called by `KletsoNotificationHost`).
  @internal
  void reportNotification(KletsoNotification n, KletsoNotificationOutcome o) {
    if (!_notificationResults.isClosed) {
      _notificationResults.add(KletsoNotificationResult(n, o));
    }
  }

  /// Runs a notification's tap target: opens the chat on its conversation
  /// when `openChat` is set and executes its `action` (`local` handler, `url`
  /// through [onOpenUrl], `agent` value sent to the runtime). The
  /// notification host calls this for in-app taps; hosts call it when the
  /// user taps the OS notification their [systemNotifier] showed. Uses
  /// [contextProvider] (or [fallbackContext]) for navigation.
  Future<void> openNotification(
    KletsoNotification n, {
    BuildContext? fallbackContext,
    KletsoPresentation presentation = KletsoPresentation.sheet,
    KletsoTheme? theme,
  }) async {
    final context = contextProvider?.call() ?? fallbackContext;
    if (context == null || !context.mounted) return;
    final payload = n.payload;
    final action = payload.action;
    if (payload.openChat) {
      if (n.conversationId.isNotEmpty &&
          client.activeConversation.value?.id != n.conversationId &&
          client.conversations.value.any((c) => c.id == n.conversationId)) {
        await client.switchConversation(n.conversationId);
      }
      if (!isOpen && context.mounted) {
        unawaited(
          client.open(context, presentation: presentation, theme: theme),
        );
      }
    }
    switch (action) {
      case KletsoLocalAction(:final name, :final args):
        if (!context.mounted) return;
        final ran = await runLocalAction(
          actions: actions,
          context: context,
          name: name,
          args: args,
          client: client,
          origin: KletsoActionOrigin.notification,
        );
        client.reportLocalAction(
          name: name,
          args: args,
          surfaceId: 'notification:${n.id}',
          componentId: n.id,
          actionId: action.id,
          handled: ran,
        );
      case KletsoUrlAction(:final url):
        await dispatcher.openUrl(url);
      case KletsoAgentAction(:final value, :final label):
        await client.send(KletsoOutbound.value(value, label: label));
      case null:
      case KletsoWorkflowAction():
      case KletsoSubmitAction():
      case KletsoConfirmAction():
      case KletsoUnknownAction():
        break;
    }
    reportNotification(n, KletsoNotificationOutcome.tapped);
  }

  void _onEvent(KletsoEvent e) {
    if (e is! KletsoServerEvent) return;
    final payload = e.payload;
    if (payload is! KletsoAppCommand) return;
    unawaited(_runCommand(payload));
  }

  Future<void> _runCommand(KletsoAppCommand cmd) async {
    if (!client.config.allowServerCommands) {
      _commandResults.add(
        KletsoCommandResult(cmd.name, KletsoCommandOutcome.disabled),
      );
      return;
    }
    if (!actions.names.contains(cmd.name)) {
      _commandResults.add(
        KletsoCommandResult(cmd.name, KletsoCommandOutcome.noHandler),
      );
      return;
    }
    final context = contextProvider?.call();
    if (context == null || !context.mounted) {
      _commandResults.add(
        KletsoCommandResult(cmd.name, KletsoCommandOutcome.noContext),
      );
      return;
    }
    if (cmd.closeChat) close();
    await runLocalAction(
      actions: actions,
      context: context,
      name: cmd.name,
      args: cmd.args,
      client: client,
    );
    _commandResults.add(
      KletsoCommandResult(cmd.name, KletsoCommandOutcome.ran),
    );
  }

  static final Expando<KletsoUi> _byClient = Expando<KletsoUi>('KletsoUi');

  /// The bindings for [client].
  static KletsoUi of(KletsoClient client) =>
      _byClient[client] ??= KletsoUi._(client);

  /// The client these bindings belong to.
  final KletsoClient client;

  /// Host-registered component builders.
  final KletsoComponentRegistry components = KletsoComponentRegistry();

  /// Host-registered `local` action handlers.
  final KletsoActionRegistry actions = KletsoActionRegistry();

  bool _isOpen = false;

  /// Whether the chat sheet or route is currently shown.
  bool get isOpen => _isOpen;

  /// Maintained by `open()`; hosts never set it.
  @internal
  set isOpen(bool value) => _isOpen = value;

  /// Opens URLs for `url` actions and markdown links. `null` means links are
  /// shown but do nothing; wire `url_launcher` or your router here.
  KletsoOpenUrl? onOpenUrl;

  /// URL allowlist; defaults to the hosts in the session bootstrap.
  KletsoUrlPolicy get urlPolicy {
    final hosts = client.session.value?.allowedUrlHosts;
    return KletsoUrlPolicy(allowedHosts: hosts ?? const <String>[]);
  }

  /// Component types the session's agent may emit plus the host's own.
  Set<String> get knownTypes => <String>{
    ...components.types,
    ...?client.session.value?.agent.allowedComponents,
  };

  /// A dispatcher bound to this client.
  KletsoActionDispatcher get dispatcher => KletsoActionDispatcher(
    actions: actions,
    client: client,
    onOpenUrl: onOpenUrl,
    urlPolicy: urlPolicy,
  );
}

/// What happened to an `app.command`.
enum KletsoCommandOutcome {
  /// The host handler ran.
  ran,

  /// `KletsoConfig.allowServerCommands` is off.
  disabled,

  /// No handler registered under that name.
  noHandler,

  /// No `contextProvider` (or its context is gone).
  noContext,
}

/// What the notification host did with an `app.notify`.
enum KletsoNotificationOutcome {
  /// Banner, toast or alert is on screen.
  shown,

  /// Handed to [KletsoUi.systemNotifier], which showed it.
  system,

  /// `system` channel without a notifier (or it declined): banner shown.
  bannerFallback,

  /// `silent` channel: only the tap target ran.
  silent,

  /// The user tapped it (or a silent one ran its target).
  tapped,
}

/// Result record for [KletsoUi.notificationResults].
final class KletsoNotificationResult {
  /// Creates a result.
  const KletsoNotificationResult(this.notification, this.outcome);

  /// The notification.
  final KletsoNotification notification;

  /// What happened.
  final KletsoNotificationOutcome outcome;
}

/// Result record for [KletsoUi.commandResults].
final class KletsoCommandResult {
  /// Creates a result.
  const KletsoCommandResult(this.name, this.outcome);

  /// Command name.
  final String name;

  /// What happened.
  final KletsoCommandOutcome outcome;
}

/// Flutter extensions on the core client.
extension KletsoClientUi on KletsoClient {
  /// The Flutter bindings for this client.
  KletsoUi get ui => KletsoUi.of(this);

  /// Registers a widget builder for a custom (or built-in) component type.
  /// Pass [spec] so `kletso_flutter:sync` can publish the type.
  void registerComponent(
    String type,
    KletsoComponentBuilder builder, {
    KletsoComponentSpec? spec,
  }) => ui.components.register(type, builder, spec: spec);

  /// Registers a handler for a `local` action name.
  void registerAction(String name, KletsoActionHandler handler) =>
      ui.actions.register(name, handler);

  /// The URL opener for `url` actions and markdown links.
  KletsoOpenUrl? get onOpenUrl => ui.onOpenUrl;

  /// Sets the URL opener for `url` actions and markdown links.
  set onOpenUrl(KletsoOpenUrl? opener) => ui.onOpenUrl = opener;

  /// Sets the OS-tray notifier for `system` notifications (see
  /// [KletsoSystemNotifier]).
  set onSystemNotification(KletsoSystemNotifier? notifier) =>
      ui.systemNotifier = notifier;

  /// Closes the chat sheet or route if one is showing.
  void close() => ui.close();

  /// Replaces the app state surfaces can bind to via `/host/...` paths.
  void setHostData(JsonMap data) =>
      ui.hostData.value = Map<String, Object?>.unmodifiable(data);

  /// Merges [changes] into the host data.
  void updateHostData(JsonMap changes) =>
      ui.hostData.value = Map<String, Object?>.unmodifiable(<String, Object?>{
        ...ui.hostData.value,
        ...changes,
      });
}
