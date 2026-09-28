import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

/// The fake backend uses real async; widget tests run in fake time, so the
/// setup (and any client call awaited directly) goes through `runAsync`.
Future<KletsoClient> liveClient(
  WidgetTester tester, {
  KletsoFakeScenario scenario = const KletsoFakeScenario(),
}) async {
  late KletsoClient client;
  await tester.runAsync(() async {
    client = await _connect(scenario);
  });
  return client;
}

Future<KletsoClient> _connect(KletsoFakeScenario scenario) async {
  final backend = KletsoFakeBackend(scenario: scenario);
  final client = KletsoClient(
    KletsoConfig(
      publishableKey: 'kl_pub_test',
      agentId: KletsoFakeBackend.agentId,
      logLevel: KletsoLogLevel.none,
    ),
    api: backend,
    transport: backend,
  );
  await client.identifyAnonymous();
  return client;
}

/// Lets the fake backend's real-time futures run, then pumps frames.
Future<void> settle(WidgetTester tester, [int frames = 30]) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'KletsoChat shows the greeting, sends text and renders the reply with its surface',
    (tester) async {
      tallViewport(tester);
      final client = await liveClient(tester);
      await tester.pumpWidget(
        harness(SizedBox(height: 1800, child: KletsoChat(client: client))),
      );
      await settle(tester);
      expect(find.text('Acme Assistant'), findsOneWidget);
      expect(find.textContaining("Hi! I'm Acme's assistant"), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'I need a flight to Osaka',
      );
      await tester.pump(); // composer enables Send once it sees text
      await tester.tap(find.bySemanticsLabel('Send'));
      await settle(tester);
      expect(
        find.widgetWithText(KletsoUserBubble, 'I need a flight to Osaka'),
        findsOneWidget,
      );
      expect(find.textContaining('best option for tomorrow'), findsOneWidget);
      expect(
        find.text('Tokyo → Osaka'),
        findsOneWidget,
        reason: 'flight card rendered under the reply',
      );
      expect(find.byType(KletsoToolCallChip), findsOneWidget);
      expect(find.text('search flights'), findsOneWidget);

      // tapping an agent action on the surface posts a new user turn and gets a reply
      await tester.tap(find.widgetWithText(KletsoButton, 'Select flight'));
      await settle(tester);
      expect(find.text('Select ANA NH873'), findsOneWidget);
      expect(find.textContaining('Great choice'), findsOneWidget);
      expect(
        find.widgetWithText(KletsoButton, 'Show me sales'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  testWidgets('connection banner and composer follow the connection state', (
    tester,
  ) async {
    tallViewport(tester);
    final client = await liveClient(tester);
    await tester.pumpWidget(
      harness(SizedBox(height: 700, child: KletsoChat(client: client))),
    );
    await settle(tester);
    expect(find.byType(KletsoConnectionBanner), findsOneWidget);
    expect(find.text('Reconnecting…'), findsNothing);
    await tester.runAsync(client.pause);
    await settle(tester);
    expect(find.text('Offline'), findsWidgets);
    await tester.runAsync(client.resume);
    await settle(tester);
    expect(find.text('Online'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets('conversation list opens, creates and switches', (tester) async {
    tallViewport(tester);
    final client = await liveClient(tester);
    await tester.pumpWidget(
      harness(SizedBox(height: 900, child: KletsoChat(client: client))),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('New conversation'));
    await settle(tester);
    expect(client.conversations.value, hasLength(2));
    await tester.tap(find.byTooltip('Conversations'));
    await settle(tester);
    expect(find.byType(KletsoConversationList), findsOneWidget);
    expect(find.text('New conversation'), findsOneWidget);
    await tester.tap(find.byType(ListTile).last);
    await settle(tester);
    expect(find.byType(KletsoConversationList), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets('KletsoLauncher opens the sheet and marks unread when closed', (
    tester,
  ) async {
    tallViewport(tester);
    final client = await liveClient(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: KletsoTheme.light(
          useHostFont: true,
        ).materialTheme(ThemeData.light()),
        home: Scaffold(
          body: const SizedBox.expand(),
          floatingActionButton: KletsoLauncher(client: client),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byType(KletsoLauncher));
    await settle(tester);
    expect(find.byType(KletsoChat), findsOneWidget);
    expect(client.ui.isOpen, isTrue);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.byType(KletsoChat), findsNothing);
    expect(client.ui.isOpen, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });

  testWidgets('bubbles render streaming, failed and surface-only messages', (
    tester,
  ) async {
    final streaming = KletsoMessage(
      id: 'm1',
      role: KletsoRole.assistant,
      createdAt: DateTime.utc(2026),
      status: KletsoMessageStatus.streaming,
    );
    final failed = KletsoMessage(
      id: 'm2',
      role: KletsoRole.user,
      createdAt: DateTime.utc(2026),
      text: 'hi',
      status: KletsoMessageStatus.failed,
    );
    final surfaceOnly = KletsoMessage(
      id: 'm3',
      role: KletsoRole.assistant,
      createdAt: DateTime.utc(2026),
      surfaces: [fixture('ui/valid/quick_replies.json')],
      toolCalls: const [
        KletsoToolCall(
          id: 'c',
          name: 'search_hotels',
          status: KletsoToolCallStatus.failed,
          error: 'boom',
        ),
      ],
    );
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            KletsoBotBubble(
              message: streaming,
              markdownRenderer: const KletsoPlainMarkdownRenderer(),
            ),
            KletsoUserBubble(message: failed),
            KletsoBotBubble(
              message: surfaceOnly,
              markdownRenderer: const KletsoPlainMarkdownRenderer(),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(KletsoTypingDots), findsOneWidget);
    expect(find.text('Not delivered'), findsOneWidget);
    expect(find.text('search hotels failed'), findsOneWidget);
    expect(find.widgetWithText(KletsoButton, 'Track my order'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
