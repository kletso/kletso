import 'package:clock/clock.dart';
import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import 'model/message.dart';

/// Reduces a conversation's event log into a message list. Pure with respect
/// to its inputs; one instance per conversation, kept by `KletsoClient` so
/// switching back to a conversation is instant.
final class KletsoConversationState {
  /// Creates an empty state for [conversationId].
  KletsoConversationState(this.conversationId);

  /// The conversation this state belongs to.
  final String conversationId;

  final List<KletsoMessage> _messages = <KletsoMessage>[];
  final Map<String, List<KletsoToolCall>> _turnTools =
      <String, List<KletsoToolCall>>{};
  final Map<String, String> _lastAssistantByTurn = <String, String>{};
  final Map<String, KletsoSurface> _pendingSurfacesByTurn =
      <String, KletsoSurface>{};
  int _lastSeq = 0;

  /// Messages in creation order.
  List<KletsoMessage> get messages =>
      List<KletsoMessage>.unmodifiable(_messages);

  /// Highest `seq` applied.
  int get lastSeq => _lastSeq;

  /// Adds an optimistic user message for an outbound with [clientId].
  void addPending(String clientId, String? text, Object? value) {
    _messages.add(
      KletsoMessage(
        id: clientId,
        role: KletsoRole.user,
        createdAt: clock.now().toUtc(),
        text: text ?? '',
        value: value,
        status: KletsoMessageStatus.pending,
        clientId: clientId,
      ),
    );
  }

  /// Marks the pending message with [clientId] as failed.
  void failPending(String clientId, KletsoErrorEvent error) {
    final i = _messages.indexWhere((m) => m.clientId == clientId);
    if (i == -1) return;
    _messages[i] = _messages[i].copyWith(
      status: KletsoMessageStatus.failed,
      error: error,
    );
  }

  /// Applies one envelope. Returns `true` when the message list changed.
  bool apply(KletsoEventEnvelope e) {
    if (e.seq > _lastSeq) _lastSeq = e.seq;
    final turnId = e.turnId ?? e.id;
    switch (e.payload) {
      case KletsoMessageCreated(
        :final messageId,
        :final role,
        :final text,
        :final value,
        :final clientId,
      ):
        final pending = clientId == null
            ? -1
            : _messages.indexWhere((m) => m.clientId == clientId);
        final created = KletsoMessage(
          id: messageId,
          role: role,
          createdAt: e.ts,
          text: text ?? '',
          value: value,
          turnId: e.turnId,
          clientId: clientId,
          status: role == KletsoRole.assistant
              ? KletsoMessageStatus.streaming
              : KletsoMessageStatus.complete,
          toolCalls: role == KletsoRole.assistant
              ? (_turnTools.remove(turnId) ?? const <KletsoToolCall>[])
              : const <KletsoToolCall>[],
          surfaces:
              role == KletsoRole.assistant &&
                  _pendingSurfacesByTurn.containsKey(turnId)
              ? <KletsoSurface>[_pendingSurfacesByTurn.remove(turnId)!]
              : const <KletsoSurface>[],
        );
        if (pending != -1) {
          // The server's order wins: drop the optimistic entry and append.
          _messages.removeAt(pending);
        }
        if (_messages.every((m) => m.id != messageId)) {
          _messages.add(created);
        }
        if (role == KletsoRole.assistant) {
          _lastAssistantByTurn[turnId] = messageId;
        }
        return true;
      case KletsoMessageDelta(:final messageId, :final text):
        return _update(
          messageId,
          (m) => m.copyWith(
            text: m.text + text,
            status: KletsoMessageStatus.streaming,
          ),
        );
      case KletsoMessageCompleted(
        :final messageId,
        :final text,
        :final costMicros,
        :final latencyMs,
      ):
        return _update(
          messageId,
          (m) => m.copyWith(
            text: text,
            status: KletsoMessageStatus.complete,
            costMicros: costMicros,
            latencyMs: latencyMs,
          ),
        );
      case KletsoToolStarted(:final toolCallId, :final name, :final args):
        final call = KletsoToolCall(
          id: toolCallId,
          name: name,
          args: args,
          status: KletsoToolCallStatus.running,
        );
        return _addToolCall(turnId, call);
      case KletsoToolConfirmationRequired(
        :final toolCallId,
        :final name,
        :final args,
      ):
        return _updateToolCall(
          turnId,
          toolCallId,
          () => KletsoToolCall(
            id: toolCallId,
            name: name,
            args: args,
            status: KletsoToolCallStatus.awaitingConfirmation,
          ),
          (c) => c.copyWith(status: KletsoToolCallStatus.awaitingConfirmation),
        );
      case KletsoToolFinished(
        :final toolCallId,
        :final name,
        :final durationMs,
        :final failed,
        :final result,
        :final errorMessage,
      ):
        return _updateToolCall(
          turnId,
          toolCallId,
          () => KletsoToolCall(
            id: toolCallId,
            name: name,
            status: failed
                ? KletsoToolCallStatus.failed
                : KletsoToolCallStatus.completed,
            durationMs: durationMs,
            result: result,
            error: errorMessage,
          ),
          (c) => c.copyWith(
            status: failed
                ? KletsoToolCallStatus.failed
                : KletsoToolCallStatus.completed,
            durationMs: durationMs,
            result: result,
            error: errorMessage,
          ),
        );
      case KletsoUiRender(:final rawSurface):
        final parsed = KletsoSurface.parseJson(rawSurface);
        if (parsed is! KletsoSurfaceOk) {
          // Rejected surfaces become a plain assistant line with the fallback.
          final fallback = parsed.fallbackText;
          if (fallback == null) return false;
          _messages.add(
            KletsoMessage(
              id: 'fallback_${e.id}',
              role: KletsoRole.assistant,
              createdAt: e.ts,
              text: fallback,
              turnId: e.turnId,
            ),
          );
          return true;
        }
        final target = _lastAssistantByTurn[turnId];
        if (target != null) {
          return _update(
            target,
            (m) => m.copyWith(
              surfaces: <KletsoSurface>[...m.surfaces, parsed.surface],
            ),
          );
        }
        // No assistant message yet in this turn: hold until message.created,
        // or attach to a synthetic message if the turn never creates one.
        _pendingSurfacesByTurn[turnId] = parsed.surface;
        _messages.add(
          KletsoMessage(
            id: 'surface_${parsed.surface.surfaceId}',
            role: KletsoRole.assistant,
            createdAt: e.ts,
            turnId: e.turnId,
            surfaces: <KletsoSurface>[parsed.surface],
          ),
        );
        _pendingSurfacesByTurn.remove(turnId);
        _lastAssistantByTurn[turnId] = 'surface_${parsed.surface.surfaceId}';
        return true;
      case KletsoUiPatch(
        :final surfaceId,
        :final data,
        components: final patchComponents,
      ):
        for (var i = 0; i < _messages.length; i++) {
          final idx = _messages[i].surfaces.indexWhere(
            (s) => s.surfaceId == surfaceId,
          );
          if (idx == -1) continue;
          try {
            final surfaces = List<KletsoSurface>.of(_messages[i].surfaces);
            surfaces[idx] = surfaces[idx].patched(
              data: data,
              components: patchComponents,
            );
            _messages[i] = _messages[i].copyWith(surfaces: surfaces);
            return true;
          } on KletsoSchemaException {
            return false; // a bad patch leaves the surface as it was
          }
        }
        return false;
      case KletsoErrorEvent():
        final target = _lastAssistantByTurn[turnId];
        if (target == null) return false;
        return _update(
          target,
          (m) => m.copyWith(
            status: KletsoMessageStatus.failed,
            error: e.payload as KletsoErrorEvent,
          ),
        );
      default:
        return false;
    }
  }

  bool _update(String messageId, KletsoMessage Function(KletsoMessage) fn) {
    final i = _messages.indexWhere((m) => m.id == messageId);
    if (i == -1) return false;
    _messages[i] = fn(_messages[i]);
    return true;
  }

  bool _addToolCall(String turnId, KletsoToolCall call) {
    final target = _lastAssistantByTurn[turnId];
    if (target != null) {
      return _update(
        target,
        (m) => m.copyWith(toolCalls: <KletsoToolCall>[...m.toolCalls, call]),
      );
    }
    (_turnTools[turnId] ??= <KletsoToolCall>[]).add(call);
    return false;
  }

  bool _updateToolCall(
    String turnId,
    String toolCallId,
    KletsoToolCall Function() create,
    KletsoToolCall Function(KletsoToolCall) fn,
  ) {
    // In a message already?
    for (var i = 0; i < _messages.length; i++) {
      final idx = _messages[i].toolCalls.indexWhere((c) => c.id == toolCallId);
      if (idx != -1) {
        final calls = List<KletsoToolCall>.of(_messages[i].toolCalls);
        calls[idx] = fn(calls[idx]);
        _messages[i] = _messages[i].copyWith(toolCalls: calls);
        return true;
      }
    }
    // Still buffered for the turn?
    final buffered = _turnTools[turnId];
    if (buffered != null) {
      final idx = buffered.indexWhere((c) => c.id == toolCallId);
      if (idx != -1) {
        buffered[idx] = fn(buffered[idx]);
        return false;
      }
    }
    return _addToolCall(turnId, create());
  }
}
