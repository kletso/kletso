import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

Future<KletsoClient> connect(
  WidgetTester tester, {
  bool allowCommands = true,
}) async {
  late KletsoClient client;
  await tester.runAsync(() async {
    final backend = KletsoFakeBackend();
    client = KletsoClient(
      KletsoConfig(
        publishableKey: 'kl_pub_test',
        agentId: KletsoFakeBackend.agentId,
        logLevel: KletsoLogLevel.none,
        allowServerCommands: allowCommands,
      ),
      api: backend,
      transport: backend,
    );
    await client.identifyAnonymous();
    await client.startConversation();
  });
  return client;
}

Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('client.close() dismisses the sheet opened by open()', (
    tester,
  ) async {
    tallViewport(tester);
    final client = await connect(tester);
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: KletsoTheme.light(
          useHostFont: true,
        ).materialTheme(ThemeData.light()),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              hostContext = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(client.ui.isOpen, isFalse);
    client.close(); // no-op when nothing is open
    client.open(hostContext).ignore();
    await settle(tester);
    expect(find.byType(KletsoChat), findsOneWidget);
    expect(client.ui.isOpen, isTrue);
    client.close();
    await settle(tester);
    expect(find.byType(KletsoChat), findsNothing);
    expect(client.ui.isOpen, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets(
    'a local action handler can change app state, close the chat and talk to the agent',
    (tester) async {
      tallViewport(tester);
      final client = await connect(tester);
      final routed = <String>[];
      client.registerAction('open_product', (args, ctx) async {
        routed.add(args['sku'] as String);
        expect(ctx.origin, KletsoActionOrigin.surface);
        ctx.client!.close();
        await ctx.client!.send(const KletsoOutbound.text('opened the product'));
      });
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: KletsoTheme.light(
            useHostFont: true,
          ).materialTheme(ThemeData.light()),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                hostContext = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      // built-in fallback for acme.productCard is the fallback text; register a
      // minimal builder that exposes the local 'view' action.
      client.registerComponent(
        'acme.productCard',
        (ctx, node) => TextButton(
          onPressed: () => ctx.executeAction('view'),
          child: Text('card ${node.string('sku')}'),
        ),
      );
      await settle(tester);
      client.open(hostContext).ignore();
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'show me products');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await settle(tester, 40);
      await tester.tap(find.text('card SKU-1001'));
      await settle(tester, 40);
      expect(routed, ['SKU-1001']);
      expect(
        find.byType(KletsoChat),
        findsNothing,
        reason: 'handler closed the chat',
      );
      expect(
        client.messages.value.any(
          (m) => m.isUser && m.text == 'opened the product',
        ),
        isTrue,
        reason: 'handler also messaged the agent',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets(
    'server app.command runs a registered handler only when allowed and with a context',
    (tester) async {
      tallViewport(tester);
      final client = await connect(tester);
      final results = <KletsoCommandResult>[];
      client.ui.commandResults.listen(results.add);
      final ran = <Map<String, Object?>>[];
      await tester.pumpWidget(harness(const SizedBox()));
      // no contextProvider yet → noContext
      client.registerAction('open_product', (args, ctx) async {
        ran.add(args);
        expect(ctx.origin, KletsoActionOrigin.server);
        expect(ctx.surface, isNull);
      });
      await tester.runAsync(
        () => client.send(const KletsoOutbound.text('open trail runner')),
      );
      await settle(tester, 60);
      expect(results.map((r) => r.outcome), [KletsoCommandOutcome.noContext]);
      client.ui.contextProvider = () => tester.element(find.byType(Scaffold));
      await tester.runAsync(
        () => client.send(const KletsoOutbound.text('open trail runner')),
      );
      await settle(tester, 60);
      expect(results.last.outcome, KletsoCommandOutcome.ran);
      expect(ran.single, {'sku': 'SKU-1001'});
      client.ui.actions.unregister('open_product');
      await tester.runAsync(
        () => client.send(const KletsoOutbound.text('open trail runner')),
      );
      await settle(tester, 60);
      expect(results.last.outcome, KletsoCommandOutcome.noHandler);
      await tester.runAsync(client.dispose);

      final locked = await connect(tester, allowCommands: false);
      final lockedResults = <KletsoCommandResult>[];
      locked.ui.commandResults.listen(lockedResults.add);
      locked.registerAction(
        'open_product',
        (args, ctx) async => fail('must not run'),
      );
      locked.ui.contextProvider = () => tester.element(find.byType(Scaffold));
      await tester.runAsync(
        () => locked.send(const KletsoOutbound.text('open trail runner')),
      );
      await settle(tester, 60);
      expect(lockedResults.single.outcome, KletsoCommandOutcome.disabled);
      await tester.runAsync(locked.dispose);
    },
  );
}
