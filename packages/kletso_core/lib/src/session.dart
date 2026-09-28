import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

import 'config.dart';

/// Describes the device to the runtime when a session is created.
@immutable
final class KletsoDevice {
  /// Creates a device description.
  const KletsoDevice({
    required this.platform,
    this.sdk = 'kletso_core',
    this.version = '0.1.0',
    this.locale = 'en',
  });

  /// `android`, `ios`, `web`, `macos`, `windows`, `linux`, `fuchsia` or `test`.
  final String platform;

  /// SDK package name.
  final String sdk;

  /// SDK version.
  final String version;

  /// BCP-47 locale tag.
  final String locale;

  /// Wire form.
  JsonMap toJson() => <String, Object?>{
    'platform': platform,
    'sdk': sdk,
    'version': version,
    'locale': locale,
  };
}

/// A device session: the short-lived token that authorises realtime and REST
/// calls.
@immutable
final class KletsoSession {
  /// Creates a session.
  const KletsoSession({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  /// Reads a session from the bootstrap response.
  factory KletsoSession.fromJson(JsonMap json) => KletsoSession(
    id: json['id'] as String? ?? '',
    token: json['token'] as String? ?? '',
    expiresAt:
        DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  /// Session id (`ses_…`).
  final String id;

  /// Session token (`kst_…`); sent as the first frame / bearer token.
  final String token;

  /// Expiry, UTC.
  final DateTime expiresAt;

  /// Whether [expiresAt] is within [margin] of [now].
  bool expiresWithin(Duration margin, DateTime now) =>
      !expiresAt.isAfter(now.add(margin));

  /// Wire form.
  JsonMap toJson() => <String, Object?>{
    'id': id,
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

/// The end user the session belongs to.
@immutable
final class KletsoEndUser {
  /// Creates an end user.
  const KletsoEndUser({required this.id, required this.anonymous});

  /// Reads from the bootstrap response.
  factory KletsoEndUser.fromJson(JsonMap json) => KletsoEndUser(
    id: json['id'] as String? ?? '',
    anonymous: json['anonymous'] as bool? ?? true,
  );

  /// Kletso end-user id (`eu_…`).
  final String id;

  /// `true` when no host token was verified.
  final bool anonymous;
}

/// Public information about the agent serving the session.
@immutable
final class KletsoAgentInfo {
  /// Creates agent info.
  const KletsoAgentInfo({
    required this.id,
    required this.versionId,
    required this.name,
    this.greeting,
    this.allowedComponents = const <String>[],
  });

  /// Reads from the bootstrap response.
  factory KletsoAgentInfo.fromJson(JsonMap json) => KletsoAgentInfo(
    id: json['id'] as String? ?? '',
    versionId: json['versionId'] as String? ?? '',
    name: json['name'] as String? ?? 'Assistant',
    greeting: json['greeting'] as String?,
    allowedComponents:
        (json['allowedComponents'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[],
  );

  /// Agent id.
  final String id;

  /// Published version the environment points at.
  final String versionId;

  /// Display name.
  final String name;

  /// Opening message for new conversations.
  final String? greeting;

  /// Custom component types this agent may render; the renderer treats them
  /// as known (host-registered or fallback, never "unknown").
  final List<String> allowedComponents;
}

/// Everything `POST /v1/sessions` returns.
@immutable
final class KletsoSessionBootstrap {
  /// Creates a bootstrap.
  const KletsoSessionBootstrap({
    required this.session,
    required this.endUser,
    required this.agent,
    required this.realtimeUrl,
    this.theme = const <String, Object?>{},
    this.minClient,
    this.allowedUrlHosts = const <String>[],
  });

  /// Parses the response body. Throws [KletsoSchemaException] when the
  /// required objects are missing.
  factory KletsoSessionBootstrap.fromJson(Object? body) {
    if (body is! Map) {
      throw const KletsoSchemaException('session response is not an object');
    }
    final map = body.cast<String, Object?>();
    JsonMap section(String key) {
      final v = map[key];
      if (v is Map) return v.cast<String, Object?>();
      throw KletsoSchemaException('missing "$key"', path: '\$/$key');
    }

    final realtime = map['realtime'];
    final realtimeUrl = realtime is Map ? realtime['url'] as String? : null;
    return KletsoSessionBootstrap(
      session: KletsoSession.fromJson(section('session')),
      endUser: KletsoEndUser.fromJson(section('endUser')),
      agent: KletsoAgentInfo.fromJson(section('agent')),
      realtimeUrl: Uri.parse(realtimeUrl ?? 'wss://api.kletso.ai/v1/realtime'),
      theme: map['theme'] is Map
          ? (map['theme']! as Map).cast<String, Object?>()
          : const <String, Object?>{},
      minClient: map['minClient'] as String?,
      allowedUrlHosts:
          (map['allowedUrlHosts'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
    );
  }

  /// The session token and expiry.
  final KletsoSession session;

  /// The resolved end user.
  final KletsoEndUser endUser;

  /// The agent.
  final KletsoAgentInfo agent;

  /// Realtime endpoint (`wss://…/v1/realtime`).
  final Uri realtimeUrl;

  /// Branding for the client theme (see `docs/v1/04-ui-protocol.md` §6).
  final JsonMap theme;

  /// Minimum client version hint.
  final String? minClient;

  /// Hosts that `url` actions, links and images may point at.
  final List<String> allowedUrlHosts;

  /// Returns a copy with a new [session] (after refresh).
  KletsoSessionBootstrap withSession(KletsoSession session) =>
      KletsoSessionBootstrap(
        session: session,
        endUser: endUser,
        agent: agent,
        realtimeUrl: realtimeUrl,
        theme: theme,
        minClient: minClient,
        allowedUrlHosts: allowedUrlHosts,
      );
}

/// Marker so `KletsoEnvironment` shows up in the session request.
extension KletsoEnvironmentWire on KletsoEnvironment {
  /// The wire string.
  String get wire => name;
}
