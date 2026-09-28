import 'dart:convert';

import '../events/envelope.dart';
import '../events/payload.dart';
import '../generated/embedded.g.dart';
import '../json_utils.dart';

/// Builds the canonical scripted conversation used by every fake: a
/// deterministic `kletso.events/v1` log with 20 messages that walks through
/// greeting, flight search with a rendered card, quick replies, a chart, a
/// hotel, product cards, a confirmed tool call and a human handoff.
///
/// `fixtures/events/conversation_20.json` is this script serialized; the
/// fake transport and the mock server replay it frame by frame.
final class KletsoConversationScript {
  /// Creates a script for [conversationId] starting at [start].
  KletsoConversationScript({
    this.conversationId = 'conv_01J8DEMO000001',
    this.agentId = 'agt_01J8ACME00001',
    DateTime? start,
    this.stepMillis = 350,
  }) : start = start ?? DateTime.utc(2026, 9, 28, 12);

  /// Conversation every event belongs to.
  final String conversationId;

  /// Agent handling the conversation.
  final String agentId;

  /// Timestamp of `seq` 1; each later event is [stepMillis] later.
  final DateTime start;

  /// Milliseconds between consecutive events.
  final int stepMillis;

  final List<KletsoEventEnvelope> _events = <KletsoEventEnvelope>[];
  int _messages = 0;
  int _turns = 0;
  int _calls = 0;

  /// The full event log.
  List<KletsoEventEnvelope> build() {
    if (_events.isNotEmpty) {
      return List<KletsoEventEnvelope>.unmodifiable(_events);
    }
    _conversationCreated();
    _assistantTurn(
      'Hi! I\'m Acme\'s assistant. I can find flights and hotels, show your sales, or help with an order. What do you need?',
    );
    _userTurn('I need a flight from Tokyo to Osaka tomorrow morning');
    _assistantTurn(
      'Here\'s the best option for tomorrow morning:',
      tool: _Tool(
        'search_flights',
        <String, Object?>{
          'from': 'TYO',
          'to': 'OSA',
          'date': '2026-09-29',
          'window': 'morning',
        },
        result: <String, Object?>{'count': 6, 'best': 'NH873'},
      ),
      surface: KletsoFixtures.flightCard,
    );
    _userAction(
      surfaceId: 'sfc_01J8FLIGHT0001',
      componentId: 'select',
      actionId: 'select',
      value: <String, Object?>{
        'intent': 'select_flight',
        'flightId': 'NH873-2026-09-29',
      },
      label: 'Select ANA NH873',
    );
    _assistantTurn(
      'Great choice. NH873 is held for 20 minutes. Anything else I can do?',
      surface: KletsoFixtures.quickReplies,
    );
    _userTurn('Show me sales');
    _assistantTurn(
      'Sales are up this month. Here\'s the weekly picture:',
      tool: _Tool(
        'get_sales',
        <String, Object?>{'period': '2026-09', 'groupBy': 'week'},
        result: <String, Object?>{'total': 61950, 'currency': 'USD'},
      ),
      surface: KletsoFixtures.chart,
    );
    _userTurn('Break down by product');
    _assistantTurn(
      'By product this month:\n\n1. **Trail Runner 2** — \$24,300\n2. **Everyday Tote** — \$18,650\n3. **Steel Bottle 750** — \$11,200\n4. Everything else — \$7,800',
    );
    _userTurn('Also find me a hotel in Shibuya');
    _assistantTurn(
      'This one is a strong match near the station:',
      tool: _Tool(
        'search_hotels',
        <String, Object?>{'area': 'Shibuya', 'nights': 2},
        result: <String, Object?>{'count': 12, 'best': 'h_1'},
      ),
      surface: KletsoFixtures.hotelCard,
    );
    _userTurn('Show me products under 2000');
    _assistantTurn(
      'Here is what I found in the catalogue:',
      tool: _Tool(
        'search_products',
        <String, Object?>{'maxPrice': 2000, 'currency': 'INR'},
        result: <String, Object?>{'count': 3},
      ),
      surface: KletsoFixtures.productCards,
    );
    _userTurn('Cancel my order ORD-4521');
    _assistantConfirmation(
      'I can cancel ORD-4521. Please confirm:',
      toolName: 'cancel_order',
      args: <String, Object?>{'orderId': 'ORD-4521'},
      surface: KletsoFixtures.confirm,
    );
    _userAction(
      surfaceId: 'sfc_01J8CONFIRM001',
      componentId: 'confirm',
      actionId: 'yes',
      value: <String, Object?>{
        'toolCallId': 'call_01J8CANCEL0001',
        'approve': true,
      },
      label: 'Yes, cancel order',
    );
    _assistantTurn(
      'Done. Order ORD-4521 is cancelled and ₹3,499 will be refunded within 5–7 days.',
      toolCompletion: _Tool(
        'cancel_order',
        <String, Object?>{'orderId': 'ORD-4521'},
        result: <String, Object?>{'status': 'cancelled', 'refund': 3499},
        callId: 'call_01J8CANCEL0001',
      ),
    );
    _userTurn('I\'d like to talk to a human');
    _assistantTurn(
      'Of course. I\'m connecting you with the Acme support team now; they have the full context of this chat.',
      handoff: true,
    );
    _userTurn('Thank you!');
    return List<KletsoEventEnvelope>.unmodifiable(_events);
  }

  /// The log as JSON text, one envelope per array element.
  String toJsonString() => const JsonEncoder.withIndent(
    '  ',
  ).convert(build().map((e) => e.toJson()).toList(growable: false));

  // ---- internals ------------------------------------------------------------

  String _turnId() => 'trn_01J8TURN${(++_turns).toString().padLeft(6, '0')}';
  String _messageId() =>
      'msg_01J8MSG${(++_messages).toString().padLeft(7, '0')}';
  String _callId() => 'call_01J8CALL${(++_calls).toString().padLeft(6, '0')}';

  void _emit(String type, JsonMap data, {String? turnId}) {
    final seq = _events.length + 1;
    _events.add(
      KletsoEventEnvelope(
        id: 'evt_01J8EVENT${seq.toString().padLeft(5, '0')}',
        seq: seq,
        type: type,
        ts: start.add(Duration(milliseconds: (seq - 1) * stepMillis)),
        conversationId: conversationId,
        turnId: turnId,
        data: data,
      ),
    );
  }

  void _conversationCreated() {
    _emit(KletsoEventTypes.conversationCreated, <String, Object?>{
      'conversation': <String, Object?>{
        'id': conversationId,
        'agentId': agentId,
        'title': null,
        'status': 'open',
        'createdAt': start.toIso8601String(),
        'updatedAt': start.toIso8601String(),
        'lastSeq': 0,
      },
    });
  }

  void _userTurn(String text) {
    final turnId = _turnId();
    _emit(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': _messageId(),
      'role': 'user',
      'text': text,
      'clientId': 'c_01J8CLIENT${_messages.toString().padLeft(4, '0')}',
    }, turnId: turnId);
  }

  void _userAction({
    required String surfaceId,
    required String componentId,
    required String actionId,
    required JsonMap value,
    required String label,
  }) {
    final turnId = _turnId();
    _emit(KletsoEventTypes.uiAction, <String, Object?>{
      'surfaceId': surfaceId,
      'componentId': componentId,
      'actionId': actionId,
      'value': value,
    }, turnId: turnId);
    _emit(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': _messageId(),
      'role': 'user',
      'text': label,
      'value': value,
      'clientId': 'c_01J8CLIENT${_messages.toString().padLeft(4, '0')}',
    }, turnId: turnId);
  }

  void _assistantTurn(
    String text, {
    _Tool? tool,
    _Tool? toolCompletion,
    Object? surface,
    bool handoff = false,
  }) {
    final turnId = _turnId();
    final messageId = _messageId();
    _emit(
      KletsoEventTypes.agentTyping,
      const <String, Object?>{},
      turnId: turnId,
    );
    if (toolCompletion != null) {
      _emit(KletsoEventTypes.toolCompleted, <String, Object?>{
        'toolCallId': toolCompletion.callId ?? _callId(),
        'name': toolCompletion.name,
        'durationMs': 640,
        'result': toolCompletion.result,
      }, turnId: turnId);
    }
    if (tool != null) {
      final callId = tool.callId ?? _callId();
      _emit(KletsoEventTypes.toolStarted, <String, Object?>{
        'toolCallId': callId,
        'name': tool.name,
        'args': tool.args,
      }, turnId: turnId);
      _emit(KletsoEventTypes.toolCompleted, <String, Object?>{
        'toolCallId': callId,
        'name': tool.name,
        'durationMs': 820,
        'result': tool.result,
      }, turnId: turnId);
    }
    _emit(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': messageId,
      'role': 'assistant',
      'text': '',
    }, turnId: turnId);
    for (final chunk in _chunks(text)) {
      _emit(KletsoEventTypes.messageDelta, <String, Object?>{
        'messageId': messageId,
        'text': chunk,
      }, turnId: turnId);
    }
    if (surface != null) {
      _emit(KletsoEventTypes.uiRender, <String, Object?>{
        'surface': surface,
      }, turnId: turnId);
    }
    _emit(KletsoEventTypes.messageCompleted, <String, Object?>{
      'messageId': messageId,
      'text': text,
      'usage': <String, Object?>{
        'in': 1200 + text.length,
        'out': text.length ~/ 4 + 20,
        'cachedIn': 900,
        'reasoning': 0,
      },
      'costMicros': 1850,
      'latencyMs': 1400,
      'finishReason': 'stop',
    }, turnId: turnId);
    if (handoff) {
      _emit(KletsoEventTypes.handoffStarted, <String, Object?>{
        'target': 'inbox',
        'agentName': 'Acme support',
      }, turnId: turnId);
      _emit(KletsoEventTypes.conversationUpdated, <String, Object?>{
        'conversation': <String, Object?>{
          'id': conversationId,
          'agentId': agentId,
          'title': 'Flight, hotel and order help',
          'status': 'handoff',
          'createdAt': start.toIso8601String(),
          'updatedAt': start
              .add(Duration(milliseconds: _events.length * stepMillis))
              .toIso8601String(),
          'lastSeq': _events.length + 1,
        },
      }, turnId: turnId);
    }
  }

  void _assistantConfirmation(
    String text, {
    required String toolName,
    required JsonMap args,
    required Object? surface,
  }) {
    final turnId = _turnId();
    final messageId = _messageId();
    _emit(
      KletsoEventTypes.agentTyping,
      const <String, Object?>{},
      turnId: turnId,
    );
    _emit(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': messageId,
      'role': 'assistant',
      'text': '',
    }, turnId: turnId);
    for (final chunk in _chunks(text)) {
      _emit(KletsoEventTypes.messageDelta, <String, Object?>{
        'messageId': messageId,
        'text': chunk,
      }, turnId: turnId);
    }
    _emit(KletsoEventTypes.messageCompleted, <String, Object?>{
      'messageId': messageId,
      'text': text,
      'usage': <String, Object?>{'in': 1300, 'out': 40, 'cachedIn': 900},
      'costMicros': 900,
      'latencyMs': 900,
      'finishReason': 'tool_calls',
    }, turnId: turnId);
    _emit(KletsoEventTypes.toolStarted, <String, Object?>{
      'toolCallId': 'call_01J8CANCEL0001',
      'name': toolName,
      'args': args,
    }, turnId: turnId);
    _emit(KletsoEventTypes.toolConfirmationRequired, <String, Object?>{
      'toolCallId': 'call_01J8CANCEL0001',
      'name': toolName,
      'args': args,
      'surface': surface,
    }, turnId: turnId);
    _emit(KletsoEventTypes.uiRender, <String, Object?>{
      'surface': surface,
    }, turnId: turnId);
  }

  /// Splits [text] into word-ish chunks of roughly 12 characters so streaming
  /// looks real without depending on a tokenizer.
  static List<String> _chunks(String text) {
    final out = <String>[];
    final words = text.split(' ');
    final buf = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      buf.write(words[i]);
      if (i < words.length - 1) buf.write(' ');
      if (buf.length >= 12 || i == words.length - 1) {
        out.add(buf.toString());
        buf.clear();
      }
    }
    return out;
  }
}

final class _Tool {
  const _Tool(this.name, this.args, {this.result, this.callId});
  final String name;
  final JsonMap args;
  final Object? result;
  final String? callId;
}
