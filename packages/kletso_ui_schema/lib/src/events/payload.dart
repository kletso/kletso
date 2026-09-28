import 'package:meta/meta.dart';

import '../json_utils.dart';
import '../ui/action.dart';
import '../ui/surface.dart';
import 'entities.dart';
import 'enums.dart';
import 'envelope.dart';

/// The `type` strings of `kletso.events/v1`.
abstract final class KletsoEventTypes {
  /// A conversation was created.
  static const String conversationCreated = 'conversation.created';

  /// Conversation metadata changed.
  static const String conversationUpdated = 'conversation.updated';

  /// The conversation was closed.
  static const String conversationClosed = 'conversation.closed';

  /// A message (any role) was appended.
  static const String messageCreated = 'message.created';

  /// Streamed text chunk for an assistant message.
  static const String messageDelta = 'message.delta';

  /// Final text and usage for an assistant message.
  static const String messageCompleted = 'message.completed';

  /// A tool call began.
  static const String toolStarted = 'tool.started';

  /// A tool call is paused until the user confirms.
  static const String toolConfirmationRequired = 'tool.confirmation_required';

  /// A tool call finished successfully.
  static const String toolCompleted = 'tool.completed';

  /// A tool call failed.
  static const String toolFailed = 'tool.failed';

  /// A workflow run started.
  static const String workflowStarted = 'workflow.started';

  /// A workflow run finished.
  static const String workflowCompleted = 'workflow.completed';

  /// A workflow run failed.
  static const String workflowFailed = 'workflow.failed';

  /// A full `kletso.ui/v1` surface to render.
  static const String uiRender = 'ui.render';

  /// Partial surface update (V2).
  static const String uiPatch = 'ui.patch';

  /// An action taken on a surface, echoed to every client.
  static const String uiAction = 'ui.action';

  /// The conversation was handed to a human or another agent.
  static const String handoffStarted = 'handoff.started';

  /// The handoff ended.
  static const String handoffCompleted = 'handoff.completed';

  /// A trigger opened or nudged the conversation.
  static const String triggerFired = 'trigger.fired';

  /// The agent is composing; clients show a typing indicator with a TTL.
  static const String agentTyping = 'agent.typing';

  /// The agent asks the host app to run a registered local action without a
  /// tap (navigate, close the chat). Hosts opt in; unregistered names are
  /// ignored.
  static const String appCommand = 'app.command';

  /// A proactive notification for the host app (banner, toast, alert, OS
  /// tray or silent), produced by trigger/workflow rules. Independent of
  /// chat messages; may arrive live or inside a push payload.
  static const String appNotify = 'app.notify';

  /// A turn-level error.
  static const String error = 'error';
}

/// Typed view of an envelope's `data`. Every constructor is total: missing or
/// mistyped fields become `null`/defaults, never exceptions, because clients
/// must keep working when the runtime ships a newer minor version.
@immutable
sealed class KletsoEventPayload {
  const KletsoEventPayload();

  /// Builds the typed payload for [envelope].
  factory KletsoEventPayload.fromEnvelope(KletsoEventEnvelope envelope) {
    final d = envelope.data;
    switch (envelope.type) {
      case KletsoEventTypes.conversationCreated:
      case KletsoEventTypes.conversationUpdated:
      case KletsoEventTypes.conversationClosed:
        return KletsoConversationEvent(
          KletsoConversationInfo.fromJson(optionalMap(d, 'conversation')),
        );
      case KletsoEventTypes.messageCreated:
        return KletsoMessageCreated(
          messageId: optionalString(d, 'messageId') ?? '',
          role: KletsoRole.parse(optionalString(d, 'role')),
          text: optionalString(d, 'text'),
          value: d['value'],
          clientId: optionalString(d, 'clientId'),
        );
      case KletsoEventTypes.messageDelta:
        return KletsoMessageDelta(
          messageId: optionalString(d, 'messageId') ?? '',
          text: optionalString(d, 'text') ?? '',
        );
      case KletsoEventTypes.messageCompleted:
        final usage = optionalMap(d, 'usage') ?? const <String, Object?>{};
        return KletsoMessageCompleted(
          messageId: optionalString(d, 'messageId') ?? '',
          text: optionalString(d, 'text') ?? '',
          inputTokens: optionalInt(usage, 'in') ?? 0,
          outputTokens: optionalInt(usage, 'out') ?? 0,
          cachedInputTokens: optionalInt(usage, 'cachedIn') ?? 0,
          reasoningTokens: optionalInt(usage, 'reasoning') ?? 0,
          costMicros: optionalInt(d, 'costMicros') ?? 0,
          latencyMs: optionalInt(d, 'latencyMs') ?? 0,
          finishReason: KletsoFinishReason.parse(
            optionalString(d, 'finishReason'),
          ),
        );
      case KletsoEventTypes.toolStarted:
        return KletsoToolStarted(
          toolCallId: optionalString(d, 'toolCallId') ?? '',
          name: optionalString(d, 'name') ?? '',
          args: freezeMap(optionalMap(d, 'args')),
        );
      case KletsoEventTypes.toolConfirmationRequired:
        return KletsoToolConfirmationRequired(
          toolCallId: optionalString(d, 'toolCallId') ?? '',
          name: optionalString(d, 'name') ?? '',
          args: freezeMap(optionalMap(d, 'args')),
          surface: _surfaceOrNull(d['surface']),
        );
      case KletsoEventTypes.toolCompleted:
      case KletsoEventTypes.toolFailed:
        final err = optionalMap(d, 'error');
        return KletsoToolFinished(
          toolCallId: optionalString(d, 'toolCallId') ?? '',
          name: optionalString(d, 'name') ?? '',
          durationMs: optionalInt(d, 'durationMs') ?? 0,
          failed: envelope.type == KletsoEventTypes.toolFailed,
          result: d['result'],
          errorCode: err == null ? null : optionalString(err, 'code'),
          errorMessage: err == null ? null : optionalString(err, 'message'),
        );
      case KletsoEventTypes.workflowStarted:
      case KletsoEventTypes.workflowCompleted:
      case KletsoEventTypes.workflowFailed:
        return KletsoWorkflowEvent(
          runId: optionalString(d, 'runId') ?? '',
          status: KletsoWorkflowStatus.parse(envelope.type.split('.').last),
          output: d['output'],
          error: optionalString(d, 'error'),
        );
      case KletsoEventTypes.uiRender:
        return KletsoUiRender(rawSurface: d['surface']);
      case KletsoEventTypes.uiPatch:
        return KletsoUiPatch(
          surfaceId: optionalString(d, 'surfaceId') ?? '',
          data: optionalMap(d, 'data'),
          components: optionalMap(d, 'components'),
        );
      case KletsoEventTypes.uiAction:
        return KletsoUiActionEvent(
          surfaceId: optionalString(d, 'surfaceId') ?? '',
          componentId: optionalString(d, 'componentId') ?? '',
          actionId: optionalString(d, 'actionId') ?? '',
          value: d['value'],
        );
      case KletsoEventTypes.handoffStarted:
      case KletsoEventTypes.handoffCompleted:
        return KletsoHandoffEvent(
          target: optionalString(d, 'target') ?? '',
          agentName: optionalString(d, 'agentName'),
          completed: envelope.type == KletsoEventTypes.handoffCompleted,
        );
      case KletsoEventTypes.triggerFired:
        return KletsoTriggerFired(
          triggerId: optionalString(d, 'triggerId') ?? '',
          kind: KletsoTriggerKind.parse(optionalString(d, 'kind')),
          name: optionalString(d, 'name') ?? '',
        );
      case KletsoEventTypes.agentTyping:
        return const KletsoAgentTyping();
      case KletsoEventTypes.appCommand:
        return KletsoAppCommand(
          name: optionalString(d, 'name') ?? '',
          args: freezeMap(optionalMap(d, 'args')),
          closeChat: optionalBool(d, 'closeChat') ?? false,
        );
      case KletsoEventTypes.appNotify:
        return KletsoAppNotification(
          notificationId: optionalString(d, 'notificationId') ?? '',
          title: optionalString(d, 'title') ?? '',
          body: optionalString(d, 'body'),
          channel: KletsoNotificationChannel.parse(
            optionalString(d, 'channel'),
          ),
          openChat: optionalBool(d, 'openChat') ?? false,
          action: d['action'] is Map
              ? KletsoAction.fromJson(d['action'], path: r'$.data.action')
              : null,
          rawSurface: d['surface'],
          ttl: switch (optionalInt(d, 'ttlSeconds')) {
            final int s when s > 0 => Duration(seconds: s),
            _ => null,
          },
          imageUrl: optionalString(d, 'imageUrl'),
          data: freezeMap(optionalMap(d, 'data')),
        );
      case KletsoEventTypes.error:
        return KletsoErrorEvent(
          code: optionalString(d, 'code') ?? 'internal',
          message: optionalString(d, 'message') ?? '',
          retryable: optionalBool(d, 'retryable') ?? false,
        );
      default:
        return KletsoUnknownEvent(envelope.type, d);
    }
  }

  static KletsoSurface? _surfaceOrNull(Object? raw) {
    final result = KletsoSurface.parseJson(raw);
    return result is KletsoSurfaceOk ? result.surface : null;
  }
}

/// `conversation.created` / `.updated` / `.closed`.
final class KletsoConversationEvent extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoConversationEvent(this.conversation);

  /// The conversation after the change.
  final KletsoConversationInfo conversation;
}

/// `message.created`.
final class KletsoMessageCreated extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoMessageCreated({
    required this.messageId,
    required this.role,
    this.text,
    this.value,
    this.clientId,
  });

  /// New message id.
  final String messageId;

  /// Who authored the message.
  final KletsoRole role;

  /// Initial text (complete for user messages, often empty for assistant).
  final String? text;

  /// Structured value for action/form-originated user turns.
  final Object? value;

  /// The client-assigned id that produced this message, for echo matching.
  final String? clientId;
}

/// `message.delta`.
final class KletsoMessageDelta extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoMessageDelta({required this.messageId, required this.text});

  /// Message being streamed.
  final String messageId;

  /// Text to append.
  final String text;
}

/// `message.completed`.
final class KletsoMessageCompleted extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoMessageCompleted({
    required this.messageId,
    required this.text,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedInputTokens = 0,
    this.reasoningTokens = 0,
    this.costMicros = 0,
    this.latencyMs = 0,
    this.finishReason = KletsoFinishReason.stop,
  });

  /// Message that finished.
  final String messageId;

  /// Final full text; clients replace their accumulated deltas with it.
  final String text;

  /// Prompt tokens.
  final int inputTokens;

  /// Completion tokens.
  final int outputTokens;

  /// Prompt tokens served from the provider cache.
  final int cachedInputTokens;

  /// Reasoning tokens, when the provider reports them.
  final int reasoningTokens;

  /// Cost on the customer's own key, in micro-units of their currency.
  final int costMicros;

  /// Wall-clock latency of the turn.
  final int latencyMs;

  /// Why the model stopped.
  final KletsoFinishReason finishReason;
}

/// `tool.started`.
final class KletsoToolStarted extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoToolStarted({
    required this.toolCallId,
    required this.name,
    this.args = const <String, Object?>{},
  });

  /// Tool call id.
  final String toolCallId;

  /// Tool name.
  final String name;

  /// Arguments (redacted by the runtime per the tool schema).
  final JsonMap args;
}

/// `tool.confirmation_required`.
final class KletsoToolConfirmationRequired extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoToolConfirmationRequired({
    required this.toolCallId,
    required this.name,
    this.args = const <String, Object?>{},
    this.surface,
  });

  /// Paused tool call id.
  final String toolCallId;

  /// Tool name.
  final String name;

  /// Arguments the user is asked to approve.
  final JsonMap args;

  /// The `confirm` surface to render, when it parsed.
  final KletsoSurface? surface;
}

/// `tool.completed` and `tool.failed`.
final class KletsoToolFinished extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoToolFinished({
    required this.toolCallId,
    required this.name,
    required this.durationMs,
    required this.failed,
    this.result,
    this.errorCode,
    this.errorMessage,
  });

  /// Tool call id.
  final String toolCallId;

  /// Tool name.
  final String name;

  /// Execution time.
  final int durationMs;

  /// `true` for `tool.failed`.
  final bool failed;

  /// Truncated result, on success.
  final Object? result;

  /// Error code, on failure.
  final String? errorCode;

  /// Error message, on failure.
  final String? errorMessage;
}

/// `workflow.started` / `.completed` / `.failed`.
final class KletsoWorkflowEvent extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoWorkflowEvent({
    required this.runId,
    required this.status,
    this.output,
    this.error,
  });

  /// Workflow run id.
  final String runId;

  /// Run state.
  final KletsoWorkflowStatus status;

  /// Output on completion.
  final Object? output;

  /// Error on failure.
  final String? error;
}

/// `ui.render`. The surface is kept raw so the renderer can apply its own
/// limits and known-type set via [parse].
final class KletsoUiRender extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoUiRender({required this.rawSurface});

  /// The decoded surface document.
  final Object? rawSurface;

  /// Validates the surface with the renderer's settings.
  KletsoSurfaceResult parse({Set<String> knownTypes = const <String>{}}) =>
      KletsoSurface.parseJson(rawSurface, knownTypes: knownTypes);
}

/// `ui.patch`: partial update of an already rendered surface. `data` is
/// deep-merged into the surface data; `components` replaces nodes by id
/// (`null` removes one). Apply with [KletsoSurface.patched].
final class KletsoUiPatch extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoUiPatch({required this.surfaceId, this.data, this.components});

  /// The surface to update.
  final String surfaceId;

  /// Data to merge, if any.
  final JsonMap? data;

  /// Components to replace or remove, if any.
  final JsonMap? components;
}

/// `ui.action`.
final class KletsoUiActionEvent extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoUiActionEvent({
    required this.surfaceId,
    required this.componentId,
    required this.actionId,
    this.value,
  });

  /// Surface acted on.
  final String surfaceId;

  /// Component acted on.
  final String componentId;

  /// Action id.
  final String actionId;

  /// Value posted with the action.
  final Object? value;
}

/// `handoff.started` / `.completed`.
final class KletsoHandoffEvent extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoHandoffEvent({
    required this.target,
    required this.completed,
    this.agentName,
  });

  /// Where the conversation went (`inbox`, `slack`, an agent id).
  final String target;

  /// Display name of the human or agent that took over.
  final String? agentName;

  /// `true` for `handoff.completed`.
  final bool completed;
}

/// `trigger.fired`.
final class KletsoTriggerFired extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoTriggerFired({
    required this.triggerId,
    required this.kind,
    required this.name,
  });

  /// Trigger id.
  final String triggerId;

  /// What fired.
  final KletsoTriggerKind kind;

  /// Trigger name.
  final String name;
}

/// `agent.typing`.
final class KletsoAgentTyping extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoAgentTyping();
}

/// `app.command`: server-initiated local action.
final class KletsoAppCommand extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoAppCommand({
    required this.name,
    this.args = const <String, Object?>{},
    this.closeChat = false,
  });

  /// Registered local action name (`open_product`).
  final String name;

  /// Arguments for the handler.
  final JsonMap args;

  /// Whether the chat should close before the handler runs.
  final bool closeChat;
}

/// `app.notify`: a proactive notification for the host app. Rendered by the
/// SDK's notification host (banner/toast/alert), handed to the OS tray
/// through the host's system notifier, or silent (open the chat / run the
/// action only). Never a chat message; the same envelope may also arrive in
/// a push payload under the `kletso` key.
final class KletsoAppNotification extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoAppNotification({
    required this.notificationId,
    required this.title,
    this.body,
    this.channel = KletsoNotificationChannel.banner,
    this.openChat = false,
    this.action,
    this.rawSurface,
    this.ttl,
    this.imageUrl,
    this.data = const <String, Object?>{},
  });

  /// Stable id (`ntf_…`); the client dedupes on it.
  final String notificationId;

  /// Headline.
  final String title;

  /// Optional body text.
  final String? body;

  /// Presentation channel.
  final KletsoNotificationChannel channel;

  /// Open the chat when tapped (immediately for [KletsoNotificationChannel.silent]).
  final bool openChat;

  /// Optional tap action: `local`, `url` or `agent`.
  final KletsoAction? action;

  /// Optional inline `kletso.ui/v1` surface shown in banners and alerts.
  final Object? rawSurface;

  /// Auto-dismiss for banner/toast.
  final Duration? ttl;

  /// Optional image.
  final String? imageUrl;

  /// Opaque host data.
  final JsonMap data;

  /// Validates the inline surface, if any.
  KletsoSurfaceResult? parseSurface({
    Set<String> knownTypes = const <String>{},
  }) => rawSurface == null
      ? null
      : KletsoSurface.parseJson(rawSurface, knownTypes: knownTypes);

  /// Wire form of `data` (for fakes and tests).
  JsonMap toJson() => <String, Object?>{
    'notificationId': notificationId,
    'title': title,
    if (body != null) 'body': body,
    'channel': channel.wire,
    if (openChat) 'openChat': true,
    if (action != null) 'action': action!.toJson(),
    if (rawSurface != null) 'surface': rawSurface,
    if (ttl != null) 'ttlSeconds': ttl!.inSeconds,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (data.isNotEmpty) 'data': data,
  };
}

/// `error`.
final class KletsoErrorEvent extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoErrorEvent({
    required this.code,
    required this.message,
    required this.retryable,
  });

  /// Error code from the API error vocabulary.
  final String code;

  /// Human-readable message.
  final String message;

  /// Whether retrying the turn may help.
  final bool retryable;
}

/// Any event type this package does not know.
final class KletsoUnknownEvent extends KletsoEventPayload {
  /// Creates the payload.
  const KletsoUnknownEvent(this.type, this.data);

  /// The unknown type string.
  final String type;

  /// The untouched data.
  final JsonMap data;
}
