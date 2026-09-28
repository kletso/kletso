import 'package:meta/meta.dart';

import '../json_utils.dart';
import 'enums.dart';

/// Conversation metadata as carried by `conversation.*` events.
@immutable
final class KletsoConversationInfo {
  /// Creates conversation info.
  const KletsoConversationInfo({
    required this.id,
    required this.agentId,
    this.title,
    this.status = KletsoConversationStatus.open,
    this.createdAt,
    this.updatedAt,
    this.lastSeq = 0,
  });

  /// Reads conversation info; a `null` map yields empty ids.
  factory KletsoConversationInfo.fromJson(JsonMap? map) {
    final m = map ?? const <String, Object?>{};
    return KletsoConversationInfo(
      id: optionalString(m, 'id') ?? '',
      agentId: optionalString(m, 'agentId') ?? '',
      title: optionalString(m, 'title'),
      status: KletsoConversationStatus.parse(optionalString(m, 'status')),
      createdAt: DateTime.tryParse(optionalString(m, 'createdAt') ?? ''),
      updatedAt: DateTime.tryParse(optionalString(m, 'updatedAt') ?? ''),
      lastSeq: optionalInt(m, 'lastSeq') ?? 0,
    );
  }

  /// Conversation id (`conv_…`).
  final String id;

  /// The agent handling the conversation.
  final String agentId;

  /// Title shown in lists, if the runtime set one.
  final String? title;

  /// Lifecycle state.
  final KletsoConversationStatus status;

  /// Creation time.
  final DateTime? createdAt;

  /// Last update time.
  final DateTime? updatedAt;

  /// Highest `seq` in the log at the time of the event.
  final int lastSeq;

  /// Wire form.
  JsonMap toJson() => <String, Object?>{
    'id': id,
    'agentId': agentId,
    'title': title,
    'status': status.wire,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    'lastSeq': lastSeq,
  };
}
