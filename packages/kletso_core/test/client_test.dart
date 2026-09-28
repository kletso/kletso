import 'dart:async';
import 'dart:convert';

import 'package:kletso_core/fake.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

import 'support/scripted_transport.dart';

Future<void> settle([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met in $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

KletsoClient client(KletsoFakeBackend backend, {KletsoConfig? config}) =>
    KletsoClient(
      config ?? testConfig(),
      api: backend,
      transport: backend,
      random: ZeroRandom(),
      device: const KletsoDevice(platform: 'test'),
    );

void main() {
  test(
    'anonymous session, greeting, streamed replies with surfaces and tool calls',
    () async {
      final backend = KletsoFakeBackend();
      final c = client(backend);
      final events = <KletsoEvent>[];
      c.events.listen(events.add);
      expect(c.isAuthenticated, isFalse);
      expect(() => c.startConversation(), throwsA(isA<KletsoStateException>()));
      await expectLater(
        c.send(const KletsoOutbound.text('x')),
        throwsA(isA<KletsoStateException>()),
      );

      await c.identifyAnonymous();
      expect(c.isAuthenticated, isTrue);
      expect(c.session.value!.agent.name, 'Acme Assistant');
      expect(c.session.value!.endUser.anonymous, isTrue);
      expect(c.connection.value, KletsoConnectionState.open);

      final conv = await c.ensureConversation();
      expect(c.activeConversation.value!.id, conv.id);
      expect(c.conversations.value.single.id, conv.id);
      await until(
        () =>
            c.messages.value.isNotEmpty &&
            c.messages.value.first.status == KletsoMessageStatus.complete,
      );
      expect(c.messages.value.single.isAssistant, isTrue);
      expect(c.messages.value.single.text, startsWith('Hi!'));
      expect(c.agentTyping.value, isFalse);

      await c.send(const KletsoOutbound.text('I need a flight to Osaka'));
      expect(c.messages.value.last.status, KletsoMessageStatus.pending);
      expect(c.messages.value.last.text, 'I need a flight to Osaka');
      await until(
        () =>
            c.messages.value.length == 3 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      final user = c.messages.value[1];
      expect(user.status, KletsoMessageStatus.complete);
      expect(user.id, startsWith('msg_'));
      final reply = c.messages.value.last;
      expect(reply.surfaces.single.surfaceId, 'sfc_01J8FLIGHT0001');
      expect(reply.toolCalls.single.name, 'search_flights');
      expect(reply.toolCalls.single.status, KletsoToolCallStatus.completed);
      expect(
        events.whereType<KletsoServerEvent>().map((e) => e.type),
        contains('ui.render'),
      );
      expect(
        events.whereType<KletsoConnectionChanged>().map((e) => e.state),
        containsAll([
          KletsoConnectionState.connecting,
          KletsoConnectionState.open,
        ]),
      );

      // actions post back as structured user turns
      await c.send(
        const KletsoOutbound.action(
          surfaceId: 'sfc_01J8FLIGHT0001',
          componentId: 'select',
          actionId: 'select',
          value: {'intent': 'select_flight'},
          label: 'Select ANA NH873',
        ),
      );
      await until(
        () =>
            c.messages.value.length == 5 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      expect(c.messages.value[3].text, 'Select ANA NH873');
      expect(c.messages.value[3].value, {'intent': 'select_flight'});
      expect(c.messages.value.last.text, startsWith('Great choice'));
      expect(
        c.messages.value.last.surfaces.single.surfaceId,
        'sfc_01J8CHIPS00001',
      );
      // conversation gets a title after a few messages
      expect(c.conversations.value.single.title, isNotNull);
      expect(c.activeConversation.value!.title, isNotNull);

      // value-only quick reply and form
      await c.send(
        const KletsoOutbound.value({
          'intent': 'show_sales',
        }, label: 'Show me sales'),
      );
      await until(
        () =>
            c.messages.value.length == 7 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      expect(
        c.messages.value.last.surfaces.single.surfaceId,
        'sfc_01J8CHART00001',
      );
      await c.send(
        KletsoOutbound.form(
          surfaceId: 's',
          componentId: 'form',
          actionId: 'submit',
          formId: 'f_callback',
          values: {'name': 'Ada'},
        ),
      );
      await until(
        () =>
            c.messages.value.length == 9 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      expect(c.messages.value[7].text, 'Form submitted');
      expect(c.messages.value.last.text, startsWith('Thanks!'));
      await c.dispose();
    },
  );

  test('confirm flow, handoff, error reply and typing indicator', () async {
    final backend = KletsoFakeBackend();
    final c = client(
      backend,
      config: testConfig().copyWith(
        typingIndicatorTtl: const Duration(milliseconds: 40),
      ),
    );
    await c.identifyAnonymous();
    await c.startConversation();
    await until(
      () =>
          c.messages.value.length == 1 &&
          c.messages.value.first.status == KletsoMessageStatus.complete,
    );
    await c.send(const KletsoOutbound.text('cancel my order'));
    await until(
      () =>
          c.messages.value.length == 3 &&
          c.messages.value.last.surfaces.isNotEmpty,
    );
    final ask = c.messages.value.last;
    expect(
      ask.toolCalls.single.status,
      KletsoToolCallStatus.awaitingConfirmation,
    );
    expect(ask.surfaces.single.components['confirm']!.type, 'confirm');
    await c.send(
      KletsoOutbound.confirm(
        surfaceId: ask.surfaces.single.surfaceId,
        componentId: 'confirm',
        actionId: 'yes',
        toolCallId: 'call_01J8CANCEL0001',
        approve: true,
      ),
    );
    await until(
      () =>
          c.messages.value.length == 5 &&
          c.messages.value.last.status == KletsoMessageStatus.complete,
    );
    expect(c.messages.value.last.text, startsWith('Done.'));
    expect(
      c.messages.value[2].toolCalls.single.status,
      KletsoToolCallStatus.completed,
    );

    final errors = <KletsoClientError>[];
    c.events.listen((e) {
      if (e is KletsoClientError) errors.add(e);
    });
    await c.send(const KletsoOutbound.text('please error'));
    await until(() => errors.isNotEmpty);
    expect(
      errors.single.exception,
      isA<KletsoServerException>().having(
        (e) => e.code,
        'code',
        'provider_error',
      ),
    );

    await c.send(const KletsoOutbound.text('talk to a human'));
    await until(
      () =>
          c.activeConversation.value!.status ==
          KletsoConversationStatus.handoff,
    );
    expect(
      c.conversations.value.first.status,
      KletsoConversationStatus.handoff,
    );

    // typing: set by agent.typing, cleared by message.created (assistant) and by TTL
    backend.emit(c.activeConversation.value!.id, 'agent.typing', {});
    await until(() => c.agentTyping.value);
    await until(
      () => !c.agentTyping.value,
      timeout: const Duration(seconds: 1),
    );
    await c.dispose();
  });

  test(
    'token expiry mid-stream: refresh, reconnect, no duplicate messages',
    () async {
      final backend = KletsoFakeBackend(
        scenario: const KletsoFakeScenario(expireTokenAfterEvents: 3),
      );
      final c = client(backend);
      final states = <KletsoConnectionState>[];
      c.connection.addListener(() => states.add(c.connection.value));
      await c.identifyAnonymous();
      final firstToken = c.session.value!.session.token;
      await c.startConversation();
      await c.send(const KletsoOutbound.text('show me products'));
      await until(
        () =>
            c.messages.value.length == 3 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      expect(
        c.session.value!.session.token,
        isNot(firstToken),
        reason: 'session was refreshed',
      );
      expect(states, contains(KletsoConnectionState.reconnecting));
      expect(c.connection.value, KletsoConnectionState.open);
      expect(backend.handshakes, greaterThanOrEqualTo(2));
      expect(c.messages.value.map((m) => m.id).toSet(), hasLength(3));
      expect(
        c.messages.value.last.surfaces.single.surfaceId,
        'sfc_01J8PRODUCTS01',
      );
      await c.dispose();
    },
  );

  test(
    'socket drops every few events and duplicate frames: transcript stays exact',
    () async {
      final backend = KletsoFakeBackend(
        scenario: const KletsoFakeScenario(
          dropSocketAfterEvents: 4,
          duplicateEveryNth: 2,
          failHandshakes: 1,
        ),
      );
      final c = client(backend);
      await c.identifyAnonymous();
      expect(
        backend.handshakes,
        2,
        reason: 'first handshake failed, second succeeded',
      );
      await c.startConversation();
      await c.send(const KletsoOutbound.text('hotel in shibuya'));
      await until(
        () =>
            c.messages.value.length == 3 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      final expected = backend
          .logOf(c.activeConversation.value!.id)
          .where((e) => e.type == 'message.created')
          .length;
      expect(c.messages.value, hasLength(expected));
      expect(
        c.messages.value.last.text,
        'This one is a strong match near the station:',
      );
      expect(c.messages.value.last.surfaces, hasLength(1));
      expect(backend.handshakes, greaterThan(3));
      await c.dispose();
    },
  );

  test(
    'auth failure surfaces from authenticate; rate limit surfaces as error',
    () async {
      final rejecting = KletsoFakeBackend(
        scenario: const KletsoFakeScenario(rejectToken: true),
      );
      final c1 = client(rejecting);
      await expectLater(
        c1.authenticate(token: 'jwt'),
        throwsA(isA<KletsoAuthException>()),
      );
      expect(c1.connection.value, KletsoConnectionState.closed);
      await c1.dispose();

      final limited = KletsoFakeBackend(
        scenario: const KletsoFakeScenario(rateLimitEveryNthMessage: 1),
      );
      final c2 = client(limited);
      final errors = <KletsoException>[];
      c2.events.listen((e) {
        if (e is KletsoClientError) errors.add(e.exception);
      });
      await c2.authenticate(token: 'jwt', onTokenExpired: () async => 'jwt2');
      expect(c2.session.value!.endUser.anonymous, isFalse);
      await c2.startConversation();
      await c2.send(const KletsoOutbound.text('hi'));
      await until(() => errors.any((e) => e is KletsoRateLimitException));
      await c2.dispose();
    },
  );

  test(
    'conversations: list, switch restores state instantly, seeded log, logout clears',
    () async {
      final backend = KletsoFakeBackend(
        scenario: const KletsoFakeScenario(
          seedConversationLog: true,
          greeting: false,
        ),
      );
      final c = client(backend);
      await c.identifyAnonymous();
      final seeded = await c.ensureConversation();
      expect(seeded.id, 'conv_01J8DEMO000001');
      await until(() => c.messages.value.length == 20);
      expect(
        c.messages.value.every((m) => m.status == KletsoMessageStatus.complete),
        isTrue,
      );
      final second = await c.startConversation(title: 'Second');
      expect(c.activeConversation.value!.id, second.id);
      expect(c.messages.value, isEmpty);
      await c.send(const KletsoOutbound.text('hello there'));
      await until(
        () =>
            c.messages.value.length == 2 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      await c.switchConversation(seeded.id);
      expect(
        c.messages.value,
        hasLength(20),
        reason: 'restored from cache without waiting',
      );
      await c.switchConversation(second.id);
      expect(c.messages.value, hasLength(2));
      final list = await c.listConversations();
      expect(list.map((x) => x.id), containsAll([seeded.id, second.id]));
      await expectLater(
        c.switchConversation('conv_nope'),
        throwsA(isA<KletsoStateException>()),
      );
      c.setContext({'plan': 'pro'});
      c.updateContext({'orderId': 'ORD1'});
      expect(c.context, {'plan': 'pro', 'orderId': 'ORD1'});
      c.track('cart_abandoned', {'value': 1});
      c.screen('checkout');
      c.useAgent('agt_sales');
      expect(c.activeAgentId, 'agt_sales');
      c.reportLocalAction(
        name: 'open_product',
        args: {'sku': 'x'},
        surfaceId: 's',
        componentId: 'p1',
        actionId: 'view',
        handled: true,
      );
      c.reportUnknownComponent(type: 'vendor.x', surfaceId: 's');
      await settle();
      final sent = <KletsoClientFrame>[];
      final sub = backend.sentFrames.listen(sent.add);
      c.track('again');
      await settle();
      expect(sent.single, isA<KletsoTrackFrame>());
      await sub.cancel();
      await c.logout();
      expect(c.isAuthenticated, isFalse);
      expect(c.messages.value, isEmpty);
      expect(c.conversations.value, isEmpty);
      expect(c.activeConversation.value, isNull);
      expect(c.session.value, isNull);
      expect(c.context, isEmpty);
      expect(c.connection.value, KletsoConnectionState.closed);
      // a new anonymous identity after logout
      await c.identifyAnonymous();
      expect(c.isAuthenticated, isTrue);
      await c.dispose();
      expect(() => c.setContext({}), throwsA(isA<KletsoStateException>()));
      await c.dispose(); // idempotent
    },
  );

  test('pause closes the socket and resume reconnects with replay', () async {
    final backend = KletsoFakeBackend();
    final c = client(backend);
    await c.identifyAnonymous();
    await c.startConversation();
    await until(
      () =>
          c.messages.value.length == 1 &&
          c.messages.value.first.status == KletsoMessageStatus.complete,
    );
    await c.pause();
    expect(c.connection.value, KletsoConnectionState.closed);
    expect(backend.openSockets, 0);
    // events that happen while paused are replayed on resume
    backend.emit(c.activeConversation.value!.id, 'agent.typing', {});
    await c.resume();
    await until(() => c.connection.value == KletsoConnectionState.open);
    expect(backend.openSockets, 1);
    await c.resume(); // no-op while connected
    await c.dispose();
  });

  test('triggers: track and screen make the agent speak first', () async {
    final backend = KletsoFakeBackend();
    final c = client(backend);
    final types = <String>[];
    c.events.listen((e) {
      if (e is KletsoServerEvent) types.add(e.type);
    });
    await c.identifyAnonymous();
    await c.startConversation();
    await until(
      () =>
          c.messages.value.length == 1 &&
          c.messages.value.first.status == KletsoMessageStatus.complete,
    );
    c.track('cart_abandoned', {'value': '₹3,198'});
    await until(
      () =>
          c.messages.value.length == 2 &&
          c.messages.value.last.status == KletsoMessageStatus.complete,
    );
    expect(types, contains('trigger.fired'));
    final nudge = c.messages.value.last;
    expect(nudge.isAssistant, isTrue);
    expect(nudge.text, contains('₹3,198'));
    expect(nudge.surfaces.single.components['cd']!.type, 'countdown');
    c.screen('checkout');
    await until(
      () =>
          c.messages.value.length == 3 &&
          c.messages.value.last.status == KletsoMessageStatus.complete,
    );
    expect(
      c.messages.value.last.surfaces.single.components['map']!.type,
      'map',
    );
    // a message about the delivery renders the same media hub
    await c.send(const KletsoOutbound.text('where is my courier'));
    await until(
      () =>
          c.messages.value.length == 5 &&
          c.messages.value.last.status == KletsoMessageStatus.complete,
    );
    expect(c.messages.value.last.toolCalls.single.name, 'track_shipment');
    expect(
      c.messages.value.last.surfaces.single.components.keys,
      containsAll(['map', 'video', 'audio', 'rating', 'eta']),
    );
    await c.dispose();
  });

  test(
    'a trigger before any conversation opens one and the device hears it',
    () async {
      final backend = KletsoFakeBackend();
      final c = client(backend);
      final types = <String>[];
      c.events.listen((e) {
        if (e is KletsoServerEvent) types.add(e.type);
      });
      await c.identifyAnonymous();
      expect(c.conversations.value, isEmpty);
      c.track('cart_abandoned', {'value': 42});
      await until(() => types.contains('message.completed'));
      expect(
        types,
        containsAll(['conversation.created', 'trigger.fired', 'ui.render']),
      );
      expect(
        c.conversations.value,
        hasLength(1),
        reason: 'learned from conversation.created',
      );
      expect(c.activeConversation.value, isNull, reason: 'nothing opened yet');
      final conv = await c.ensureConversation();
      expect(conv.id, c.conversations.value.single.id);
      await until(
        () =>
            c.messages.value.isNotEmpty &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      expect(
        c.messages.value.single.surfaces.single.components['cd']!.type,
        'countdown',
      );
      // replay after attach must not duplicate what arrived unattached
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.messages.value, hasLength(1));
      await c.dispose();
    },
  );

  test(
    'app → server: context updates and local-action analytics reach the runtime',
    () async {
      final backend = KletsoFakeBackend();
      final c = client(backend);
      await c.identifyAnonymous();
      final user = c.session.value!.endUser.id;
      c.setContext({'plan': 'pro'});
      c.updateContext({'cartValue': 3198});
      await until(() => backend.contextOf(user)['cartValue'] == 3198);
      expect(backend.contextOf(user), {'plan': 'pro', 'cartValue': 3198});
      c.setContext({'screen': 'checkout'});
      await until(() => !backend.contextOf(user).containsKey('plan'));
      expect(backend.contextOf(user), {
        'screen': 'checkout',
      }, reason: 'replace semantics');

      await c.startConversation();
      await until(
        () =>
            c.messages.value.length == 1 &&
            c.messages.value.first.status == KletsoMessageStatus.complete,
      );
      final local = <KletsoLocalActionRan>[];
      c.events.listen((e) {
        if (e is KletsoLocalActionRan) local.add(e);
      });
      c.reportLocalAction(
        name: 'open_product',
        args: {'sku': 'SKU-1001'},
        surfaceId: 'sfc_x',
        componentId: 'p1',
        actionId: 'view',
        handled: true,
      );
      await until(() => local.isNotEmpty);
      expect(local.single.handled, isTrue);
      final conv = c.activeConversation.value!.id;
      await until(() => backend.logOf(conv).any((e) => e.type == 'ui.action'));
      final echoed =
          backend.logOf(conv).firstWhere((e) => e.type == 'ui.action').payload
              as KletsoUiActionEvent;
      expect(echoed.actionId, 'view');
      expect((echoed.value! as Map)['local'], 'open_product');
      expect(
        backend.logOf(conv).where((e) => e.type == 'message.created'),
        hasLength(1),
        reason: 'analytics never becomes a user turn',
      );
      await c.dispose();
    },
  );

  test('server → app: app.command arrives as a typed payload', () async {
    final backend = KletsoFakeBackend();
    final c = client(backend);
    final commands = <KletsoAppCommand>[];
    c.events.listen((e) {
      if (e is KletsoServerEvent && e.payload is KletsoAppCommand) {
        commands.add(e.payload as KletsoAppCommand);
      }
    });
    await c.identifyAnonymous();
    await c.startConversation();
    await c.send(const KletsoOutbound.text('open trail runner'));
    await until(() => commands.isNotEmpty);
    expect(commands.single.name, 'open_product');
    expect(commands.single.args, {'sku': 'SKU-1001'});
    expect(commands.single.closeChat, isTrue);
    expect(
      c.config.allowServerCommands,
      isFalse,
      reason: 'core only delivers; the Flutter layer decides',
    );
    await c.dispose();
  });

  test(
    'live surface: trip plan receives patches that move the progress bar and steps',
    () async {
      final backend = KletsoFakeBackend();
      final c = client(backend);
      await c.identifyAnonymous();
      await c.startConversation();
      await c.send(const KletsoOutbound.text('my trip plan'));
      await until(() {
        final s = c.messages.value.lastOrNull?.surfaces.firstOrNull;
        return s != null &&
            s.resolveNode(s.node('progress')!).number('value') == 1.0;
      });
      final s = c.messages.value.last.surfaces.single;
      expect(
        s.node('steps')!.mapList('items').every((i) => i['status'] == 'done'),
        isTrue,
      );
      expect(
        backend
            .logOf(c.activeConversation.value!.id)
            .where((e) => e.type == 'ui.patch'),
        hasLength(2),
      );
      await c.dispose();
    },
  );

  test(
    'silent app events → app.notify: banner + chat turn, alert-only, system',
    () async {
      final backend = KletsoFakeBackend();
      final c = client(backend);
      final notes = <KletsoNotification>[];
      c.notifications.listen(notes.add);
      await c.identifyAnonymous();
      await c.startConversation();
      await until(
        () =>
            c.messages.value.length == 1 &&
            c.messages.value.first.status == KletsoMessageStatus.complete,
      );
      // geofence: notification first, then the agent speaks in the chat
      c.track('geofence_entered', {'store': 'Shibuya'});
      await until(() => notes.length == 1);
      expect(notes.single.source, KletsoNotificationSource.live);
      expect(notes.single.channel, KletsoNotificationChannel.banner);
      expect(notes.single.payload.openChat, isTrue);
      expect(notes.single.title, contains('Shibuya'));
      expect(notes.single.conversationId, c.activeConversation.value!.id);
      await until(
        () =>
            c.messages.value.length == 2 &&
            c.messages.value.last.status == KletsoMessageStatus.complete,
      );
      expect(c.messages.value.last.text, contains('SHIBUYA10'));
      // payment failed: alert with a local action and no chat message
      c.track('payment_failed', {'method': 'Visa'});
      await until(() => notes.length == 2);
      expect(notes.last.channel, KletsoNotificationChannel.alert);
      expect(
        (notes.last.payload.action! as KletsoLocalAction).name,
        'open_checkout',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.messages.value, hasLength(2), reason: 'notification-only');
      // order shipped: system channel with an inline surface
      c.track('order_shipped', {'orderId': 'ORD-77'});
      await until(() => notes.length == 3);
      expect(notes.last.channel, KletsoNotificationChannel.system);
      expect(notes.last.title, contains('ORD-77'));
      expect(notes.last.payload.parseSurface(), isA<KletsoSurfaceOk>());
      await c.dispose();
    },
  );

  test(
    'push token registration and push payload handoff with dedupe',
    () async {
      final backend = KletsoFakeBackend();
      final c = client(backend);
      final notes = <KletsoNotification>[];
      c.notifications.listen(notes.add);
      await expectLater(
        c.registerPushToken(
          const KletsoPushToken(platform: KletsoPushPlatform.fcm, token: 't'),
        ),
        throwsA(isA<KletsoStateException>()),
        reason: 'needs a session',
      );
      await c.identifyAnonymous();
      final userId = c.session.value!.endUser.id;
      expect(
        () => backend.sendPush(
          userId,
          const KletsoAppNotification(notificationId: 'ntf_x', title: 'x'),
        ),
        throwsA(isA<KletsoStateException>()),
        reason: 'no token yet',
      );
      await c.registerPushToken(
        const KletsoPushToken(
          platform: KletsoPushPlatform.fcm,
          token: 'fcm-abc',
        ),
      );
      expect(backend.pushTokens[userId]!.token, 'fcm-abc');
      expect(c.pushToken!.platform, KletsoPushPlatform.fcm);

      // the runtime sends a push while the app is in the background; the host
      // hands the data map to the client
      final payload = backend.sendPush(
        userId,
        const KletsoAppNotification(
          notificationId: 'ntf_push1',
          title: 'Flash sale',
          body: 'Ends in an hour',
          channel: KletsoNotificationChannel.toast,
          openChat: true,
        ),
      );
      expect(payload['kletso'], isA<String>());
      expect(c.handlePushPayload(payload), isTrue);
      await until(() => notes.length == 1);
      expect(notes.single.source, KletsoNotificationSource.push);
      expect(notes.single.channel, KletsoNotificationChannel.toast);
      expect(notes.single.conversationId, startsWith('conv_'));
      // duplicates (same notificationId) and foreign pushes are ignored
      expect(c.handlePushPayload(payload), isFalse);
      expect(c.handlePushPayload({'foo': 'bar'}), isFalse);
      expect(c.handlePushPayload({'kletso': 'not json'}), isFalse);
      expect(c.handlePushPayload({'kletso': '{"id":"evt_1"}'}), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notes, hasLength(1));
      // a map form works too
      final decoded = jsonDecode(payload['kletso']! as String) as Map;
      decoded['data'] = {
        ...decoded['data'] as Map,
        'notificationId': 'ntf_push2',
      };
      expect(c.handlePushPayload({'kletso': decoded}), isTrue);
      await until(() => notes.length == 2);
      // live server-originated notify arrives too and dedupes against push
      backend.notify(
        userId,
        const KletsoAppNotification(notificationId: 'ntf_push2', title: 'dup'),
      );
      backend.notify(
        userId,
        const KletsoAppNotification(notificationId: 'ntf_live3', title: 'live'),
      );
      await until(() => notes.length == 3);
      expect(notes.last.title, 'live');
      expect(notes.last.source, KletsoNotificationSource.live);
      expect(backend.pushesSent, 1);
      await c.unregisterPushToken();
      expect(backend.pushTokens, isEmpty);
      expect(c.pushToken, isNull);
      await c.dispose();
    },
  );

  test('Kletso singleton', () async {
    expect(() => Kletso.instance, throwsA(isA<KletsoStateException>()));
    expect(Kletso.isInitialized, isFalse);
    final backend = KletsoFakeBackend();
    final a = await Kletso.init(testConfig(), api: backend, transport: backend);
    expect(Kletso.instance, same(a));
    final b = await Kletso.init(testConfig(), api: backend, transport: backend);
    expect(Kletso.instance, same(b));
    expect(
      () => a.setContext({}),
      throwsA(isA<KletsoStateException>()),
      reason: 'previous instance disposed',
    );
    await Kletso.reset();
    expect(Kletso.isInitialized, isFalse);
  });

  test('config validates keys and exposes derived values', () {
    expect(
      () => KletsoConfig(publishableKey: 'kl_sec_x', agentId: 'a'),
      throwsArgumentError,
    );
    expect(
      () => KletsoConfig(publishableKey: 'kl_pub_x', agentId: ''),
      throwsArgumentError,
    );
    final cfg = KletsoConfig(publishableKey: 'kl_pub_x', agentId: 'a');
    expect(cfg.apiRoot.toString(), 'https://api.kletso.ai/v1');
    expect(
      cfg.copyWith(transport: KletsoTransportMode.sse).transport,
      KletsoTransportMode.sse,
    );
    expect(cfg.toString(), contains('agent: a'));
    expect(
      KletsoConfig(
        publishableKey: 'kl_pub_x',
        agentId: 'a',
        baseUrl: Uri.parse('http://localhost:8787'),
      ).apiRoot.toString(),
      'http://localhost:8787/v1',
    );
  });

  test(
    'default transports are built per mode without touching the network',
    () async {
      for (final mode in KletsoTransportMode.values) {
        final c = KletsoClient(
          testConfig(transport: mode),
          logger: (level, message, {error, stackTrace}) {},
        );
        expect(c.config.transport, mode);
        await c.dispose();
      }
    },
  );

  test('ids are time-ordered ULIDs', () {
    final g = KletsoIdGenerator();
    final a = g.clientId();
    final b = g.clientId();
    expect(a, startsWith('c_'));
    expect(a.length, 28);
    expect(a, isNot(b));
    expect(a.substring(2, 12).compareTo(b.substring(2, 12)) <= 0, isTrue);
    expect(g.anonymousId(), startsWith('anon_'));
  });

  test('value notifier semantics', () {
    final n = KletsoValueNotifier<int>(1);
    var calls = 0;
    void listener() => calls++;
    n.addListener(listener);
    n.value = 1;
    expect(calls, 0);
    n.value = 2;
    expect(calls, 1);
    expect(n.hasListeners, isTrue);
    n.removeListener(listener);
    n.value = 3;
    expect(calls, 1);
    n.dispose();
    n.value = 4;
    expect(n.value, 3);
    n.addListener(listener);
    expect(n.hasListeners, isFalse);
  });

  test('memory token store', () async {
    final s = KletsoMemoryTokenStore();
    expect(await s.read('k'), isNull);
    await s.write('k', 'v');
    expect(await s.read('k'), 'v');
    await s.delete('k');
    expect(await s.read('k'), isNull);
  });

  test('exceptions describe themselves', () {
    expect(
      const KletsoNetworkException('down').toString(),
      'KletsoNetworkException: down',
    );
    expect(const KletsoNetworkException('x').retryable, isTrue);
    expect(const KletsoTimeoutException('x').retryable, isTrue);
    expect(const KletsoAuthException('x').retryable, isFalse);
    expect(const KletsoAuthException('x', expired: true).retryable, isTrue);
    expect(const KletsoRateLimitException('x').retryable, isTrue);
    expect(const KletsoProtocolException('x').retryable, isFalse);
    expect(const KletsoToolException('x', toolName: 't').retryable, isFalse);
    expect(const KletsoWorkflowException('x', runId: 'r').retryable, isFalse);
    expect(const KletsoStateException('x').retryable, isFalse);
    expect(
      const KletsoQueueOverflowException('x', droppedClientId: 'c').retryable,
      isTrue,
    );
  });
}
