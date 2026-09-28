// End-to-end flow against the fake backend. On the web the
// `integration_test` runner needs a WebDriver:
//   chromedriver --port=4444 &
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/chat_flow_test.dart -d web-server \
//     --browser-name=chrome --headless   (see scripts/web-e2e.sh)
// On Android: `flutter test integration_test -d <device>`.
import 'package:acme_shop/main.dart' as app;
import 'package:acme_shop/src/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

/// Browser console output does not reach `flutter drive`; collect it here.
final List<String> _log = <String>[];
void _note(String s) => _log.add(s);

/// Pumps real frames until [finder] matches (the fake backend answers on
/// real timers, which `pumpAndSettle` does not wait for).
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  final texts = find
      .descendant(of: find.byType(KletsoChat), matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '<rich>')
      .toList();
  final pill = find.byType(KletsoNewMessagesPill).evaluate().isNotEmpty;
  final msgs = Kletso.instance.messages.value
      .map(
        (m) =>
            '${m.role.wire}:${m.text.split('\n').first}'
            '${m.surfaces.isEmpty ? '' : '[surface]'}',
      )
      .toList();
  final scrollables = find
      .descendant(
        of: find.byType(KletsoChat),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .map((s) => s.position.hasPixels ? s.position.pixels : -1)
      .toList();
  fail(
    'Timed out waiting for $finder. pill=$pill scroll=$scrollables '
    'messages=$msgs chat texts: $texts\nlog: $_log',
  );
}

Future<void> _waitUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}

Future<void> _say(WidgetTester tester, String text) async {
  final field = find.descendant(
    of: find.byType(KletsoComposer),
    matching: find.byType(TextField),
  );
  final before = Kletso.instance.messages.value.length;
  // On the web the browser owns the text input once the field has been
  // focused for real, so `enterText` stops reaching it; drive the
  // controller like a keyboard would.
  tester.widget<TextField>(field).controller!.text = text;
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.bySemanticsLabel('Send').last);
  await tester.pump(const Duration(milliseconds: 300));
  _note(
    '[e2e] "$text" → messages $before → '
    '${Kletso.instance.messages.value.length}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user → server → surface → local action → host navigation', (
    tester,
  ) async {
    // LIVE_API=http://host:port switches the example to a real Kletso runtime.
    const live = String.fromEnvironment('LIVE_API');
    const liveKey = String.fromEnvironment('LIVE_KEY');
    if (live.isNotEmpty) {
      AppSettings.instance.liveApi = true;
      AppSettings.instance.apiBase = live;
      if (liveKey.isNotEmpty) {
        AppSettings.instance.publishableKey = liveKey;
      }
    }
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Acme Shop'), findsWidgets);

    // 1. open the chat from the launcher (host → SDK)
    await tester.tap(find.byType(KletsoLauncher));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(KletsoChat), findsOneWidget);
    expect(find.textContaining("I'm Acme's assistant"), findsOneWidget);

    // 2. user text → fake server → ui.render with bound data
    await _say(tester, 'I need a flight to Osaka');
    await _waitFor(tester, find.text('Select flight'));
    expect(find.text('HND'), findsOneWidget, reason: 'bound flight surface');

    // 3. agent action from a surface → server reply
    await tester.tap(find.text('Select flight'));
    await _waitFor(tester, find.textContaining('Great choice'));

    // 4. host-registered component rendered from a surface
    await _say(tester, 'show me products');
    // the shop grid behind the sheet shows the same name: scope to the chat
    final inChat = find.descendant(
      of: find.byType(KletsoChat),
      matching: find.text('Trail Runner 2'),
    );
    await _waitFor(tester, inChat);
    expect(inChat, findsOneWidget);

    // 5. local action → host handler navigates and closes the chat
    await tester.tap(inChat);
    await _waitFor(tester, find.textContaining('Opened from the chat'));
    await _waitUntilGone(tester, find.byType(KletsoChat)); // sheet animates out
  });

  testWidgets('silent app event → server rule → banner → tap opens the chat', (
    tester,
  ) async {
    const live = String.fromEnvironment('LIVE_API');
    const liveKey = String.fromEnvironment('LIVE_KEY');
    if (live.isNotEmpty) {
      AppSettings.instance.liveApi = true;
      AppSettings.instance.apiBase = live;
      if (liveKey.isNotEmpty) {
        AppSettings.instance.publishableKey = liveKey;
      }
    }
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // the app fires a silent event (geofence); nothing is typed or shown
    // in the chat by the app itself
    Kletso.instance.track('geofence_entered', <String, Object?>{
      'store': 'Shibuya',
    });
    await _waitFor(tester, find.byType(KletsoNotificationBanner));
    expect(find.text('You are near Acme Shibuya'), findsOneWidget);
    expect(find.byType(KletsoChat), findsNothing);

    await tester.tap(find.text('You are near Acme Shibuya'));
    await _waitFor(tester, find.byType(KletsoChat));
    await _waitFor(tester, find.textContaining('SHIBUYA10'));
    await _waitUntilGone(tester, find.byType(KletsoNotificationBanner));

    // push handoff while "backgrounded": toast, deduped on a second delivery
    final backend = AppSettings.instance.backend;
    if (backend == null) {
      return; // live runtime: push comes from the server side
    }
    final user = Kletso.instance.session.value!.endUser.id;
    final payload = backend.sendPush(
      user,
      const KletsoAppNotification(
        notificationId: 'ntf_e2e_push',
        title: 'Flash sale',
        channel: KletsoNotificationChannel.toast,
      ),
    );
    expect(Kletso.instance.handlePushPayload(payload), isTrue);
    expect(Kletso.instance.handlePushPayload(payload), isFalse);
    await _waitFor(tester, find.byType(KletsoNotificationToast));
    expect(find.textContaining('Flash sale'), findsOneWidget);
  });
}
