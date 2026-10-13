// The launcher and the chat bind the app lifecycle themselves: background →
// socket closed cleanly, foreground → reconnected. Hosts no longer have to
// call bindAppLifecycle (SeeCircles 2026-10-09: idle sockets aborted by Android
// surfaced as close code 1002).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

Future<KletsoClient> _connect() async {
  final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
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

/// Dispatches lifecycle states inside `runAsync` so the SDK's reconnect
/// timers run in real time, then lets them settle.
Future<void> _lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  await tester.runAsync(() async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await _frames(tester);
}

/// Pumps enough frames for the chat's animations to finish (test clock).
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  for (final (name, build) in <(String, Widget Function(KletsoClient))>[
    ('KletsoLauncher', (c) => KletsoLauncher(client: c)),
    ('KletsoChat', (c) => KletsoChat(client: c)),
  ]) {
    testWidgets('$name pauses the socket in the background and resumes', (
      tester,
    ) async {
      final client = await tester.runAsync(_connect);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: build(client!))),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await _frames(tester);
      expect(client.connection.value, KletsoConnectionState.open);

      // Real transitions, as the engine emits them (the listener asserts).
      await _lifecycle(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(client.connection.value, KletsoConnectionState.closed);

      await _lifecycle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(client.connection.value, KletsoConnectionState.open);

      await _frames(tester);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
      await tester.runAsync(client.dispose);
    });
  }
}
