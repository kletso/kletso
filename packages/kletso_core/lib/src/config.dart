import 'package:meta/meta.dart';

/// Which Kletso environment a session belongs to.
enum KletsoEnvironment {
  /// Published agent versions, real end users.
  production,

  /// Draft-adjacent environment for testing an integration.
  development,
}

/// How the SDK reaches the realtime endpoint.
enum KletsoTransportMode {
  /// WebSocket first; fall back to SSE for the session after two consecutive
  /// handshake failures.
  auto,

  /// WebSocket only.
  webSocket,

  /// Server-sent events for downstream, HTTP POST for upstream.
  sse,
}

/// Verbosity of the SDK log.
enum KletsoLogLevel {
  /// Every frame and state change.
  debug,

  /// Connection lifecycle and session events.
  info,

  /// Recoverable problems (reconnects, dropped frames).
  warning,

  /// Failures surfaced to the host.
  error,

  /// Nothing.
  none,
}

/// Immutable SDK configuration, passed once to `Kletso.init` or
/// `KletsoClient`.
@immutable
final class KletsoConfig {
  /// Creates a configuration.
  ///
  /// [publishableKey] must start with `kl_pub_`; secret keys (`kl_sec_`) are
  /// rejected because they must never ship inside an app.
  KletsoConfig({
    required this.publishableKey,
    required this.agentId,
    this.environment = KletsoEnvironment.production,
    this.transport = KletsoTransportMode.auto,
    Uri? baseUrl,
    this.logLevel = KletsoLogLevel.warning,
    this.heartbeatInterval = const Duration(seconds: 25),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 10),
    this.backoffBase = const Duration(milliseconds: 500),
    this.backoffCap = const Duration(seconds: 30),
    this.outboundQueueLimit = 100,
    this.typingIndicatorTtl = const Duration(seconds: 4),
    this.reportLocalActions = true,
    this.debugValidateUi = false,
    this.allowServerCommands = false,
  }) : baseUrl = baseUrl ?? defaultBaseUrl {
    if (!publishableKey.startsWith('kl_pub_')) {
      throw ArgumentError.value(
        publishableKey,
        'publishableKey',
        'must be a publishable key (kl_pub_…); never ship a secret key',
      );
    }
    if (agentId.isEmpty) {
      throw ArgumentError.value(agentId, 'agentId', 'must not be empty');
    }
  }

  /// `https://api.kletso.ai`.
  static final Uri defaultBaseUrl = Uri.parse('https://api.kletso.ai');

  /// Publishable key (`kl_pub_…`) that identifies the project + environment.
  final String publishableKey;

  /// Default agent for new conversations.
  final String agentId;

  /// Environment label sent with the session.
  final KletsoEnvironment environment;

  /// Realtime transport selection.
  final KletsoTransportMode transport;

  /// API origin; override for self-hosted or local runtimes.
  final Uri baseUrl;

  /// Minimum level that reaches the logger.
  final KletsoLogLevel logLevel;

  /// Interval between application-level pings.
  final Duration heartbeatInterval;

  /// How long to wait for a pong before closing and reconnecting.
  final Duration heartbeatTimeout;

  /// Handshake timeout for one connection attempt.
  final Duration connectTimeout;

  /// First reconnect delay (doubles with full jitter).
  final Duration backoffBase;

  /// Maximum reconnect delay.
  final Duration backoffCap;

  /// Frames buffered while the connection is not open; older ones are dropped
  /// with a `KletsoQueueOverflowException` once the limit is reached.
  final int outboundQueueLimit;

  /// How long `agent.typing` keeps the indicator on without a new event.
  final Duration typingIndicatorTtl;

  /// Whether `local` actions are reported to the runtime as `ui.action` for
  /// analytics (they still never leave the device otherwise).
  final bool reportLocalActions;

  /// Run full validation on every surface (slower; for development).
  final bool debugValidateUi;

  /// Let `app.command` events run host-registered local actions without a
  /// tap (agent-driven navigation). Off by default; only names the host
  /// registered can ever run.
  final bool allowServerCommands;

  /// `/v1` API root.
  Uri get apiRoot => baseUrl.replace(path: '/v1');

  /// Returns a copy with the given fields replaced.
  KletsoConfig copyWith({
    String? publishableKey,
    String? agentId,
    KletsoEnvironment? environment,
    KletsoTransportMode? transport,
    Uri? baseUrl,
    KletsoLogLevel? logLevel,
    Duration? heartbeatInterval,
    Duration? heartbeatTimeout,
    Duration? connectTimeout,
    Duration? backoffBase,
    Duration? backoffCap,
    int? outboundQueueLimit,
    Duration? typingIndicatorTtl,
    bool? reportLocalActions,
    bool? debugValidateUi,
    bool? allowServerCommands,
  }) => KletsoConfig(
    publishableKey: publishableKey ?? this.publishableKey,
    agentId: agentId ?? this.agentId,
    environment: environment ?? this.environment,
    transport: transport ?? this.transport,
    baseUrl: baseUrl ?? this.baseUrl,
    logLevel: logLevel ?? this.logLevel,
    heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
    heartbeatTimeout: heartbeatTimeout ?? this.heartbeatTimeout,
    connectTimeout: connectTimeout ?? this.connectTimeout,
    backoffBase: backoffBase ?? this.backoffBase,
    backoffCap: backoffCap ?? this.backoffCap,
    outboundQueueLimit: outboundQueueLimit ?? this.outboundQueueLimit,
    typingIndicatorTtl: typingIndicatorTtl ?? this.typingIndicatorTtl,
    reportLocalActions: reportLocalActions ?? this.reportLocalActions,
    debugValidateUi: debugValidateUi ?? this.debugValidateUi,
    allowServerCommands: allowServerCommands ?? this.allowServerCommands,
  );

  @override
  String toString() =>
      'KletsoConfig(agent: $agentId, env: ${environment.name}, '
      'transport: ${transport.name}, baseUrl: $baseUrl)';
}
