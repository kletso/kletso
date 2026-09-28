import 'package:meta/meta.dart';

import '../errors.dart';
import '../json_utils.dart';
import 'payload.dart';

/// One `kletso.events/v1` event as it appears in a conversation log, a
/// realtime `event` frame or a webhook batch.
///
/// [seq] is monotonic per conversation and is the replay cursor. [data] is
/// kept as decoded JSON; [payload] gives a typed view for the types this
/// package knows about and [KletsoUnknownEvent] for everything else.
@immutable
final class KletsoEventEnvelope {
  /// Creates an envelope.
  KletsoEventEnvelope({
    required this.id,
    required this.seq,
    required this.type,
    required this.ts,
    required this.conversationId,
    JsonMap data = const <String, Object?>{},
    this.turnId,
  }) : data = freezeMap(data);

  /// Parses an envelope. Throws [KletsoSchemaException] when a required field
  /// is missing or has the wrong type; unknown [type]s are accepted.
  factory KletsoEventEnvelope.fromJson(Object? json, {String path = r'$'}) {
    final map = requireMap(json, path);
    final tsRaw = requireString(map, 'ts', path);
    final ts = DateTime.tryParse(tsRaw);
    if (ts == null) {
      throw KletsoSchemaException(
        '"ts" is not an ISO-8601 timestamp',
        path: '$path/ts',
      );
    }
    final rawData = map['data'];
    if (rawData != null && rawData is! Map) {
      throw KletsoSchemaException(
        '"data" must be an object',
        path: '$path/data',
      );
    }
    return KletsoEventEnvelope(
      id: requireString(map, 'id', path),
      seq: requireInt(map, 'seq', path),
      type: requireString(map, 'type', path),
      ts: ts.toUtc(),
      conversationId: requireString(map, 'conversationId', path),
      turnId: optionalString(map, 'turnId'),
      data: rawData == null
          ? const <String, Object?>{}
          : (rawData as Map).cast<String, Object?>(),
    );
  }

  /// Globally unique event id (`evt_…`); dedupe on this.
  final String id;

  /// Position in the conversation log, starting at 1.
  final int seq;

  /// Dotted event type, e.g. `message.delta`.
  final String type;

  /// Server timestamp, UTC.
  final DateTime ts;

  /// Conversation the event belongs to.
  final String conversationId;

  /// Turn the event belongs to, when it is part of one.
  final String? turnId;

  /// Type-specific data, unmodifiable.
  final JsonMap data;

  /// Typed view of [data]; computed once, never throws.
  late final KletsoEventPayload payload = KletsoEventPayload.fromEnvelope(this);

  /// Wire form.
  JsonMap toJson() => <String, Object?>{
    'id': id,
    'seq': seq,
    'type': type,
    'ts': ts.toIso8601String(),
    'conversationId': conversationId,
    if (turnId != null) 'turnId': turnId,
    'data': data,
  };

  @override
  bool operator ==(Object other) =>
      other is KletsoEventEnvelope && jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(id, seq, type);

  @override
  String toString() => 'KletsoEventEnvelope(#$seq $type $id)';
}
