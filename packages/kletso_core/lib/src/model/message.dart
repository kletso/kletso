import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

/// Delivery state of a message.
enum KletsoMessageStatus {
  /// Sent by this device, not yet acknowledged by the runtime.
  pending,

  /// Assistant text is still arriving.
  streaming,

  /// Final.
  complete,

  /// The turn errored; [KletsoMessage.error] has details.
  failed,
}

/// State of a tool call inside an assistant turn.
enum KletsoToolCallStatus {
  /// Running on the runtime.
  running,

  /// Paused until the user answers a `confirm` block.
  awaitingConfirmation,

  /// Finished successfully.
  completed,

  /// Finished with an error.
  failed,
}

/// A tool call shown in the transcript ("Searching flights…").
@immutable
final class KletsoToolCall {
  /// Creates a tool call.
  const KletsoToolCall({
    required this.id,
    required this.name,
    required this.status,
    this.args = const <String, Object?>{},
    this.durationMs,
    this.result,
    this.error,
  });

  /// Tool call id.
  final String id;

  /// Tool name.
  final String name;

  /// Current state.
  final KletsoToolCallStatus status;

  /// Arguments (redacted by the runtime).
  final JsonMap args;

  /// Execution time once finished.
  final int? durationMs;

  /// Truncated result once completed.
  final Object? result;

  /// Error message once failed.
  final String? error;

  /// Returns a copy with the given fields replaced.
  KletsoToolCall copyWith({
    KletsoToolCallStatus? status,
    int? durationMs,
    Object? result,
    String? error,
  }) => KletsoToolCall(
    id: id,
    name: name,
    status: status ?? this.status,
    args: args,
    durationMs: durationMs ?? this.durationMs,
    result: result ?? this.result,
    error: error ?? this.error,
  );
}

/// One message in the active conversation, materialised from events.
///
/// Instances are immutable snapshots; the client publishes a new list on every
/// change. Assistant text grows through [text] while [status] is
/// [KletsoMessageStatus.streaming].
@immutable
final class KletsoMessage {
  /// Creates a message.
  KletsoMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    this.text = '',
    this.status = KletsoMessageStatus.complete,
    this.turnId,
    this.clientId,
    this.value,
    List<KletsoSurface> surfaces = const <KletsoSurface>[],
    List<KletsoToolCall> toolCalls = const <KletsoToolCall>[],
    this.error,
    this.costMicros,
    this.latencyMs,
  }) : surfaces = List<KletsoSurface>.unmodifiable(surfaces),
       toolCalls = List<KletsoToolCall>.unmodifiable(toolCalls);

  /// Message id (`msg_…`), or the `clientId` while pending.
  final String id;

  /// Author.
  final KletsoRole role;

  /// Server timestamp of `message.created`, or local time while pending.
  final DateTime createdAt;

  /// Text so far.
  final String text;

  /// Delivery state.
  final KletsoMessageStatus status;

  /// Turn this message belongs to.
  final String? turnId;

  /// Client id for messages sent from this device.
  final String? clientId;

  /// Structured value for action/form-originated user turns.
  final Object? value;

  /// Surfaces rendered under this message, in arrival order.
  final List<KletsoSurface> surfaces;

  /// Tool calls made during this turn, in start order.
  final List<KletsoToolCall> toolCalls;

  /// Error when [status] is failed.
  final KletsoErrorEvent? error;

  /// Cost on the customer's key, once completed.
  final int? costMicros;

  /// Turn latency, once completed.
  final int? latencyMs;

  /// Whether this is an assistant message.
  bool get isAssistant => role == KletsoRole.assistant;

  /// Whether this is a user message.
  bool get isUser => role == KletsoRole.user;

  /// Returns a copy with the given fields replaced.
  KletsoMessage copyWith({
    String? id,
    String? text,
    KletsoMessageStatus? status,
    String? turnId,
    DateTime? createdAt,
    List<KletsoSurface>? surfaces,
    List<KletsoToolCall>? toolCalls,
    KletsoErrorEvent? error,
    int? costMicros,
    int? latencyMs,
  }) => KletsoMessage(
    id: id ?? this.id,
    role: role,
    createdAt: createdAt ?? this.createdAt,
    text: text ?? this.text,
    status: status ?? this.status,
    turnId: turnId ?? this.turnId,
    clientId: clientId,
    value: value,
    surfaces: surfaces ?? this.surfaces,
    toolCalls: toolCalls ?? this.toolCalls,
    error: error ?? this.error,
    costMicros: costMicros ?? this.costMicros,
    latencyMs: latencyMs ?? this.latencyMs,
  );

  @override
  String toString() =>
      'KletsoMessage($id, ${role.wire}, ${status.name}, '
      '${text.length} chars, ${surfaces.length} surfaces)';
}
