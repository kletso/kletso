import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

/// Goldens are generated on macOS only (`flutter test --update-goldens`);
/// CI compares on the same OS. The bundled Plus Jakarta Sans is loaded so
/// text renders as in the app.
void main() {
  setUpAll(() async {
    final loader = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
    await loader.load();
  });

  Widget frame(Widget child, {double width = 400, bool dark = false}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme:
            (dark
                    ? KletsoTheme.dark(useHostFont: true)
                    : KletsoTheme.light(useHostFont: true))
                .materialTheme(dark ? ThemeData.dark() : ThemeData.light()),
        home: Scaffold(
          backgroundColor: dark ? KletsoTokens.deepNavy : KletsoTokens.cream,
          body: Center(
            child: SizedBox(
              width: width,
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        ),
      );

  Future<void> golden(
    WidgetTester tester,
    Widget child,
    String name, {
    double width = 400,
    double height = 600,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width + 24, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(child, width: width, dark: dark));
    await tester.pump();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('bubbles', (tester) async {
    final user = KletsoMessage(
      id: 'u',
      role: KletsoRole.user,
      createdAt: DateTime.utc(2026),
      text: 'I need a flight from Tokyo to Osaka tomorrow morning',
    );
    final bot = KletsoMessage(
      id: 'b',
      role: KletsoRole.assistant,
      createdAt: DateTime.utc(2026),
      text:
          'Here is the **best option** for tomorrow morning. Prices include taxes; see the [fare rules](https://acme.com/fares).',
      toolCalls: const [
        KletsoToolCall(
          id: 'c',
          name: 'search_flights',
          status: KletsoToolCallStatus.completed,
          durationMs: 820,
        ),
      ],
    );
    await golden(
      tester,
      Column(
        children: [
          KletsoUserBubble(message: user),
          const SizedBox(height: 12),
          KletsoBotBubble(
            message: bot,
            markdownRenderer: const KletsoPlainMarkdownRenderer(),
          ),
        ],
      ),
      'bubbles',
      height: 320,
    );
  });

  testWidgets('flight card', (tester) async {
    await golden(
      tester,
      KletsoSurfaceView(surface: fixture('ui/valid/flight_card.json')),
      'flight_card',
      height: 620,
    );
  });

  testWidgets('hotel card', (tester) async {
    await golden(
      tester,
      KletsoSurfaceView(surface: fixture('ui/valid/hotel_card.json')),
      'hotel_card',
      height: 560,
    );
  });

  testWidgets('product cards with a host component', (tester) async {
    final registry = KletsoComponentRegistry()
      ..register(
        'acme.productCard',
        (ctx, node) => Container(
          decoration: BoxDecoration(
            color: ctx.theme.surface,
            borderRadius: ctx.theme.borderRadiusLg,
            border: Border.all(color: ctx.theme.line),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: ctx.theme.successSoft,
                  borderRadius: ctx.theme.borderRadiusMd,
                ),
              ),
              const SizedBox(height: 8),
              Text(node.string('name'), style: ctx.theme.subtitle),
              Text(
                '₹${node.number('price')}',
                style: ctx.theme.body.copyWith(
                  color: ctx.theme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              KletsoButton(
                label: node.boolean('inStock') ? 'Add to cart' : 'Notify me',
                variant: 'secondary',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
    await golden(
      tester,
      KletsoSurfaceView(
        surface: fixture('ui/valid/product_cards.json'),
        registry: registry,
      ),
      'product_cards',
      height: 420,
    );
  });

  testWidgets('chart and confirm', (tester) async {
    await golden(
      tester,
      Column(
        children: [
          KletsoSurfaceView(surface: fixture('ui/valid/chart.json')),
          const SizedBox(height: 12),
          KletsoSurfaceView(surface: fixture('ui/valid/confirm.json')),
        ],
      ),
      'chart_confirm',
      height: 860,
    );
  });

  testWidgets('media hub and trip plan', (tester) async {
    await golden(
      tester,
      KletsoSurfaceView(surface: fixture('ui/valid/media_hub.json')),
      'media_hub',
      height: 1400,
    );
    await golden(
      tester,
      KletsoSurfaceView(surface: fixture('ui/valid/trip_plan.json')),
      'trip_plan',
      height: 1000,
    );
  });

  testWidgets('dark theme: bubbles and flight card', (tester) async {
    final user = KletsoMessage(
      id: 'u',
      role: KletsoRole.user,
      createdAt: DateTime.utc(2026),
      text: 'Any flights to Osaka tomorrow?',
    );
    final bot = KletsoMessage(
      id: 'b',
      role: KletsoRole.assistant,
      createdAt: DateTime.utc(2026),
      text: 'Here is the **best option**.',
      toolCalls: const [
        KletsoToolCall(
          id: 'c',
          name: 'search_flights',
          status: KletsoToolCallStatus.completed,
        ),
      ],
    );
    await golden(
      tester,
      Column(
        children: [
          KletsoUserBubble(message: user),
          const SizedBox(height: 12),
          KletsoBotBubble(
            message: bot,
            markdownRenderer: const KletsoPlainMarkdownRenderer(),
          ),
          const SizedBox(height: 12),
          KletsoSurfaceView(surface: fixture('ui/valid/flight_card.json')),
        ],
      ),
      'dark_bubbles_flight',
      height: 820,
      dark: true,
    );
  });
}
