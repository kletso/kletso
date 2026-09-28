import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:kletso_ui_schema/kletso_ui_schema.dart';

import '../api/api.dart';
import '../exceptions.dart';
import '../model/conversation.dart';
import '../model/notification.dart';
import '../session.dart';
import '../transport/transport.dart';
import 'scenario.dart';

/// A complete fake runtime in memory: REST ([KletsoApi]) and realtime
/// ([KletsoTransport]) with an agent that answers from the protocol fixtures.
///
/// Say "flight", "hotel", "products", "sales", "cancel my order", "callback",
/// "order", "human" or "error" to get the matching surface or behaviour;
/// anything else is echoed with quick replies. Actions on surfaces are
/// answered too (select flight, book, add to cart, confirm, submit form).
final class KletsoFakeBackend implements KletsoApi, KletsoTransport {
  /// Creates a backend.
  KletsoFakeBackend({this.scenario = const KletsoFakeScenario(), DateTime? now})
    : _start = now;

  /// Behaviour knobs.
  final KletsoFakeScenario scenario;
  final DateTime? _start;

  final Map<String, _Session> _sessions = <String, _Session>{};
  final Map<String, _Conversation> _conversations = <String, _Conversation>{};
  final List<_FakeSocket> _sockets = <_FakeSocket>[];
  final StreamController<KletsoClientFrame> _sent =
      StreamController<KletsoClientFrame>.broadcast();

  /// Every event of every conversation, tagged with its end user. Sockets that
  /// are not attached to a conversation receive their user's events from
  /// here, the way the runtime notifies a device when a trigger opens a new
  /// conversation.
  final StreamController<(String, KletsoEventEnvelope)> _userEvents =
      StreamController<(String, KletsoEventEnvelope)>.broadcast();
  final Map<String, KletsoPushToken> _pushTokens = <String, KletsoPushToken>{};
  int _pushesSent = 0;
  int _handshakes = 0;
  int _messagesSeen = 0;
  int _ids = 0;
  bool _expired = false;
  bool _closed = false;

  /// Agent id the fake serves.
  static const String agentId = 'agt_01J8ACME00001';

  /// The custom component type the fake agent may render.
  static const List<String> allowedComponents = <String>['acme.productCard'];

  /// Hosts the fake agent links to.
  static const List<String> allowedUrlHosts = <String>[
    'acme.com',
    'cdn.acme.com',
    'track.carrier.example',
    'maps.google.com',
    'flutter.github.io',
    'tile.openstreetmap.org',
  ];

  /// Every client frame any socket received (for assertions).
  Stream<KletsoClientFrame> get sentFrames => _sent.stream;

  /// Sockets currently open.
  int get openSockets => _sockets.where((s) => !s._closed).length;

  /// Number of handshakes attempted.
  int get handshakes => _handshakes;

  /// Push tokens registered per end user, for assertions.
  Map<String, KletsoPushToken> get pushTokens =>
      Map<String, KletsoPushToken>.unmodifiable(_pushTokens);

  /// How many push payloads [sendPush] produced.
  int get pushesSent => _pushesSent;

  /// Server-originated notification (what a dashboard workflow's "notify the
  /// app" step does): delivered live over the user's socket, attached to
  /// the user's latest open conversation (created if needed).
  KletsoEventEnvelope notify(String endUserId, KletsoAppNotification n) {
    final target = _conversationFor(endUserId);
    return target.add(KletsoEventTypes.appNotify, n.toJson());
  }

  /// Builds the data map a push provider would deliver for [n] while the app
  /// is in the background: `{'kletso': '<envelope json>'}`. Hosts feed it to
  /// `KletsoClient.handlePushPayload`. Requires a registered push token.
  /// Nothing is sent over the socket, so the only way the app learns about
  /// it is through the push.
  Map<String, Object?> sendPush(String endUserId, KletsoAppNotification n) {
    if (!_pushTokens.containsKey(endUserId)) {
      throw const KletsoStateException('no push token registered for user');
    }
    final target = _conversationFor(endUserId);
    final envelope = KletsoEventEnvelope(
      id: _id('evt'),
      seq: target.seq == 0 ? 1 : target.seq,
      type: KletsoEventTypes.appNotify,
      ts: _now(),
      conversationId: target.id,
      data: n.toJson(),
    );
    _pushesSent++;
    return <String, Object?>{
      'kletso': jsonEncode(envelope.toJson()),
      'title': n.title,
      if (n.body != null) 'body': n.body,
    };
  }

  /// The runtime context the fake holds for [endUserId] (from `context`
  /// frames and `PUT/PATCH` calls), for assertions.
  Map<String, Object?> contextOf(String endUserId) =>
      Map<String, Object?>.unmodifiable(
        _sessions.values
                .where((s) => s.endUserId == endUserId && !s.expired)
                .map((s) => s.context)
                .lastOrNull ??
            const <String, Object?>{},
      );

  /// Event log of [conversationId], for assertions.
  List<KletsoEventEnvelope> logOf(String conversationId) =>
      List<KletsoEventEnvelope>.unmodifiable(
        _conversations[conversationId]?.log ?? const <KletsoEventEnvelope>[],
      );

  /// Closes every open socket with [code] (simulates a deploy).
  void dropAllSockets([int code = 1001, String reason = 'deploy']) {
    for (final s in List<_FakeSocket>.of(_sockets)) {
      s._serverClose(code, reason);
    }
  }

  /// Marks the current session tokens expired: open sockets close with 4403
  /// and the next handshake with an old token fails until refreshed.
  void expireTokens() {
    _expired = true;
    for (final s in List<_FakeSocket>.of(_sockets)) {
      s._serverClose(KletsoCloseCodes.tokenExpired, 'token expired');
    }
  }

  /// Appends a server-authored event of [type] with [data] to a conversation
  /// (e.g. `agent.typing`, or a trigger opening a conversation).
  void emit(
    String conversationId,
    String type,
    JsonMap data, {
    String? turnId,
  }) {
    final conv = _conversations[conversationId];
    if (conv == null) return;
    conv.add(type, data, turnId: turnId);
  }

  // ---- KletsoApi ----------------------------------------------------------------

  Future<void> _latency() => Future<void>.delayed(scenario.apiLatency);

  String _id(String prefix) =>
      '${prefix}_01J8FAKE${(++_ids).toString().padLeft(6, '0')}';

  DateTime _now() => (_start ?? clock.now()).toUtc();

  _Session _auth(KletsoSession session) {
    final s = _sessions[session.token];
    if (s == null) throw const KletsoAuthException('unknown session token');
    if (s.expired) {
      throw const KletsoAuthException('session expired', expired: true);
    }
    return s;
  }

  @override
  Future<KletsoSessionBootstrap> createSession({
    required String agentId,
    required KletsoDevice device,
    String? userToken,
    String? visitorId,
    JsonMap context = const <String, Object?>{},
  }) async {
    await _latency();
    if (_closed) throw const KletsoStateException('backend closed');
    final endUserId = userToken != null
        ? 'eu_${userToken.hashCode.toRadixString(36)}'
        : 'eu_${(visitorId ?? 'anon').hashCode.toRadixString(36)}';
    final session = _Session(
      id: _id('ses'),
      token: 'kst_${_id('tok')}',
      endUserId: endUserId,
      anonymous: userToken == null,
      context: Map<String, Object?>.of(context),
    );
    _sessions[session.token] = session;
    return _bootstrap(session);
  }

  KletsoSessionBootstrap _bootstrap(_Session s) => KletsoSessionBootstrap(
    session: KletsoSession(
      id: s.id,
      token: s.token,
      expiresAt: _now().add(const Duration(hours: 1)),
    ),
    endUser: KletsoEndUser(id: s.endUserId, anonymous: s.anonymous),
    agent: KletsoAgentInfo(
      id: agentId,
      versionId: 'agv_01J8FAKE000001',
      name: 'Acme Assistant',
      greeting:
          'Hi! I\'m Acme\'s assistant. I can find flights and hotels, show your sales, or help with an order. What do you need?',
      allowedComponents: allowedComponents,
    ),
    realtimeUrl: Uri.parse('wss://fake.kletso.test/v1/realtime'),
    theme: const <String, Object?>{
      'primary': '#FF6A2B',
      'onPrimary': '#FFFFFF',
      'surface': '#FFFFFF',
      'background': '#FBF7F0',
      'text': '#1E2A44',
      'textMuted': '#6B7280',
      'radius': 16,
      'fontFamily': 'Plus Jakarta Sans',
      'launcher': <String, Object?>{'position': 'bottomRight', 'icon': 'chat'},
    },
    minClient: '0.1.0',
    allowedUrlHosts: allowedUrlHosts,
  );

  @override
  Future<KletsoSession> refreshSession(
    KletsoSession current, {
    String? userToken,
  }) async {
    await _latency();
    final old = _sessions[current.token];
    if (old == null) throw const KletsoAuthException('unknown session token');
    old.expired = true;
    final fresh = _Session(
      id: old.id,
      token: 'kst_${_id('tok')}',
      endUserId: old.endUserId,
      anonymous: old.anonymous,
      context: old.context,
    );
    _sessions[fresh.token] = fresh;
    _expired = false;
    return KletsoSession(
      id: fresh.id,
      token: fresh.token,
      expiresAt: _now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> deleteSession(KletsoSession session) async {
    await _latency();
    _sessions.remove(session.token);
  }

  @override
  Future<void> updateContext(
    KletsoSession session,
    JsonMap context, {
    required bool replace,
  }) async {
    await _latency();
    final s = _auth(session);
    if (replace) s.context.clear();
    s.context.addAll(context);
  }

  @override
  Future<List<KletsoConversation>> listConversations(
    KletsoSession session,
  ) async {
    await _latency();
    final s = _auth(session);
    final list =
        _conversations.values.where((c) => c.endUserId == s.endUserId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.map((c) => c.info).toList(growable: false);
  }

  @override
  Future<KletsoConversation> createConversation(
    KletsoSession session, {
    String? agentId,
    String? title,
  }) async {
    await _latency();
    final s = _auth(session);
    final seed = scenario.seedConversationLog && _conversations.isEmpty;
    final conv = _Conversation(
      id: seed ? 'conv_01J8DEMO000001' : _id('conv'),
      endUserId: s.endUserId,
      agentId: agentId ?? KletsoFakeBackend.agentId,
      title: title,
      createdAt: _now(),
      backend: this,
    );
    _conversations[conv.id] = conv;
    if (seed) {
      final script = KletsoConversationScript(start: _now());
      for (final e in script.build()) {
        conv.log.add(e);
        conv.seq = e.seq;
      }
      conv.status = KletsoConversationStatus.handoff;
    } else {
      conv.add(KletsoEventTypes.conversationCreated, <String, Object?>{
        'conversation': conv.info.toJson(),
      });
      if (scenario.greeting) unawaited(conv.reply(_Reply.greeting()));
    }
    return conv.info;
  }

  @override
  Future<List<KletsoEventEnvelope>> listEvents(
    KletsoSession session,
    String conversationId, {
    int after = 0,
    int limit = 200,
  }) async {
    await _latency();
    _auth(session);
    final conv = _conversations[conversationId];
    if (conv == null) {
      throw const KletsoServerException(
        'not found',
        code: 'not_found',
        statusCode: 404,
      );
    }
    return conv.log
        .where((e) => e.seq > after)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> postMessage(
    KletsoSession session,
    String conversationId,
    KletsoMessageFrame frame,
  ) async {
    await _latency();
    _auth(session);
    _conversations[conversationId]?.onMessage(frame);
  }

  @override
  Future<void> postAction(
    KletsoSession session,
    String conversationId,
    KletsoActionFrame frame,
  ) async {
    await _latency();
    _auth(session);
    _conversations[conversationId]?.onAction(frame);
  }

  @override
  Future<void> postTrigger(
    KletsoSession session,
    KletsoClientFrame frame,
  ) async {
    await _latency();
    final s = _auth(session);
    _fireTrigger(s, frame);
  }

  @override
  Future<void> registerPushToken(
    KletsoSession session,
    KletsoPushToken token,
  ) async {
    await _latency();
    final s = _auth(session);
    _pushTokens[s.endUserId] = token;
  }

  @override
  Future<void> unregisterPushToken(KletsoSession session) async {
    await _latency();
    final s = _auth(session);
    _pushTokens.remove(s.endUserId);
  }

  /// Dashboard-style trigger rules. `track('cart_abandoned')` and
  /// `screen('checkout')` make the agent speak first in the user's latest
  /// open conversation (creating one if needed) with a `trigger.fired` event
  /// and a proactive surface. Silent app events can also produce
  /// `app.notify` notifications, the way a workflow's "notify" step would:
  /// `geofence_entered` (banner + opens the chat, then a welcome turn),
  /// `payment_failed` (alert with a local action, no chat turn) and
  /// `order_shipped` (OS notification with an inline surface).
  void _fireTrigger(_Session s, KletsoClientFrame frame) {
    final (String kind, String name, _Reply? reply) = switch (frame) {
      KletsoTrackFrame(name: 'cart_abandoned', :final properties) => (
        'event',
        'cart_abandoned',
        _Reply(
          text:
              'Looks like you left something in your cart (${properties['value'] ?? 'a few items'}). Want a hand finishing checkout? Free shipping ends soon:',
          surface: _cartNudge(),
        ),
      ),
      KletsoScreenFrame(name: 'checkout') => (
        'screen',
        'checkout',
        _Reply(
          text:
              'Checking out? Here is how delivery works and when to expect your order:',
          surface: _Reply.mediaHub(sampleMedia: scenario.sampleMedia),
        ),
      ),
      KletsoTrackFrame(name: 'geofence_entered', :final properties) => (
        'event',
        'geofence_entered',
        _Reply(
          text:
              'Welcome to Acme ${properties['store'] ?? 'Shibuya'}! Show code SHIBUYA10 at the till for 10% off today. Want me to check what is in stock here?',
          surface: KletsoFixtures.quickReplies,
          notification: KletsoAppNotification(
            notificationId: _id('ntf'),
            title: 'You are near Acme ${properties['store'] ?? 'Shibuya'}',
            body: '10% off in store today. Tap to see the code.',
            openChat: true,
            ttl: const Duration(seconds: 12),
            data: <String, Object?>{'store': properties['store'] ?? 'Shibuya'},
          ).toJson(),
        ),
      ),
      KletsoTrackFrame(name: 'payment_failed', :final properties) => (
        'event',
        'payment_failed',
        _Reply(
          text: '',
          notification: KletsoAppNotification(
            notificationId: _id('ntf'),
            title: 'Payment did not go through',
            body:
                'Your ${properties['method'] ?? 'card'} was declined. Retry or pick another method to keep your cart.',
            channel: KletsoNotificationChannel.alert,
            action: const KletsoLocalAction(
              id: 'retry',
              label: 'Retry payment',
              name: 'open_checkout',
              args: <String, Object?>{'retry': true},
            ),
          ).toJson(),
        ),
      ),
      KletsoTrackFrame(name: 'order_shipped', :final properties) => (
        'event',
        'order_shipped',
        _Reply(
          text: '',
          notification: KletsoAppNotification(
            notificationId: _id('ntf'),
            title: 'Order ${properties['orderId'] ?? 'ORD-2201'} shipped',
            body: 'Arrives tomorrow. Track it live or ask me anything.',
            channel: KletsoNotificationChannel.system,
            openChat: true,
            rawSurface: _shipmentSteps(),
          ).toJson(),
        ),
      ),
      _ => ('event', '', null),
    };
    if (reply == null) return;
    final target = _conversationFor(s.endUserId);
    final turnId = target.newTurn();
    target.add(KletsoEventTypes.triggerFired, <String, Object?>{
      'triggerId': 'trg_01J8FAKE_$name',
      'kind': kind,
      'name': name,
    }, turnId: turnId);
    unawaited(target.reply(reply, turnId: turnId));
  }

  /// The user's latest open conversation, created when there is none.
  _Conversation _conversationFor(String endUserId) {
    final open =
        _conversations.values
            .where(
              (c) =>
                  c.endUserId == endUserId &&
                  c.status == KletsoConversationStatus.open,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (open.isNotEmpty) return open.first;
    final target = _Conversation(
      id: _id('conv'),
      endUserId: endUserId,
      agentId: agentId,
      createdAt: _now(),
      backend: this,
    );
    _conversations[target.id] = target;
    target.add(KletsoEventTypes.conversationCreated, <String, Object?>{
      'conversation': target.info.toJson(),
    });
    return target;
  }

  static Object _shipmentSteps() => <String, Object?>{
    'schema': 'kletso.ui/v1',
    'surfaceId': 'sfc_01J8SHIPSTEPS1',
    'root': 'steps',
    'fallbackText': 'Packed → Shipped → Out for delivery → Delivered',
    'components': <String, Object?>{
      'steps': <String, Object?>{
        'type': 'steps',
        'props': <String, Object?>{
          'orientation': 'horizontal',
          'items': <Object?>[
            <String, Object?>{'id': 's1', 'title': 'Packed', 'status': 'done'},
            <String, Object?>{'id': 's2', 'title': 'Shipped', 'status': 'done'},
            <String, Object?>{
              'id': 's3',
              'title': 'Out for delivery',
              'status': 'current',
            },
            <String, Object?>{
              'id': 's4',
              'title': 'Delivered',
              'status': 'upcoming',
            },
          ],
        },
      },
    },
  };

  static Object _cartNudge() => <String, Object?>{
    'schema': 'kletso.ui/v1',
    'surfaceId': 'sfc_01J8CARTNUDGE1',
    'root': 'card',
    'components': <String, Object?>{
      'card': <String, Object?>{
        'type': 'card',
        'props': <String, Object?>{
          'title': 'Free shipping ends in',
          'children': <String>['cd', 'progress', 'row'],
        },
      },
      'cd': <String, Object?>{
        'type': 'countdown',
        'props': <String, Object?>{
          'endsAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 30))
              .toIso8601String(),
          'expiredLabel': 'Offer ended',
          'tone': 'warning',
        },
      },
      'progress': <String, Object?>{
        'type': 'progress',
        'props': <String, Object?>{
          'value': <String, Object?>{'path': '/host/cart/progress'},
          'label': 'Cart',
          'detail': <String, Object?>{'path': '/host/cart/label'},
          'tone': 'success',
        },
      },
      'row': <String, Object?>{
        'type': 'row',
        'props': <String, Object?>{
          'children': <String>['b1', 'b2'],
          'gap': 'sm',
        },
      },
      'b1': <String, Object?>{
        'type': 'button',
        'props': <String, Object?>{
          'label': 'Finish checkout',
          'variant': 'primary',
        },
        'actions': <Object?>[
          <String, Object?>{
            'id': 'go',
            'kind': 'local',
            'name': 'open_checkout',
          },
        ],
      },
      'b2': <String, Object?>{
        'type': 'button',
        'props': <String, Object?>{
          'label': 'Show my cart',
          'variant': 'secondary',
        },
        'actions': <Object?>[
          <String, Object?>{
            'id': 'cart',
            'kind': 'agent',
            'value': <String, Object?>{'intent': 'show_cart'},
            'label': 'Show my cart',
          },
        ],
      },
    },
    'data': <String, Object?>{
      'host': <String, Object?>{
        'cart': <String, Object?>{
          'progress': 0.0,
          'label': 'Add items to reach free shipping',
        },
      },
    },
    'fallbackText':
        'Free shipping ends in 30 minutes. Finish checkout or view your cart.',
  };

  @override
  void close() {
    _closed = true;
    for (final s in List<_FakeSocket>.of(_sockets)) {
      s._serverClose(KletsoCloseCodes.goingAway, 'backend closed');
    }
    unawaited(_sent.close());
    unawaited(_userEvents.close());
  }

  // ---- KletsoTransport -------------------------------------------------------------

  @override
  String get name => 'fake';

  @override
  Future<KletsoSocket> open(KletsoTransportRequest request) async {
    _handshakes++;
    await _latency();
    if (_handshakes <= scenario.failHandshakes) {
      throw const KletsoNetworkException('simulated handshake failure');
    }
    if (scenario.rejectToken) {
      throw const KletsoAuthException('invalid token');
    }
    final session = _sessions[request.token];
    if (session == null) throw const KletsoAuthException('unknown token');
    if (session.expired || _expired) {
      throw const KletsoAuthException('token expired', expired: true);
    }
    final socket = _FakeSocket(this, session);
    _sockets.add(socket);
    if (request.conversationId != null) {
      socket._attach(request.conversationId!, request.after);
    } else {
      socket._readySeq = 0;
      socket._listenUnattached();
    }
    return socket;
  }

  void _forget(_FakeSocket s) => _sockets.remove(s);
}

final class _Session {
  _Session({
    required this.id,
    required this.token,
    required this.endUserId,
    required this.anonymous,
    required this.context,
  });
  final String id;
  final String token;
  final String endUserId;
  final bool anonymous;
  final Map<String, Object?> context;
  bool expired = false;
}

/// One conversation's log plus the scripted agent behind it.
final class _Conversation {
  _Conversation({
    required this.id,
    required this.endUserId,
    required this.agentId,
    required this.createdAt,
    required this.backend,
    this.title,
  });

  final String id;
  final String endUserId;
  final String agentId;
  final DateTime createdAt;
  final KletsoFakeBackend backend;
  String? title;
  KletsoConversationStatus status = KletsoConversationStatus.open;
  int seq = 0;
  int turns = 0;
  int messages = 0;
  final List<KletsoEventEnvelope> log = <KletsoEventEnvelope>[];
  final StreamController<KletsoEventEnvelope> live =
      StreamController<KletsoEventEnvelope>.broadcast();
  final Set<String> seenClientIds = <String>{};
  String? pendingConfirmCallId;

  KletsoConversation get info => KletsoConversation(
    id: id,
    agentId: agentId,
    title: title,
    status: status,
    createdAt: createdAt,
    updatedAt: log.isEmpty ? createdAt : log.last.ts,
    lastSeq: seq,
  );

  KletsoEventEnvelope add(String type, JsonMap data, {String? turnId}) {
    seq++;
    final e = KletsoEventEnvelope(
      id: 'evt_01J8FAKE${id.hashCode.toRadixString(36)}${seq.toString().padLeft(6, '0')}',
      seq: seq,
      type: type,
      ts: backend._now(),
      conversationId: id,
      turnId: turnId,
      data: data,
    );
    log.add(e);
    live.add(e);
    backend._userEvents.add((endUserId, e));
    return e;
  }

  String newTurn() => 'trn_01J8FAKE${(++turns).toString().padLeft(6, '0')}';
  String newMessage() =>
      'msg_01J8FAKE${(++messages).toString().padLeft(6, '0')}';

  void onMessage(KletsoMessageFrame frame) {
    if (!seenClientIds.add(frame.clientId)) return; // dedupe on clientId
    backend._messagesSeen++;
    final turnId = newTurn();
    add(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': newMessage(),
      'role': 'user',
      'text': frame.text ?? _labelFor(frame.value),
      if (frame.value != null) 'value': frame.value,
      'clientId': frame.clientId,
    }, turnId: turnId);
    final every = backend.scenario.rateLimitEveryNthMessage;
    if (every != null && backend._messagesSeen % every == 0) {
      for (final s in backend._sockets.where((s) => s._conversationId == id)) {
        s._push(
          const KletsoErrorFrame(
            code: 'rate_limited',
            message: 'Too many messages, slow down',
            retryable: true,
            retryAfterMs: 2000,
          ),
        );
      }
      return;
    }
    unawaited(
      reply(
        _Reply.forInput(
          frame.text,
          frame.value,
          sampleMedia: backend.scenario.sampleMedia,
        ),
        turnId: turnId,
      ),
    );
  }

  void onAction(KletsoActionFrame frame) {
    if (!seenClientIds.add(frame.clientId)) return;
    final value = frame.value;
    if (value is Map && value.containsKey('local')) {
      add(KletsoEventTypes.uiAction, <String, Object?>{
        'surfaceId': frame.surfaceId,
        'componentId': frame.componentId,
        'actionId': frame.actionId,
        'value': value,
      });
      return; // analytics only
    }
    final turnId = newTurn();
    add(KletsoEventTypes.uiAction, <String, Object?>{
      'surfaceId': frame.surfaceId,
      'componentId': frame.componentId,
      'actionId': frame.actionId,
      'value': value,
    }, turnId: turnId);
    add(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': newMessage(),
      'role': 'user',
      'text':
          _labelFromSurface(
            frame.surfaceId,
            frame.componentId,
            frame.actionId,
          ) ??
          _labelFor(value),
      'value': value,
      'clientId': frame.clientId,
    }, turnId: turnId);
    if (value is Map && value.containsKey('approve')) {
      final approved = value['approve'] == true;
      final callId =
          (value['toolCallId'] as String?) ??
          pendingConfirmCallId ??
          'call_01J8CANCEL0001';
      pendingConfirmCallId = null;
      unawaited(
        reply(
          approved
              ? _Reply(
                  text:
                      'Done. Order ORD-4521 is cancelled and ₹3,499 will be refunded within 5–7 days.',
                  completeTool: _Tool(
                    'cancel_order',
                    const <String, Object?>{'orderId': 'ORD-4521'},
                    callId: callId,
                    result: const <String, Object?>{
                      'status': 'cancelled',
                      'refund': 3499,
                    },
                  ),
                )
              : _Reply(
                  text: 'No problem, your order stays as it is.',
                  completeTool: _Tool(
                    'cancel_order',
                    const <String, Object?>{'orderId': 'ORD-4521'},
                    callId: callId,
                    failed: true,
                    error: 'cancelled_by_user',
                  ),
                ),
          turnId: turnId,
        ),
      );
      return;
    }
    unawaited(
      reply(
        _Reply.forInput(null, value, sampleMedia: backend.scenario.sampleMedia),
        turnId: turnId,
      ),
    );
  }

  /// The `label` of the action as declared in the fixture surface, the way
  /// the real runtime resolves it from the stored surface.
  static String? _labelFromSurface(
    String surfaceId,
    String componentId,
    String actionId,
  ) {
    for (final path in KletsoFixtures.validSurfaces) {
      final json = KletsoFixtures.json(path);
      if (json is! Map || json['surfaceId'] != surfaceId) continue;
      final surface = KletsoSurface.fromJson(json);
      final node = surface.node(componentId);
      final action = node?.action(actionId);
      if (node == null || action == null) return null;
      if (action.label != null) return action.label;
      if (action is KletsoConfirmAction) {
        return node.string(
          action.approve ? 'confirmLabel' : 'cancelLabel',
          fallback: action.approve ? 'Confirm' : 'Cancel',
        );
      }
      return node.stringOrNull('label');
    }
    return null;
  }

  static String _labelFor(Object? value) {
    if (value is Map) {
      final intent = value['intent'];
      if (value.containsKey('approve')) {
        return value['approve'] == true ? 'Yes, confirm' : 'No, cancel';
      }
      if (value.containsKey('formId')) return 'Form submitted';
      if (intent is String) return intent.replaceAll('_', ' ');
    }
    return value?.toString() ?? '';
  }

  Future<void> _delay(Duration d) =>
      d == Duration.zero ? Future<void>.value() : Future<void>.delayed(d);

  Future<void> reply(_Reply r, {String? turnId}) async {
    final s = backend.scenario;
    turnId ??= newTurn();
    await _delay(s.thinkingDelay);
    if (backend._closed) return;
    add(
      KletsoEventTypes.agentTyping,
      const <String, Object?>{},
      turnId: turnId,
    );
    final complete = r.completeTool;
    if (complete != null) {
      await _delay(s.toolDelay);
      add(
        complete.failed
            ? KletsoEventTypes.toolFailed
            : KletsoEventTypes.toolCompleted,
        <String, Object?>{
          'toolCallId': complete.callId!,
          'name': complete.name,
          'durationMs': s.toolDelay.inMilliseconds,
          if (!complete.failed) 'result': complete.result,
          if (complete.failed)
            'error': <String, Object?>{
              'code': complete.error,
              'message': complete.error,
            },
        },
        turnId: turnId,
      );
    }
    final tool = r.tool;
    if (tool != null) {
      final callId =
          tool.callId ?? 'call_01J8FAKE${seq.toString().padLeft(6, '0')}';
      add(KletsoEventTypes.toolStarted, <String, Object?>{
        'toolCallId': callId,
        'name': tool.name,
        'args': tool.args,
      }, turnId: turnId);
      await _delay(s.toolDelay);
      add(KletsoEventTypes.toolCompleted, <String, Object?>{
        'toolCallId': callId,
        'name': tool.name,
        'durationMs': s.toolDelay.inMilliseconds,
        'result': tool.result,
      }, turnId: turnId);
    }
    if (r.error != null) {
      add(KletsoEventTypes.error, <String, Object?>{
        'code': 'provider_error',
        'message': r.error,
        'retryable': true,
      }, turnId: turnId);
      return;
    }
    if (r.notification != null) {
      add(KletsoEventTypes.appNotify, r.notification!, turnId: turnId);
    }
    if (r.text.isEmpty && r.surface == null && r.command == null) return;
    final messageId = newMessage();
    add(KletsoEventTypes.messageCreated, <String, Object?>{
      'messageId': messageId,
      'role': 'assistant',
      'text': '',
    }, turnId: turnId);
    for (final chunk in _chunks(r.text)) {
      await _delay(s.deltaDelay);
      if (backend._closed) return;
      add(KletsoEventTypes.messageDelta, <String, Object?>{
        'messageId': messageId,
        'text': chunk,
      }, turnId: turnId);
    }
    add(KletsoEventTypes.messageCompleted, <String, Object?>{
      'messageId': messageId,
      'text': r.text,
      'usage': <String, Object?>{
        'in': 900 + r.text.length,
        'out': r.text.length ~/ 4,
        'cachedIn': 600,
        'reasoning': 0,
      },
      'costMicros': 1200,
      'latencyMs': s.thinkingDelay.inMilliseconds + s.toolDelay.inMilliseconds,
      'finishReason': r.confirmTool != null ? 'tool_calls' : 'stop',
    }, turnId: turnId);
    final confirm = r.confirmTool;
    if (confirm != null) {
      pendingConfirmCallId = confirm.callId;
      add(KletsoEventTypes.toolStarted, <String, Object?>{
        'toolCallId': confirm.callId!,
        'name': confirm.name,
        'args': confirm.args,
      }, turnId: turnId);
      add(KletsoEventTypes.toolConfirmationRequired, <String, Object?>{
        'toolCallId': confirm.callId!,
        'name': confirm.name,
        'args': confirm.args,
        'surface': r.surface,
      }, turnId: turnId);
    }
    if (r.command != null) {
      add(KletsoEventTypes.appCommand, r.command!, turnId: turnId);
    }
    if (r.surface != null) {
      add(KletsoEventTypes.uiRender, <String, Object?>{
        'surface': r.surface,
      }, turnId: turnId);
    }
    if (r.surface != null && r.patches.isNotEmpty) {
      final surfaceId = (r.surface! as Map)['surfaceId'] as String? ?? '';
      for (final patch in r.patches) {
        await _delay(
          s.thinkingDelay == Duration.zero
              ? Duration.zero
              : const Duration(milliseconds: 1500),
        );
        if (backend._closed) return;
        add(KletsoEventTypes.uiPatch, <String, Object?>{
          'surfaceId': surfaceId,
          ...patch,
        }, turnId: turnId);
      }
    }
    if (r.handoff) {
      status = KletsoConversationStatus.handoff;
      title ??= 'Support request';
      add(KletsoEventTypes.handoffStarted, <String, Object?>{
        'target': 'inbox',
        'agentName': 'Acme support',
      }, turnId: turnId);
      add(KletsoEventTypes.conversationUpdated, <String, Object?>{
        'conversation': info.toJson(),
      }, turnId: turnId);
    } else if (title == null && messages >= 3) {
      title = _titleFrom(log);
      add(KletsoEventTypes.conversationUpdated, <String, Object?>{
        'conversation': info.toJson(),
      }, turnId: turnId);
    }
  }

  static String? _titleFrom(List<KletsoEventEnvelope> log) {
    for (final e in log) {
      final p = e.payload;
      if (p is KletsoMessageCreated &&
          p.role == KletsoRole.user &&
          (p.text ?? '').isNotEmpty) {
        final t = p.text!;
        return t.length > 40 ? '${t.substring(0, 40)}…' : t;
      }
    }
    return null;
  }

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
  const _Tool(
    this.name,
    this.args, {
    this.result,
    this.callId,
    this.failed = false,
    this.error,
  });
  final String name;
  final JsonMap args;
  final Object? result;
  final String? callId;
  final bool failed;
  final String? error;
}

final class _Reply {
  const _Reply({
    required this.text,
    this.tool,
    this.completeTool,
    this.confirmTool,
    this.surface,
    this.handoff = false,
    this.error,
    this.command,
    this.patches = const <JsonMap>[],
    this.notification,
  });

  final String text;
  final _Tool? tool;
  final _Tool? completeTool;
  final _Tool? confirmTool;
  final Object? surface;
  final bool handoff;
  final String? error;

  /// Server-initiated local action emitted after the text.
  final JsonMap? command;

  /// `app.notify` payload emitted before any text; with an empty [text]
  /// the reply is notification-only (no assistant message).
  final JsonMap? notification;

  /// `ui.patch` payloads (without surfaceId) emitted after the surface, one
  /// per [patchDelay], to demo live updates.
  final List<JsonMap> patches;

  static _Reply greeting() => const _Reply(
    text:
        'Hi! I\'m Acme\'s assistant. I can find flights and hotels, show your sales, or help with an order. What do you need?',
  );

  static _Reply forInput(
    String? text,
    Object? value, {
    bool sampleMedia = false,
  }) {
    final intent = value is Map ? value['intent'] as String? : null;
    if (value is Map && value.containsKey('formId')) {
      return const _Reply(
        text:
            'Thanks! We\'ll call you at the time you picked. You\'ll get a confirmation email shortly.',
      );
    }
    switch (intent) {
      case 'rate_delivery':
        final stars = value is Map ? value['rating'] : null;
        return _Reply(
          text:
              'Thanks for rating the delivery${stars == null ? '' : ' $stars/5'}! I have passed it on to the courier team.',
        );
      case 'change_hotel':
        return _Reply(
          text: 'Sure. Here are two alternatives near Shibuya:',
          surface: KletsoFixtures.hotelCard,
        );
      case 'show_cart':
        return const _Reply(
          text:
              'Your cart: Trail Runner 2 (₹1,899) and Everyday Tote (₹1,299). Total ₹3,198.',
        );
      case 'select_flight':
        return _Reply(
          text:
              'Great choice. NH873 is held for 20 minutes. Anything else I can do?',
          surface: KletsoFixtures.quickReplies,
        );
      case 'book':
        return const _Reply(
          text:
              'Booked! Shibuya Grand Hotel, 2 nights. The confirmation is on its way to your inbox.',
        );
      case 'add_to_cart':
        return _Reply(
          text: 'Added to your cart. Want to keep browsing or check out?',
          surface: KletsoFixtures.quickReplies,
        );
      case 'notify_when_in_stock':
        return const _Reply(
          text:
              'You\'re on the list. I\'ll ping you the moment Steel Bottle 750 is back.',
        );
      case 'show_sales':
        return _sales();
      case 'track_order':
        return _order();
      case 'report_problem':
        return const _Reply(
          text:
              'Sorry about that. I\'ve flagged order ORD-4521 to the team; someone will reach out within the hour.',
        );
      case 'sales_by_product':
        return const _Reply(
          text:
              'By product this month:\n\n1. **Trail Runner 2** — \$24,300\n2. **Everyday Tote** — \$18,650\n3. **Steel Bottle 750** — \$11,200\n4. Everything else — \$7,800',
        );
      case 'handoff':
        return _handoff();
    }
    final t = (text ?? '').toLowerCase();
    if (t.contains('flight')) {
      return _Reply(
        text: 'Here\'s the best option for tomorrow morning:',
        tool: const _Tool(
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
    }
    if (t.contains('hotel')) {
      return _Reply(
        text: 'This one is a strong match near the station:',
        tool: const _Tool(
          'search_hotels',
          <String, Object?>{'area': 'Shibuya', 'nights': 2},
          result: <String, Object?>{'count': 12, 'best': 'h_1'},
        ),
        surface: KletsoFixtures.hotelCard,
      );
    }
    if (t.contains('product') || t.contains('under')) {
      return _Reply(
        text: 'Here is what I found in the catalogue:',
        tool: const _Tool(
          'search_products',
          <String, Object?>{'maxPrice': 2000, 'currency': 'INR'},
          result: <String, Object?>{'count': 3},
        ),
        surface: KletsoFixtures.productCards,
      );
    }
    if (t.contains('sales') || t.contains('chart') || t.contains('revenue')) {
      return _sales();
    }
    if (t.contains('where') ||
        t.contains('map') ||
        t.contains('courier') ||
        t.contains('deliver') ||
        t.contains('video') ||
        t.contains('audio')) {
      return _Reply(
        text:
            'Your courier is about 15 minutes away. Here is everything for the delivery:',
        tool: const _Tool(
          'track_shipment',
          <String, Object?>{'orderId': 'ORD-4521'},
          result: <String, Object?>{'eta': 15, 'status': 'out_for_delivery'},
        ),
        surface: _Reply.mediaHub(sampleMedia: sampleMedia),
      );
    }
    if (t.contains('open trail') ||
        t.contains('take me to') ||
        t.contains('show me the page')) {
      return const _Reply(
        text: 'Opening Trail Runner 2 for you.',
        command: <String, Object?>{
          'name': 'open_product',
          'args': <String, Object?>{'sku': 'SKU-1001'},
          'closeChat': true,
        },
      );
    }
    if (t.contains('trip') ||
        t.contains('plan') ||
        t.contains('itinerary') ||
        t.contains('tabs')) {
      return _Reply(
        text:
            'Here is where your Osaka trip stands (payment is going through now):',
        surface: KletsoFixtures.tripPlan,
        patches: <JsonMap>[
          <String, Object?>{
            'data': <String, Object?>{
              'plan': <String, Object?>{
                'progress': 0.75,
                'detail': '3 of 4 steps done',
              },
            },
            'components': <String, Object?>{
              'steps': <String, Object?>{
                'type': 'steps',
                'props': <String, Object?>{
                  'orientation': 'vertical',
                  'items': <Object?>[
                    <String, Object?>{
                      'id': 's1',
                      'title': 'Flight selected',
                      'subtitle': 'ANA NH873 · 08:15',
                      'status': 'done',
                      'timestamp': 'Today 12:01',
                    },
                    <String, Object?>{
                      'id': 's2',
                      'title': 'Hotel booked',
                      'subtitle': 'Shibuya Grand · 2 nights',
                      'status': 'done',
                      'timestamp': 'Today 12:04',
                    },
                    <String, Object?>{
                      'id': 's3',
                      'title': 'Payment',
                      'subtitle': 'Charged ¥42,600',
                      'status': 'done',
                      'timestamp': 'Just now',
                    },
                    <String, Object?>{
                      'id': 's4',
                      'title': 'Tickets issued',
                      'subtitle': 'Generating e-tickets…',
                      'status': 'current',
                    },
                  ],
                },
              },
            },
          },
          <String, Object?>{
            'data': <String, Object?>{
              'plan': <String, Object?>{
                'progress': 1.0,
                'detail': 'All done · tickets sent by email',
              },
            },
            'components': <String, Object?>{
              'steps': <String, Object?>{
                'type': 'steps',
                'props': <String, Object?>{
                  'orientation': 'vertical',
                  'items': <Object?>[
                    <String, Object?>{
                      'id': 's1',
                      'title': 'Flight selected',
                      'subtitle': 'ANA NH873 · 08:15',
                      'status': 'done',
                      'timestamp': 'Today 12:01',
                    },
                    <String, Object?>{
                      'id': 's2',
                      'title': 'Hotel booked',
                      'subtitle': 'Shibuya Grand · 2 nights',
                      'status': 'done',
                      'timestamp': 'Today 12:04',
                    },
                    <String, Object?>{
                      'id': 's3',
                      'title': 'Payment',
                      'subtitle': 'Charged ¥42,600',
                      'status': 'done',
                      'timestamp': 'Just now',
                    },
                    <String, Object?>{
                      'id': 's4',
                      'title': 'Tickets issued',
                      'subtitle': 'Sent to ada@example.com',
                      'status': 'done',
                      'timestamp': 'Just now',
                    },
                  ],
                },
              },
            },
          },
        ],
      );
    }
    if (t.contains('cancel')) {
      return _Reply(
        text: 'I can cancel ORD-4521. Please confirm:',
        confirmTool: const _Tool('cancel_order', <String, Object?>{
          'orderId': 'ORD-4521',
        }, callId: 'call_01J8CANCEL0001'),
        surface: KletsoFixtures.confirm,
      );
    }
    if (t.contains('callback') || t.contains('call me') || t.contains('form')) {
      return _Reply(
        text: 'Sure, tell me when to call:',
        surface: KletsoFixtures.form,
      );
    }
    if (t.contains('order') || t.contains('track') || t.contains('table')) {
      return _order();
    }
    if (t.contains('human') ||
        t.contains('agent') ||
        t.contains('support') ||
        t.contains('person')) {
      return _handoff();
    }
    if (t.contains('error') || t.contains('fail')) {
      return const _Reply(
        text: '',
        error: 'The model provider returned 503. Please try again.',
      );
    }
    if (t.contains('long')) {
      return const _Reply(
        text:
            'Here is a longer answer so you can see wrapping and streaming. Kletso renders **markdown** with *emphasis*, `code`, lists:\n\n- one\n- two\n- three\n\nand [links](https://acme.com/help), but never raw HTML. Bot output is untrusted, so only allowlisted hosts are clickable.',
      );
    }
    return _Reply(
      text:
          'You said: "${text ?? ''}". I can help with flights, hotels, products, sales or your orders.',
      surface: KletsoFixtures.quickReplies,
    );
  }

  /// The media-hub fixture with the countdown moved to 15 minutes from now
  /// so the live timer has something to count.
  static Object mediaHub({bool sampleMedia = false}) {
    final json = KletsoSurface.fromJson(KletsoFixtures.mediaHub).toJson();
    final components = Map<String, Object?>.of(
      json['components']! as Map<String, Object?>,
    );
    final eta = Map<String, Object?>.of(
      components['eta']! as Map<String, Object?>,
    );
    final props = Map<String, Object?>.of(
      eta['props']! as Map<String, Object?>,
    );
    props['endsAt'] = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 15))
        .toIso8601String();
    eta['props'] = props;
    components['eta'] = eta;
    if (sampleMedia) {
      // Public sample files so real players have something to play in demos.
      const base = 'https://flutter.github.io/assets-for-api-docs/assets';
      final video = Map<String, Object?>.of(
        components['video']! as Map<String, Object?>,
      );
      final vp = Map<String, Object?>.of(
        video['props']! as Map<String, Object?>,
      );
      vp['src'] = '$base/videos/butterfly.mp4';
      vp.remove('poster');
      vp['durationSeconds'] = 7;
      video['props'] = vp;
      components['video'] = video;
      final audio = Map<String, Object?>.of(
        components['audio']! as Map<String, Object?>,
      );
      final ap = Map<String, Object?>.of(
        audio['props']! as Map<String, Object?>,
      );
      ap['src'] = '$base/audio/rooster.mp3';
      ap['durationSeconds'] = 3;
      audio['props'] = ap;
      components['audio'] = audio;
    }
    json['components'] = components;
    return json;
  }

  static _Reply _sales() => _Reply(
    text: 'Sales are up this month. Here\'s the weekly picture:',
    tool: const _Tool(
      'get_sales',
      <String, Object?>{'period': '2026-09', 'groupBy': 'week'},
      result: <String, Object?>{'total': 61950, 'currency': 'USD'},
    ),
    surface: KletsoFixtures.chart,
  );

  static _Reply _order() => _Reply(
    text: 'Here\'s where order ORD-4521 stands:',
    tool: const _Tool(
      'get_order',
      <String, Object?>{'orderId': 'ORD-4521'},
      result: <String, Object?>{'status': 'shipped'},
    ),
    surface: KletsoFixtures.catalogAll,
  );

  static _Reply _handoff() => const _Reply(
    text:
        'Of course. I\'m connecting you with the Acme support team now; they have the full context of this chat.',
    handoff: true,
  );
}

final class _FakeSocket implements KletsoSocket {
  _FakeSocket(this._backend, this._session);

  final KletsoFakeBackend _backend;
  final _Session _session;
  final StreamController<KletsoServerFrame> _frames =
      StreamController<KletsoServerFrame>();
  final Completer<KletsoCloseInfo> _done = Completer<KletsoCloseInfo>();
  StreamSubscription<KletsoEventEnvelope>? _liveSub;
  String? _conversationId;
  int _readySeq = 0;
  int _delivered = 0;
  bool _closed = false;

  @override
  int get readySeq => _readySeq;

  @override
  Stream<KletsoServerFrame> get frames => _frames.stream;

  @override
  Future<KletsoCloseInfo> get done => _done.future;

  /// Session-wide delivery while no conversation is attached.
  StreamSubscription<(String, KletsoEventEnvelope)>? _userSub;

  void _listenUnattached() {
    _userSub ??= _backend._userEvents.stream
        .where((t) => t.$1 == _session.endUserId)
        .listen((t) => _deliver(t.$2));
  }

  void _attach(String conversationId, int after) {
    unawaited(_liveSub?.cancel());
    unawaited(_userSub?.cancel());
    _userSub = null;
    _conversationId = conversationId;
    final conv = _backend._conversations[conversationId];
    if (conv == null) {
      _push(
        const KletsoErrorFrame(
          code: 'not_found',
          message: 'unknown conversation',
        ),
      );
      _readySeq = 0;
      return;
    }
    _readySeq = conv.seq;
    // Replay, then live. Replay is delivered asynchronously so `ready`
    // semantics match the real server (ready first, then frames).
    final replay = conv.log.where((e) => e.seq > after).toList(growable: false);
    _liveSub = conv.live.stream.listen((e) => _deliver(e));
    scheduleMicrotask(() {
      for (final e in replay) {
        _deliver(e);
      }
    });
  }

  void _deliver(KletsoEventEnvelope e) {
    if (_closed) return;
    final s = _backend.scenario;
    _delivered++;
    _push(KletsoEventFrame(e));
    final dup = s.duplicateEveryNth;
    if (dup != null && _delivered % dup == 0) _push(KletsoEventFrame(e));
    final expire = s.expireTokenAfterEvents;
    if (expire != null &&
        !_backend._expired &&
        _delivered >= expire &&
        _backend._handshakes == 1) {
      _backend._expired = true;
      _session.expired = true;
      _serverClose(KletsoCloseCodes.tokenExpired, 'token expired');
      return;
    }
    final drop = s.dropSocketAfterEvents;
    if (drop != null && _delivered >= drop) {
      _serverClose(s.dropSocketCloseCode, 'simulated drop');
    }
  }

  void _push(KletsoServerFrame frame) {
    if (_closed) return;
    _frames.add(frame);
  }

  void _serverClose(int code, String reason) {
    if (_closed) return;
    _closed = true;
    unawaited(_liveSub?.cancel());
    unawaited(_userSub?.cancel());
    _backend._forget(this);
    unawaited(_frames.close());
    if (!_done.isCompleted) _done.complete(KletsoCloseInfo(code, reason));
  }

  @override
  Future<void> send(KletsoClientFrame frame) async {
    if (_closed) throw const KletsoNetworkException('socket closed');
    _backend._sent.add(frame);
    switch (frame) {
      case KletsoPingFrame():
        _push(const KletsoPongFrame());
      case KletsoSwitchFrame(:final conversationId, :final after):
        _attach(conversationId, after);
        _push(KletsoReadyFrame(seq: _readySeq, conversationId: conversationId));
      case KletsoMessageFrame():
        final conv = _backend._conversations[_conversationId];
        if (conv == null) {
          _push(
            const KletsoErrorFrame(
              code: 'invalid_request',
              message: 'no conversation attached',
            ),
          );
        } else {
          conv.onMessage(frame);
        }
      case KletsoActionFrame():
        _backend._conversations[_conversationId]?.onAction(frame);
      case KletsoContextFrame(:final merge, :final replace):
        if (replace != null) _session.context.clear();
        _session.context.addAll(merge ?? replace ?? const <String, Object?>{});
      case KletsoTrackFrame() || KletsoScreenFrame():
        _backend._fireTrigger(_session, frame);
      case KletsoTypingFrame() || KletsoAuthFrame():
        break;
    }
  }

  @override
  Future<void> close([
    int code = KletsoCloseCodes.normal,
    String reason = '',
  ]) async {
    _serverClose(code, reason);
  }
}
