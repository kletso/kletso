/// Closed vocabularies of the event protocol.
///
/// Every enum has an `unknown` member so a client built against this version
/// keeps working when a newer runtime adds a value; `wire` is the string on
/// the wire and `parse` never throws.
library;

/// Who authored a message.
enum KletsoRole {
  /// The end user.
  user('user'),

  /// The agent.
  assistant('assistant'),

  /// Runtime-authored system text (e.g. handoff notices).
  system('system'),

  /// A tool result surfaced as a message.
  tool('tool'),

  /// A value this client does not know.
  unknown('unknown');

  const KletsoRole(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [unknown].
  static KletsoRole parse(String? value) => values.firstWhere(
    (r) => r.wire == value,
    orElse: () => KletsoRole.unknown,
  );
}

/// Lifecycle state of a conversation.
enum KletsoConversationStatus {
  /// The agent is answering.
  open('open'),

  /// A human or another agent has taken over.
  handoff('handoff'),

  /// No more turns are accepted.
  closed('closed'),

  /// A value this client does not know.
  unknown('unknown');

  const KletsoConversationStatus(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [unknown].
  static KletsoConversationStatus parse(String? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => KletsoConversationStatus.unknown,
  );
}

/// Why the model stopped generating.
enum KletsoFinishReason {
  /// Natural end of the reply.
  stop('stop'),

  /// The output token limit was hit.
  length('length'),

  /// The model called tools; the turn continues.
  toolCalls('tool_calls'),

  /// The provider filtered the content.
  contentFilter('content_filter'),

  /// The provider or runtime failed.
  error('error'),

  /// The user or runtime cancelled the turn.
  cancelled('cancelled'),

  /// A value this client does not know.
  unknown('unknown');

  const KletsoFinishReason(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [unknown].
  static KletsoFinishReason parse(String? value) => values.firstWhere(
    (r) => r.wire == value,
    orElse: () => KletsoFinishReason.unknown,
  );
}

/// What started a triggered conversation.
enum KletsoTriggerKind {
  /// `Kletso.instance.open()`.
  manual('manual'),

  /// A tracked event matched a rule.
  event('event'),

  /// A screen name matched a rule.
  screen('screen'),

  /// A delay or idle timer fired.
  time('time'),

  /// A value this client does not know.
  unknown('unknown');

  const KletsoTriggerKind(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [unknown].
  static KletsoTriggerKind parse(String? value) => values.firstWhere(
    (k) => k.wire == value,
    orElse: () => KletsoTriggerKind.unknown,
  );
}

/// State of a workflow run as reported by `workflow.*` events.
enum KletsoWorkflowStatus {
  /// `workflow.started`.
  started('started'),

  /// `workflow.completed`.
  completed('completed'),

  /// `workflow.failed`.
  failed('failed'),

  /// A value this client does not know.
  unknown('unknown');

  const KletsoWorkflowStatus(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [unknown].
  static KletsoWorkflowStatus parse(String? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => KletsoWorkflowStatus.unknown,
  );
}

/// How the SDK presents an `app.notify` event.
enum KletsoNotificationChannel {
  /// In-app banner at the top of the screen.
  banner('banner'),

  /// Short in-app toast at the bottom.
  toast('toast'),

  /// Modal alert the user must dismiss.
  alert('alert'),

  /// The OS notification tray through the host's system notifier; falls
  /// back to [banner] when the host has none.
  system('system'),

  /// No UI: only `openChat` / `action` run.
  silent('silent');

  const KletsoNotificationChannel(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [banner], the safe default.
  static KletsoNotificationChannel parse(String? value) => values.firstWhere(
    (k) => k.wire == value,
    orElse: () => KletsoNotificationChannel.banner,
  );
}
