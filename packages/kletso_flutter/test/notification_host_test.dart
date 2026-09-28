import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

Future<(KletsoClient, KletsoFakeBackend)> connect(WidgetTester tester) async {
  late KletsoClient client;
  late KletsoFakeBackend backend;
  await tester.runAsync(() async {
    backend = KletsoFakeBackend();
    client = KletsoClient(
      KletsoConfig(
        publishableKey: 'kl_pub_test',
        agentId: KletsoFakeBackend.agentId,
        logLevel: KletsoLogLevel.none,
      ),
      api: backend,
      transport: backend,
    );
    await client.identifyAnonymous();
    await client.startConversation();
  });
  return (client, backend);
}

Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

Widget app(KletsoClient client, {List<Widget> body = const <Widget>[]}) =>
    MaterialApp(
      navigatorKey: navigator,
      theme: KletsoTheme.light(
        useHostFont: true,
      ).materialTheme(ThemeData.light()),
      builder: (context, child) =>
          KletsoNotificationHost(client: client, child: child!),
      home: Scaffold(body: Column(children: body)),
    );

void main() {
  testWidgets(
    'silent app event → banner; tap opens the chat on the notification\'s conversation',
    (tester) async {
      tallViewport(tester);
      final (client, _) = await connect(tester);
      final outcomes = <KletsoNotificationOutcome>[];
      client.ui.notificationResults.listen((r) => outcomes.add(r.outcome));
      client.ui.contextProvider = () => navigator.currentContext;
      await tester.pumpWidget(app(client));
      await settle(tester);

      client.track('geofence_entered', <String, Object?>{'store': 'Shibuya'});
      await settle(tester, 40);
      expect(find.byType(KletsoNotificationBanner), findsOneWidget);
      expect(find.text('You are near Acme Shibuya'), findsOneWidget);
      expect(find.byType(KletsoChat), findsNothing, reason: 'no chat yet');
      expect(outcomes, <KletsoNotificationOutcome>[
        KletsoNotificationOutcome.shown,
      ]);

      await tester.tap(find.text('You are near Acme Shibuya'));
      await settle(tester, 40);
      expect(find.byType(KletsoNotificationBanner), findsNothing);
      expect(find.byType(KletsoChat), findsOneWidget);
      expect(client.ui.isOpen, isTrue);
      expect(outcomes.last, KletsoNotificationOutcome.tapped);
      // the agent's proactive turn is in the open chat
      expect(find.textContaining('SHIBUYA10'), findsOneWidget);

      client.close();
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets('banner auto-dismisses after its ttl and can be closed by hand', (
    tester,
  ) async {
    tallViewport(tester);
    final (client, backend) = await connect(tester);
    await tester.pumpWidget(app(client));
    await settle(tester);
    final user = client.session.value!.endUser.id;
    await tester.runAsync(() async {
      backend.notify(
        user,
        const KletsoAppNotification(
          notificationId: 'ntf_ttl',
          title: 'Short lived',
          ttl: Duration(seconds: 1),
        ),
      );
      backend.notify(
        user,
        const KletsoAppNotification(
          notificationId: 'ntf_manual',
          title: 'Manual',
        ),
      );
      backend.notify(
        user,
        const KletsoAppNotification(notificationId: 'ntf_manual', title: 'Dup'),
      );
    });
    await settle(tester);
    expect(find.text('Short lived'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Dup'), findsNothing, reason: 'deduped on id');
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(find.text('Short lived'), findsNothing);
    expect(find.text('Manual'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byType(KletsoNotificationBanner), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets(
    'alert channel shows a dialog; its local action runs with the notification origin',
    (tester) async {
      tallViewport(tester);
      final (client, _) = await connect(tester);
      final ran = <(String, KletsoActionOrigin, Object?)>[];
      client.registerAction('open_checkout', (args, ctx) async {
        ran.add(('open_checkout', ctx.origin, args['retry']));
      });
      client.ui.contextProvider = () => navigator.currentContext;
      await tester.pumpWidget(app(client));
      await settle(tester);

      client.track('payment_failed', <String, Object?>{'method': 'Visa'});
      await settle(tester, 40);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Payment did not go through'), findsOneWidget);
      expect(find.textContaining('Visa'), findsOneWidget);
      expect(client.messages.value, hasLength(1), reason: 'no chat message');

      await tester.tap(find.text('Retry payment'));
      await settle(tester, 40);
      expect(find.byType(AlertDialog), findsNothing);
      expect(ran.single, (
        'open_checkout',
        KletsoActionOrigin.notification,
        true,
      ));
      expect(find.byType(KletsoChat), findsNothing, reason: 'openChat false');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets(
    'system channel goes to the host notifier, falls back to a banner without one',
    (tester) async {
      tallViewport(tester);
      final (client, _) = await connect(tester);
      final outcomes = <KletsoNotificationOutcome>[];
      client.ui.notificationResults.listen((r) => outcomes.add(r.outcome));
      await tester.pumpWidget(app(client));
      await settle(tester);

      // no notifier → banner fallback with the inline steps surface
      client.track('order_shipped', <String, Object?>{'orderId': 'ORD-1'});
      await settle(tester, 40);
      expect(find.byType(KletsoNotificationBanner), findsOneWidget);
      expect(find.text('Out for delivery'), findsOneWidget);
      expect(outcomes.last, KletsoNotificationOutcome.bannerFallback);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      // notifier that shows it → nothing in-app
      final tray = <String>[];
      client.onSystemNotification = (n) async {
        tray.add(n.title);
        return true;
      };
      client.track('order_shipped', <String, Object?>{'orderId': 'ORD-2'});
      await settle(tester, 40);
      expect(tray, <String>['Order ORD-2 shipped']);
      expect(find.byType(KletsoNotificationBanner), findsNothing);
      expect(outcomes.last, KletsoNotificationOutcome.system);

      // notifier that declines → banner
      client.onSystemNotification = (n) async => false;
      client.track('order_shipped', <String, Object?>{'orderId': 'ORD-3'});
      await settle(tester, 40);
      expect(find.text('Order ORD-3 shipped'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets(
    'push payload → toast; silent notification opens the chat with no UI',
    (tester) async {
      tallViewport(tester);
      final (client, backend) = await connect(tester);
      client.ui.contextProvider = () => navigator.currentContext;
      await tester.pumpWidget(app(client));
      await settle(tester);
      final user = client.session.value!.endUser.id;
      await tester.runAsync(
        () => client.registerPushToken(
          const KletsoPushToken(platform: KletsoPushPlatform.fcm, token: 'fcm'),
        ),
      );
      final payload = backend.sendPush(
        user,
        const KletsoAppNotification(
          notificationId: 'ntf_toast',
          title: 'Flash sale',
          body: '1 hour left',
          channel: KletsoNotificationChannel.toast,
          action: KletsoUrlAction(
            id: 'go',
            url: 'https://acme.com/sale',
            label: 'Shop',
          ),
        ),
      );
      final opened = <Uri>[];
      client.onOpenUrl = (uri) async => opened.add(uri);
      expect(client.handlePushPayload(payload), isTrue);
      await settle(tester);
      expect(find.byType(KletsoNotificationToast), findsOneWidget);
      expect(find.textContaining('Flash sale'), findsOneWidget);
      await tester.tap(find.text('Shop'));
      await settle(tester);
      expect(opened.single.toString(), 'https://acme.com/sale');
      expect(find.byType(KletsoNotificationToast), findsNothing);

      await tester.runAsync(() async {
        backend.notify(
          user,
          const KletsoAppNotification(
            notificationId: 'ntf_silent',
            title: 'ignored',
            channel: KletsoNotificationChannel.silent,
            openChat: true,
          ),
        );
      });
      await settle(tester, 40);
      expect(find.text('ignored'), findsNothing);
      expect(find.byType(KletsoChat), findsOneWidget);
      client.close();
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );
}
