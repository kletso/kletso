import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import 'api/api.dart';
import 'api/http_api.dart';
import 'config.dart';
import 'connection/connection.dart';
import 'connection/connection_state.dart';
import 'conversation_state.dart';
import 'events.dart';
import 'exceptions.dart';
import 'ids.dart';
import 'log.dart';
import 'model/conversation.dart';
import 'model/message.dart';
import 'model/notification.dart';
import 'outbound.dart';
import 'session.dart';
import 'token_store.dart';
import 'transport/auto_transport.dart';
import 'transport/sse_transport.dart';
import 'transport/transport.dart';
import 'transport/web_socket_transport.dart';
import 'value_listenable.dart';

/// Names of the silent app events the SDK sends on its own.
abstract final class KletsoEvents {
  /// Sent by `open()` when the chat is shown; trigger rules of kind
  /// "opens the chat" react to it.
  static const String chatOpened = 'kletso.chat_opened';
}

/// Returns a fresh host-signed user token when the current one expired.
typedef KletsoUserTokenRefresher = Future<String?> Function();

/// The Kletso client: one per app (through `Kletso.init`) or one per test.
///
/// Owns the session, the realtime [KletsoConnection], the per-conversation
/// state and the public observables. Everything is exposed as
/// [KletsoValueListenable]s and one broadcast [events] stream so hosts can
/// wrap it in whatever state library they use.
final class KletsoClient {
  /// Creates a client. All dependencies are injectable: [api] and
  /// [transport] for fakes, [httpClient] for `MockClient` (used only when
  /// [api] or [transport] are not supplied), [random] for deterministic ids
  /// and backoff, [logger] for log capture, [tokenStore] to persist the
  /// anonymous visitor id.
  KletsoClient(
    this.config, {
    KletsoApi? api,
    KletsoTransport? transport,
    http.Client? httpClient,
    Random? random,
    KletsoLogger? logger,
    KletsoDevice? device,
    KletsoTokenStore? tokenStore,
  }) : _log = KletsoLog(config.logLevel, logger),
       _ids = KletsoIdGenerator(random: random),
       _random = random,
       _device = device ?? const KletsoDevice(platform: 'dart'),
       _tokenStore = tokenStore ?? KletsoMemoryTokenStore() {
    final httpClientOrNull = httpClient;
    _api = api ?? KletsoHttpApi(config, client: httpClientOrNull);
    _ownsApi = api == null;
    _transport = transport ?? _defaultTransport(httpClientOrNull);
    _activeAgentId = config.agentId;
  }

  /// The configuration this client was created with.
  final KletsoConfig config;

  final KletsoLog _log;
  final KletsoIdGenerator _ids;
  final Random? _random;
  final KletsoDevice _device;
  final KletsoTokenStore _tokenStore;
  late final KletsoApi _api;
  late final bool _ownsApi;
  late final KletsoTransport _transport;
  late String _activeAgentId;

  static const String _anonymousKey = 'kletso.anonymousId';

  KletsoSessionBootstrap? _bootstrap;
  String? _userToken;
  KletsoUserTokenRefresher? _onUserTokenExpired;
  KletsoConnection? _connection;
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  final Map<String, KletsoConversationState> _states =
      <String, KletsoConversationState>{};
  final Map<String, Object?> _context = <String, Object?>{};
  Timer? _typingTimer;
  bool _paused = false;
  bool _disposed = false;

  final KletsoValueNotifier<KletsoConnectionState> _connectionState =
      KletsoValueNotifier<KletsoConnectionState>(KletsoConnectionState.closed);
  final KletsoValueNotifier<List<KletsoMessage>> _messages =
      KletsoValueNotifier<List<KletsoMessage>>(const <KletsoMessage>[]);
  final KletsoValueNotifier<List<KletsoConversation>> _conversations =
      KletsoValueNotifier<List<KletsoConversation>>(
        const <KletsoConversation>[],
      );
  final KletsoValueNotifier<KletsoConversation?> _active =
      KletsoValueNotifier<KletsoConversation?>(null);
  final KletsoValueNotifier<bool> _typing = KletsoValueNotifier<bool>(false);
  final KletsoValueNotifier<KletsoSessionBootstrap?> _session =
      KletsoValueNotifier<KletsoSessionBootstrap?>(null);
  final StreamController<KletsoEvent> _events =
      StreamController<KletsoEvent>.broadcast();
  final StreamController<KletsoNotification> _notifications =
      StreamController<KletsoNotification>.broadcast();
  final Set<String> _seenNotificationIds = <String>{};
  KletsoPushToken? _pushToken;

  // ---- observables ----------------------------------------------------------

  /// Realtime connection state.
  KletsoValueListenable<KletsoConnectionState> get connection =>
      _connectionState;

  /// Messages of the active conversation, oldest first.
  KletsoValueListenable<List<KletsoMessage>> get messages => _messages;

  /// The end user's conversations, most recent first.
  KletsoValueListenable<List<KletsoConversation>> get conversations =>
      _conversations;

  /// The conversation [messages] shows, or `null` before the first one.
  KletsoValueListenable<KletsoConversation?> get activeConversation => _active;

  /// Whether the agent is composing (from `agent.typing`, with a TTL).
  KletsoValueListenable<bool> get agentTyping => _typing;

  /// Session bootstrap (agent info, theme, allowlists); `null` until
  /// [authenticate] or [identifyAnonymous] succeeded.
  KletsoValueListenable<KletsoSessionBootstrap?> get session => _session;

  /// Every protocol and client event. Broadcast; late listeners miss earlier
  /// events, use the value listenables for state.
  Stream<KletsoEvent> get events => _events.stream;

  /// Proactive `app.notify` notifications, deduped on `notificationId`,
  /// whether they arrived live or through [handlePushPayload]. The Flutter
  /// layer's `KletsoNotificationHost` renders them; hosts may listen too.
  Stream<KletsoNotification> get notifications => _notifications.stream;

  /// The push token registered for this session, if any.
  KletsoPushToken? get pushToken => _pushToken;

  /// Read-only view of the runtime context.
  Map<String, Object?> get context =>
      Map<String, Object?>.unmodifiable(_context);

  /// Whether a session exists.
  bool get isAuthenticated => _bootstrap != null;

  /// The agent used for new conversations.
  String get activeAgentId => _activeAgentId;

  // ---- identity ---------------------------------------------------------------

  /// Creates a session for the end user identified by the host-signed
  /// [token]. [onTokenExpired] is asked for a fresh token when the runtime
  /// rejects the old one. Throws [KletsoAuthException] when the key or token
  /// is rejected.
  Future<void> authenticate({
    required String token,
    KletsoUserTokenRefresher? onTokenExpired,
  }) async {
    _checkNotDisposed();
    _userToken = token;
    _onUserTokenExpired = onTokenExpired;
    await _startSession();
  }

  /// Creates an anonymous session. The visitor id is persisted through the
  /// [KletsoTokenStore] so a returning visitor keeps their conversations.
  Future<void> identifyAnonymous() async {
    _checkNotDisposed();
    _userToken = null;
    _onUserTokenExpired = null;
    var visitorId = await _tokenStore.read(_anonymousKey);
    if (visitorId == null) {
      visitorId = _ids.anonymousId();
      await _tokenStore.write(_anonymousKey, visitorId);
    }
    await _startSession(visitorId: visitorId);
  }

  /// Ends the session on the runtime and clears every trace of the user on
  /// the device (conversations, messages, context, visitor id).
  Future<void> logout() async {
    _checkNotDisposed();
    final bootstrap = _bootstrap;
    await _teardownConnection();
    if (bootstrap != null) {
      try {
        await _api.deleteSession(bootstrap.session);
      } on KletsoException catch (e) {
        _log.warning('deleteSession failed: $e');
      }
    }
    await _tokenStore.delete(_anonymousKey);
    _bootstrap = null;
    _userToken = null;
    _onUserTokenExpired = null;
    _states.clear();
    _context.clear();
    _session.value = null;
    _active.value = null;
    _messages.value = const <KletsoMessage>[];
    _conversations.value = const <KletsoConversation>[];
    _typing.value = false;
  }

  Future<void> _startSession({String? visitorId}) async {
    await _teardownConnection();
    final bootstrap = await _api.createSession(
      agentId: _activeAgentId,
      device: _device,
      userToken: _userToken,
      visitorId: visitorId,
      context: Map<String, Object?>.of(_context),
    );
    _bootstrap = bootstrap;
    _session.value = bootstrap;
    _log.info('session ${bootstrap.session.id} for ${bootstrap.endUser.id}');
    final connection = _connection = KletsoConnection(
      transport: _transport,
      config: config,
      log: _log,
      realtimeUrl: bootstrap.realtimeUrl,
      token: bootstrap.session.token,
      onTokenExpired: _refreshSessionToken,
      random: _random,
    );
    _subs
      ..add(connection.events.listen(_onEnvelope))
      ..add(connection.errors.listen(_onError));
    connection.state.addListener(_onConnectionState);
    if (!_paused) await connection.connect();
  }

  Future<String?> _refreshSessionToken() async {
    final bootstrap = _bootstrap;
    if (bootstrap == null) return null;
    String? userToken;
    final refresher = _onUserTokenExpired;
    if (refresher != null) userToken = await refresher();
    final session = await _api.refreshSession(
      bootstrap.session,
      userToken: userToken,
    );
    _bootstrap = bootstrap.withSession(session);
    _session.value = _bootstrap;
    return session.token;
  }

  Future<void> _teardownConnection() async {
    final connection = _connection;
    _connection = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    if (connection != null) {
      connection.state.removeListener(_onConnectionState);
      await connection.dispose();
    }
    _connectionState.value = KletsoConnectionState.closed;
  }

  // ---- context, agents, triggers ---------------------------------------------

  /// Replaces the runtime context.
  void setContext(Map<String, Object?> context) {
    _checkNotDisposed();
    _context
      ..clear()
      ..addAll(context);
    _connection?.send(
      KletsoContextFrame.replace(Map<String, Object?>.of(_context)),
    );
  }

  /// Merges [changes] into the runtime context.
  void updateContext(Map<String, Object?> changes) {
    _checkNotDisposed();
    _context.addAll(changes);
    _connection?.send(
      KletsoContextFrame.merge(Map<String, Object?>.of(changes)),
    );
  }

  /// Uses [agentId] for conversations started from now on.
  void useAgent(String agentId) {
    _checkNotDisposed();
    _activeAgentId = agentId;
  }

  /// Fires an event trigger.
  void track(
    String name, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    _checkNotDisposed();
    _connection?.send(KletsoTrackFrame(name: name, properties: properties));
  }

  /// Fires a screen trigger.
  void screen(String name) {
    _checkNotDisposed();
    _connection?.send(KletsoScreenFrame(name: name));
  }

  // ---- notifications ------------------------------------------------------------

  /// Registers the device's push token so the runtime can deliver
  /// `app.notify` events while the app is in the background. Call it after
  /// authenticating and again whenever the host's push plugin rotates the
  /// token. The SDK bundles no push plugin (D57).
  Future<void> registerPushToken(KletsoPushToken token) async {
    final session = _requireSession();
    await _api.registerPushToken(session, token);
    _pushToken = token;
  }

  /// Removes the registered push token (log out, opt out).
  Future<void> unregisterPushToken() async {
    final session = _requireSession();
    await _api.unregisterPushToken(session);
    _pushToken = null;
  }

  /// Feeds a push message's data map (FCM `RemoteMessage.data`, APNs
  /// userInfo, Web Push payload) into the client. The runtime puts a full
  /// `kletso.events/v1` envelope under the `kletso` key, as a JSON string or
  /// a map. Returns `true` when it was a Kletso notification that had not
  /// been seen yet; anything else is ignored so hosts can call this for every
  /// push they receive.
  bool handlePushPayload(Map<Object?, Object?> message) {
    _checkNotDisposed();
    final raw = message['kletso'];
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return false;
      }
    }
    if (decoded is! Map) return false;
    final KletsoEventEnvelope envelope;
    try {
      envelope = KletsoEventEnvelope.fromJson(decoded);
    } on KletsoSchemaException {
      return false;
    }
    final payload = envelope.payload;
    if (payload is! KletsoAppNotification) return false;
    return _emitNotification(envelope, payload, KletsoNotificationSource.push);
  }

  bool _emitNotification(
    KletsoEventEnvelope e,
    KletsoAppNotification n,
    KletsoNotificationSource source,
  ) {
    if (n.notificationId.isEmpty ||
        !_seenNotificationIds.add(n.notificationId)) {
      return false;
    }
    if (_seenNotificationIds.length > 512) {
      _seenNotificationIds.remove(_seenNotificationIds.first);
    }
    _notifications.add(
      KletsoNotification(
        payload: n,
        conversationId: e.conversationId,
        eventId: e.id,
        receivedAt: DateTime.now().toUtc(),
        source: source,
      ),
    );
    if (source == KletsoNotificationSource.push) {
      _events.add(KletsoServerEvent(e));
    }
    return true;
  }

  // ---- conversations ------------------------------------------------------------

  /// Creates a conversation with the active agent and makes it active.
  Future<KletsoConversation> startConversation({String? title}) async {
    final session = _requireSession();
    final conversation = await _api.createConversation(
      session,
      agentId: _activeAgentId,
      title: title,
    );
    _conversations.value = <KletsoConversation>[
      conversation,
      ..._conversations.value.where((c) => c.id != conversation.id),
    ];
    _attach(conversation);
    return conversation;
  }

  /// Makes [conversationId] active; its state is restored instantly when it
  /// was seen before, otherwise replayed from the runtime.
  Future<void> switchConversation(String conversationId) async {
    _requireSession();
    var conversation = _conversations.value
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      await listConversations();
      conversation = _conversations.value
          .where((c) => c.id == conversationId)
          .firstOrNull;
    }
    if (conversation == null) {
      throw KletsoStateException('unknown conversation $conversationId');
    }
    _attach(conversation);
  }

  /// Fetches the end user's conversations and updates [conversations].
  Future<List<KletsoConversation>> listConversations() async {
    final session = _requireSession();
    final list = await _api.listConversations(session);
    _conversations.value = List<KletsoConversation>.unmodifiable(list);
    return _conversations.value;
  }

  /// Returns the active conversation, reusing the most recent one or
  /// starting a new one when there is none.
  Future<KletsoConversation> ensureConversation() async {
    final active = _active.value;
    if (active != null) return active;
    _requireSession();
    if (_conversations.value.isEmpty) await listConversations();
    final existing = _conversations.value
        .where((c) => c.status != KletsoConversationStatus.closed)
        .firstOrNull;
    if (existing != null) {
      _attach(existing);
      return existing;
    }
    return startConversation();
  }

  void _attach(KletsoConversation conversation) {
    final state = _states[conversation.id] ??= KletsoConversationState(
      conversation.id,
    );
    _active.value = conversation;
    _messages.value = state.messages;
    _typing.value = false;
    _connection?.attach(conversation.id, after: state.lastSeq);
  }

  // ---- sending -----------------------------------------------------------------

  /// Sends [outbound] on the active conversation (starting one if needed).
  /// Completes once the frame is queued; delivery and the reply arrive as
  /// events. Throws [KletsoStateException] without a session.
  Future<void> send(KletsoOutbound outbound) async {
    _checkNotDisposed();
    final connection = _connection;
    if (connection == null) {
      throw const KletsoStateException('authenticate before sending');
    }
    final conversation = await ensureConversation();
    final clientId = _ids.clientId();
    final state = _states[conversation.id]!;
    final echo = outbound.echoText;
    if (echo != null || outbound is KletsoOutboundValue) {
      state.addPending(clientId, echo, switch (outbound) {
        KletsoOutboundValue(:final value) => value,
        KletsoOutboundAction(:final value) => value,
        KletsoOutboundText() => null,
      });
      _messages.value = state.messages;
    }
    connection.send(outbound.toFrame(clientId));
  }

  /// Reports that a `local` action ran on the device. Emits
  /// [KletsoLocalActionRan] and, when `config.reportLocalActions` is on,
  /// tells the runtime for analytics.
  void reportLocalAction({
    required String name,
    required JsonMap args,
    required String surfaceId,
    required String componentId,
    required String actionId,
    required bool handled,
  }) {
    if (_disposed) return;
    _events.add(
      KletsoLocalActionRan(
        name: name,
        args: args,
        surfaceId: surfaceId,
        componentId: componentId,
        handled: handled,
      ),
    );
    if (config.reportLocalActions) {
      _connection?.send(
        KletsoActionFrame(
          surfaceId: surfaceId,
          componentId: componentId,
          actionId: actionId,
          clientId: _ids.clientId(),
          value: <String, Object?>{'local': name, 'handled': handled},
        ),
      );
    }
  }

  /// Reports a component type that nothing could render.
  void reportUnknownComponent({
    required String type,
    required String surfaceId,
  }) {
    if (_disposed) return;
    _events.add(KletsoUnknownComponent(type: type, surfaceId: surfaceId));
  }

  // ---- lifecycle ---------------------------------------------------------------

  /// Closes the socket without forgetting anything (app went to background).
  Future<void> pause() async {
    _paused = true;
    await _connection?.disconnect();
  }

  /// Reconnects after [pause].
  Future<void> resume() async {
    _paused = false;
    final connection = _connection;
    if (connection != null && !connection.wantsConnection) {
      try {
        await connection.connect();
      } on KletsoException {
        // Already reported through the events stream.
      }
    }
  }

  /// Releases every resource. The client is unusable afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _typingTimer?.cancel();
    await _teardownConnection();
    if (_ownsApi) _api.close();
    _connectionState.dispose();
    _messages.dispose();
    _conversations.dispose();
    _active.dispose();
    _typing.dispose();
    _session.dispose();
    await _events.close();
    await _notifications.close();
  }

  // ---- internals ---------------------------------------------------------------

  KletsoTransport _defaultTransport(http.Client? httpClient) {
    final ws = KletsoWebSocketTransport(
      handshakeTimeout: config.connectTimeout,
    );
    switch (config.transport) {
      case KletsoTransportMode.webSocket:
        return ws;
      case KletsoTransportMode.sse:
        return KletsoSseTransport(
          api: _api,
          apiRoot: config.apiRoot,
          client: httpClient,
          handshakeTimeout: config.connectTimeout,
        );
      case KletsoTransportMode.auto:
        return KletsoAutoTransport(
          primary: ws,
          fallback: KletsoSseTransport(
            api: _api,
            apiRoot: config.apiRoot,
            client: httpClient,
            handshakeTimeout: config.connectTimeout,
          ),
        );
    }
  }

  void _onEnvelope(KletsoEventEnvelope e) {
    if (_disposed) return;
    final state = _states[e.conversationId] ??= KletsoConversationState(
      e.conversationId,
    );
    final changed = state.apply(e);
    final isActive = _active.value?.id == e.conversationId;
    if (changed && isActive) _messages.value = state.messages;
    switch (e.payload) {
      case KletsoAgentTyping():
        if (isActive) _setTyping(true);
      case KletsoMessageCreated(:final role) when role == KletsoRole.assistant:
      case KletsoMessageCompleted():
      case KletsoErrorEvent():
        if (isActive) _setTyping(false);
      case KletsoConversationEvent(:final conversation):
        _upsertConversation(conversation);
      case KletsoAppNotification():
        _emitNotification(
          e,
          e.payload as KletsoAppNotification,
          KletsoNotificationSource.live,
        );
      default:
        break;
    }
    switch (e.payload) {
      case KletsoErrorEvent(:final code, :final message, :final retryable):
        _events.add(
          KletsoClientError(
            KletsoServerException(message, code: code, retryable: retryable),
          ),
        );
      case KletsoToolFinished(
            :final failed,
            :final name,
            :final errorMessage,
            :final errorCode,
          )
          when failed:
        _events.add(
          KletsoClientError(
            KletsoToolException(
              errorMessage ?? 'tool $name failed',
              toolName: name,
              code: errorCode,
            ),
          ),
        );
      case KletsoWorkflowEvent(:final status, :final runId, :final error)
          when status == KletsoWorkflowStatus.failed:
        _events.add(
          KletsoClientError(
            KletsoWorkflowException(error ?? 'workflow failed', runId: runId),
          ),
        );
      default:
        break;
    }
    _events.add(KletsoServerEvent(e));
  }

  void _upsertConversation(KletsoConversation conversation) {
    if (conversation.id.isEmpty) return;
    final list = <KletsoConversation>[
      conversation,
      ..._conversations.value.where((c) => c.id != conversation.id),
    ];
    _conversations.value = List<KletsoConversation>.unmodifiable(list);
    if (_active.value?.id == conversation.id) _active.value = conversation;
  }

  void _setTyping(bool on) {
    _typingTimer?.cancel();
    _typingTimer = null;
    _typing.value = on;
    if (on) {
      _typingTimer = Timer(config.typingIndicatorTtl, () {
        _typingTimer = null;
        _typing.value = false;
      });
    }
  }

  void _onError(KletsoException e) {
    if (_disposed) return;
    _events.add(KletsoClientError(e));
  }

  void _onConnectionState() {
    final connection = _connection;
    if (connection == null || _disposed) return;
    final state = connection.state.value;
    _connectionState.value = state;
    _events.add(KletsoConnectionChanged(state));
  }

  KletsoSession _requireSession() {
    _checkNotDisposed();
    final bootstrap = _bootstrap;
    if (bootstrap == null) {
      throw const KletsoStateException(
        'no session: call authenticate() or identifyAnonymous() first',
      );
    }
    return bootstrap.session;
  }

  void _checkNotDisposed() {
    if (_disposed) throw const KletsoStateException('client disposed');
  }
}
