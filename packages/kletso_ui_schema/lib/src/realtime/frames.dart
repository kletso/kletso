import 'package:meta/meta.dart';

import '../errors.dart';
import '../events/envelope.dart';
import '../json_utils.dart';
import 'binary.dart';

/// WebSocket close codes the runtime uses.
abstract final class KletsoCloseCodes {
  /// Normal closure.
  static const int normal = 1000;

  /// Endpoint going away (deploy, tab closed).
  static const int goingAway = 1001;

  /// Client closed because no `pong` arrived in time.
  static const int heartbeatTimeout = 4000;

  /// Authentication failed; do not retry with the same token.
  static const int authFailed = 4401;

  /// Session token expired; refresh, then reconnect.
  static const int tokenExpired = 4403;
}

/// A frame the client sends to the runtime.
@immutable
sealed class KletsoClientFrame {
  const KletsoClientFrame();

  /// Parses a client frame; used by mock servers and tests. Throws
  /// [KletsoSchemaException] for unknown or malformed frames.
  factory KletsoClientFrame.fromJson(Object? json, {String path = r'$'}) {
    final map = requireMap(json, path);
    final t = requireString(map, 't', path);
    switch (t) {
      case 'auth':
        return KletsoAuthFrame(
          token: requireString(map, 'token', path),
          conversationId: optionalString(map, 'conversationId'),
          after: optionalInt(map, 'after') ?? 0,
        );
      case 'message':
        return KletsoMessageFrame(
          clientId: requireString(map, 'clientId', path),
          text: optionalString(map, 'text'),
          value: map['value'],
        );
      case 'action':
        return KletsoActionFrame(
          surfaceId: requireString(map, 'surfaceId', path),
          componentId: requireString(map, 'componentId', path),
          actionId: requireString(map, 'actionId', path),
          clientId: requireString(map, 'clientId', path),
          value: map['value'],
        );
      case 'context':
        final merge = optionalMap(map, 'merge');
        final replace = optionalMap(map, 'replace');
        if ((merge == null) == (replace == null)) {
          throw KletsoSchemaException(
            'context frame needs exactly one of "merge" or "replace"',
            path: path,
          );
        }
        return merge != null
            ? KletsoContextFrame.merge(merge)
            : KletsoContextFrame.replace(replace!);
      case 'track':
        return KletsoTrackFrame(
          name: requireString(map, 'name', path),
          properties: freezeMap(optionalMap(map, 'properties')),
        );
      case 'screen':
        return KletsoScreenFrame(name: requireString(map, 'name', path));
      case 'switch':
        return KletsoSwitchFrame(
          conversationId: requireString(map, 'conversationId', path),
          after: optionalInt(map, 'after') ?? 0,
        );
      case 'typing':
        return const KletsoTypingFrame();
      case 'ping':
        return const KletsoPingFrame();
      case 'voice.start':
        return KletsoVoiceStartFrame(
          clientId: requireString(map, 'clientId', path),
          mode: KletsoVoiceMode.parse(optionalString(map, 'mode')),
          sampleRate: optionalInt(map, 'sampleRate') ?? 24000,
        );
      case 'voice.stop':
        return KletsoVoiceStopFrame(
          reason: KletsoVoiceStopReason.parse(optionalString(map, 'reason')),
        );
      case 'voice.commit':
        return const KletsoVoiceCommitFrame();
      case 'voice.played':
        return KletsoVoicePlayedFrame(
          itemId: requireString(map, 'itemId', path),
          ms: requireInt(map, 'ms', path),
        );
      case 'voice.text':
        return KletsoVoiceTextFrame(text: requireString(map, 'text', path));
      default:
        throw KletsoSchemaException(
          'unknown client frame "$t"',
          path: '$path/t',
        );
    }
  }

  /// The wire discriminator.
  String get t;

  /// Wire form.
  JsonMap toJson();

  @override
  bool operator ==(Object other) =>
      other is KletsoClientFrame &&
      other.runtimeType == runtimeType &&
      jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(runtimeType, t);

  @override
  String toString() => '$runtimeType(${toJson()})';
}

/// First frame after the socket opens; carries the session token.
final class KletsoAuthFrame extends KletsoClientFrame {
  /// Creates an auth frame.
  const KletsoAuthFrame({
    required this.token,
    this.conversationId,
    this.after = 0,
  });

  /// Session token (`kst_…`). Never put it in the URL.
  final String token;

  /// Conversation to attach to, or `null` to attach later with `switch`.
  final String? conversationId;

  /// Last `seq` the client has; the server replays everything after it.
  final int after;

  @override
  String get t => 'auth';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'token': token,
    if (conversationId != null) 'conversationId': conversationId,
    'after': after,
  };
}

/// A user message.
final class KletsoMessageFrame extends KletsoClientFrame {
  /// Creates a message frame.
  const KletsoMessageFrame({required this.clientId, this.text, this.value});

  /// Client-assigned id; the server dedupes on it after reconnects.
  final String clientId;

  /// Plain text, or `null` for value-only turns.
  final String? text;

  /// Structured value (quick replies, form results).
  final Object? value;

  @override
  String get t => 'message';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'text': text,
    'value': value,
    'clientId': clientId,
  };
}

/// A non-local action taken on a surface.
final class KletsoActionFrame extends KletsoClientFrame {
  /// Creates an action frame.
  const KletsoActionFrame({
    required this.surfaceId,
    required this.componentId,
    required this.actionId,
    required this.clientId,
    this.value,
  });

  /// Surface the action belongs to.
  final String surfaceId;

  /// Component that carries the action.
  final String componentId;

  /// Action id.
  final String actionId;

  /// Client-assigned id for dedupe.
  final String clientId;

  /// Action-specific value (agent value, form values, confirm answer).
  final Object? value;

  @override
  String get t => 'action';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'surfaceId': surfaceId,
    'componentId': componentId,
    'actionId': actionId,
    if (value != null) 'value': value,
    'clientId': clientId,
  };
}

/// Runtime context change: either merge keys into the current context or
/// replace it wholesale. Exactly one of [merge] or [replace] is set.
final class KletsoContextFrame extends KletsoClientFrame {
  const KletsoContextFrame._({this.merge, this.replace})
    : assert(
        (merge == null) != (replace == null),
        'exactly one of merge or replace must be set',
      );

  /// Merges [keys] into the current context (`PATCH` semantics).
  const KletsoContextFrame.merge(JsonMap keys) : this._(merge: keys);

  /// Replaces the whole context with [context] (`PUT` semantics).
  const KletsoContextFrame.replace(JsonMap context) : this._(replace: context);

  /// Keys to merge into the current context.
  final JsonMap? merge;

  /// Full replacement context.
  final JsonMap? replace;

  @override
  String get t => 'context';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    if (merge != null) 'merge': merge,
    if (replace != null) 'replace': replace,
  };
}

/// Event trigger.
final class KletsoTrackFrame extends KletsoClientFrame {
  /// Creates a track frame.
  const KletsoTrackFrame({
    required this.name,
    this.properties = const <String, Object?>{},
  });

  /// Event name, e.g. `cart_abandoned`.
  final String name;

  /// Event properties.
  final JsonMap properties;

  @override
  String get t => 'track';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'name': name,
    if (properties.isNotEmpty) 'properties': properties,
  };
}

/// Screen trigger.
final class KletsoScreenFrame extends KletsoClientFrame {
  /// Creates a screen frame.
  const KletsoScreenFrame({required this.name});

  /// Screen name, e.g. `checkout`.
  final String name;

  @override
  String get t => 'screen';

  @override
  JsonMap toJson() => <String, Object?>{'t': t, 'name': name};
}

/// Attach the socket to another conversation.
final class KletsoSwitchFrame extends KletsoClientFrame {
  /// Creates a switch frame.
  const KletsoSwitchFrame({required this.conversationId, this.after = 0});

  /// Conversation to attach to.
  final String conversationId;

  /// Replay cursor for that conversation.
  final int after;

  @override
  String get t => 'switch';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'conversationId': conversationId,
    'after': after,
  };
}

/// The user is typing.
final class KletsoTypingFrame extends KletsoClientFrame {
  /// Creates a typing frame.
  const KletsoTypingFrame();

  @override
  String get t => 'typing';

  @override
  JsonMap toJson() => const <String, Object?>{'t': 'typing'};
}

/// Application-level heartbeat.
final class KletsoPingFrame extends KletsoClientFrame {
  /// Creates a ping frame.
  const KletsoPingFrame();

  @override
  String get t => 'ping';

  @override
  JsonMap toJson() => const <String, Object?>{'t': 'ping'};
}

/// Turn-taking mode of a voice session.
enum KletsoVoiceMode {
  /// The model detects when the user starts and stops speaking.
  vad('vad'),

  /// Push-to-talk: the client sends `voice.commit` when the user releases.
  ptt('ptt');

  const KletsoVoiceMode(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [vad].
  static KletsoVoiceMode parse(String? value) =>
      values.firstWhere((m) => m.wire == value, orElse: () => vad);
}

/// Why the client stops a voice session.
enum KletsoVoiceStopReason {
  /// The user tapped End.
  user('user'),

  /// The app went to the background.
  background('background');

  const KletsoVoiceStopReason(this.wire);

  /// The wire string.
  final String wire;

  /// Parses [value]; anything unrecognised is [user].
  static KletsoVoiceStopReason parse(String? value) =>
      values.firstWhere((r) => r.wire == value, orElse: () => user);
}

/// Opens a voice session on the attached conversation. Audio then travels as
/// binary frames (see [KletsoAudioFrame]).
final class KletsoVoiceStartFrame extends KletsoClientFrame {
  /// Creates a voice.start frame.
  const KletsoVoiceStartFrame({
    required this.clientId,
    this.mode = KletsoVoiceMode.vad,
    this.sampleRate = 24000,
  });

  /// Client-assigned id for dedupe after reconnects.
  final String clientId;

  /// Turn-taking mode.
  final KletsoVoiceMode mode;

  /// Sample rate of the PCM the client sends and expects (24 kHz only).
  final int sampleRate;

  @override
  String get t => 'voice.start';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'mode': mode.wire,
    'sampleRate': sampleRate,
    'clientId': clientId,
  };
}

/// Ends the voice session.
final class KletsoVoiceStopFrame extends KletsoClientFrame {
  /// Creates a voice.stop frame.
  const KletsoVoiceStopFrame({this.reason = KletsoVoiceStopReason.user});

  /// Why.
  final KletsoVoiceStopReason reason;

  @override
  String get t => 'voice.stop';

  @override
  JsonMap toJson() => <String, Object?>{'t': t, 'reason': reason.wire};
}

/// Push-to-talk release: the buffered audio is one utterance, answer it.
final class KletsoVoiceCommitFrame extends KletsoClientFrame {
  /// Creates a voice.commit frame.
  const KletsoVoiceCommitFrame();

  @override
  String get t => 'voice.commit';

  @override
  JsonMap toJson() => const <String, Object?>{'t': 'voice.commit'};
}

/// Playback progress of an assistant audio item, so the runtime can cut the
/// model's transcript where the user interrupted.
final class KletsoVoicePlayedFrame extends KletsoClientFrame {
  /// Creates a voice.played frame.
  const KletsoVoicePlayedFrame({required this.itemId, required this.ms});

  /// Assistant audio item.
  final String itemId;

  /// Milliseconds of it played so far.
  final int ms;

  @override
  String get t => 'voice.played';

  @override
  JsonMap toJson() => <String, Object?>{'t': t, 'itemId': itemId, 'ms': ms};
}

/// Typed text during a voice session; routed to the voice model, not the
/// text agent.
final class KletsoVoiceTextFrame extends KletsoClientFrame {
  /// Creates a voice.text frame.
  const KletsoVoiceTextFrame({required this.text});

  /// The text.
  final String text;

  @override
  String get t => 'voice.text';

  @override
  JsonMap toJson() => <String, Object?>{'t': t, 'text': text};
}

/// A frame the runtime sends to the client.
@immutable
sealed class KletsoServerFrame {
  const KletsoServerFrame();

  /// Parses a server frame. Throws [KletsoSchemaException] for malformed
  /// frames; unknown `t` values become [KletsoUnknownServerFrame].
  factory KletsoServerFrame.fromJson(Object? json, {String path = r'$'}) {
    final map = requireMap(json, path);
    final t = requireString(map, 't', path);
    switch (t) {
      case 'ready':
        return KletsoReadyFrame(
          seq: requireInt(map, 'seq', path),
          conversationId: optionalString(map, 'conversationId'),
        );
      case 'pong':
        return const KletsoPongFrame();
      case 'event':
        return KletsoEventFrame(
          KletsoEventEnvelope.fromJson(map['event'], path: '$path/event'),
        );
      case 'error':
        return KletsoErrorFrame(
          code: requireString(map, 'code', path),
          message: requireString(map, 'message', path),
          retryable: optionalBool(map, 'retryable') ?? false,
          retryAfterMs: optionalInt(map, 'retryAfterMs'),
        );
      default:
        return KletsoUnknownServerFrame(t, freezeMap(map));
    }
  }

  /// The wire discriminator.
  String get t;

  /// Wire form.
  JsonMap toJson();

  @override
  bool operator ==(Object other) =>
      other is KletsoServerFrame &&
      other.runtimeType == runtimeType &&
      jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(runtimeType, t);

  @override
  String toString() => '$runtimeType(${toJson()})';
}

/// Auth accepted; the client may send. [seq] is the server's current cursor
/// for the attached conversation.
final class KletsoReadyFrame extends KletsoServerFrame {
  /// Creates a ready frame.
  const KletsoReadyFrame({required this.seq, this.conversationId});

  /// Highest `seq` the server holds for the attached conversation.
  final int seq;

  /// Attached conversation, when one was requested.
  final String? conversationId;

  @override
  String get t => 'ready';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'seq': seq,
    if (conversationId != null) 'conversationId': conversationId,
  };
}

/// Heartbeat reply.
final class KletsoPongFrame extends KletsoServerFrame {
  /// Creates a pong frame.
  const KletsoPongFrame();

  @override
  String get t => 'pong';

  @override
  JsonMap toJson() => const <String, Object?>{'t': 'pong'};
}

/// An event envelope.
final class KletsoEventFrame extends KletsoServerFrame {
  /// Creates an event frame.
  const KletsoEventFrame(this.event);

  /// The event.
  final KletsoEventEnvelope event;

  @override
  String get t => 'event';

  @override
  JsonMap toJson() => <String, Object?>{'t': t, 'event': event.toJson()};
}

/// A non-fatal error on the connection (fatal ones close the socket).
final class KletsoErrorFrame extends KletsoServerFrame {
  /// Creates an error frame.
  const KletsoErrorFrame({
    required this.code,
    required this.message,
    this.retryable = false,
    this.retryAfterMs,
  });

  /// Error code from the API vocabulary (`rate_limited`, `invalid_request`…).
  final String code;

  /// Human-readable message.
  final String message;

  /// Whether the client may retry the failed frame.
  final bool retryable;

  /// Suggested wait before retrying, for `rate_limited`.
  final int? retryAfterMs;

  @override
  String get t => 'error';

  @override
  JsonMap toJson() => <String, Object?>{
    't': t,
    'code': code,
    'message': message,
    'retryable': retryable,
    if (retryAfterMs != null) 'retryAfterMs': retryAfterMs,
  };
}

/// A server frame this client does not know; ignored by the SDK.
final class KletsoUnknownServerFrame extends KletsoServerFrame {
  /// Creates an unknown frame wrapping [raw].
  const KletsoUnknownServerFrame(this.t, this.raw);

  @override
  final String t;

  /// The original wire object.
  final JsonMap raw;

  @override
  JsonMap toJson() => raw;
}
