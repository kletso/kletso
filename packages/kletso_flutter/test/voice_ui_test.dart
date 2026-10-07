import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

Uint8List _pcm(int bytes) {
  final b = ByteData(bytes);
  for (var i = 0; i < bytes ~/ 2; i++) {
    b.setInt16(i * 2, i.isEven ? 6000 : -6000, Endian.little);
  }
  return b.buffer.asUint8List();
}

Future<KletsoClient> _connect(KletsoFakeBackend backend) async {
  final client = KletsoClient(
    KletsoConfig(
      publishableKey: 'kl_pub_test',
      agentId: KletsoFakeBackend.agentId,
      transport: KletsoTransportMode.webSocket,
    ),
    api: backend,
    transport: backend,
  );
  await client.identifyAnonymous();
  return client;
}

/// The fake backend runs on real timers, so client setup (and any client
/// call awaited directly) goes through `runAsync`, like `chat_test.dart`.
Future<KletsoClient> _client(
  WidgetTester tester,
  KletsoFakeBackend backend,
) async {
  late KletsoClient client;
  await tester.runAsync(() async {
    client = await _connect(backend);
  });
  return client;
}

/// Fake timers (pumps) and the backend's real-zone async both need to run,
/// in turns, before the UI settles.
Future<void> _settle(WidgetTester tester, [int rounds = 3]) async {
  for (var r = 0; r < rounds; r++) {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: KletsoTheme.light(useHostFont: true).materialTheme(ThemeData.light()),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('no audio IO → no microphone in the composer', (tester) async {
    final backend = KletsoFakeBackend();
    final client = await _client(tester, backend);
    await tester.pumpWidget(_app(KletsoChat(client: client)));
    await _settle(tester);
    expect(find.byType(KletsoVoiceButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
    backend.close();
  });

  testWidgets(
    'mic opens the voice sheet, the fake answers aloud, End closes it',
    (tester) async {
      final backend = KletsoFakeBackend();
      final client = await _client(tester, backend);
      final io = _FakeIo();
      client.voice.setAudioIo(io);
      await tester.pumpWidget(_app(KletsoChat(client: client)));
      await _settle(tester);
      expect(find.byType(KletsoVoiceButton), findsOneWidget);
      await tester.tap(find.byType(KletsoVoiceButton));
      await _settle(tester);
      expect(find.byType(KletsoVoiceSheet), findsOneWidget);
      expect(find.text('Listening…'), findsOneWidget);
      expect(io.captureOpen, isTrue);
      // the user talks for about a second
      await tester.runAsync(() async {
        for (var i = 0; i < 26; i++) {
          io.emit(_pcm(1920));
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _settle(tester);
      expect(find.text('Show me products under 2000'), findsWidgets);
      expect(find.textContaining('catalogue'), findsWidgets);
      expect(io.enqueued, greaterThan(0));
      expect(
        client.messages.value.any((m) => m.text.contains('under 2000')),
        isTrue,
      );
      // avatar bound to the chat reacted
      final avatar = tester.widget<KletsoAvatar>(
        find.descendant(
          of: find.byType(KletsoVoiceSheet),
          matching: find.byType(KletsoAvatar),
        ),
      );
      expect(avatar.size, 160);
      await tester.tap(find.byIcon(Icons.call_end));
      await _settle(tester);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(KletsoVoiceSheet), findsNothing);
      expect(client.voice.status.value, KletsoVoiceStatus.idle);
      expect(io.captureOpen, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
      backend.close();
    },
  );

  testWidgets('voice off on the agent → sheet explains and stays closed', (
    tester,
  ) async {
    final backend = KletsoFakeBackend(
      scenario: const KletsoFakeScenario(voice: false),
    );
    final client = await _client(tester, backend);
    client.voice.setAudioIo(_FakeIo());
    await tester.pumpWidget(_app(KletsoChat(client: client)));
    await _settle(tester);
    expect(find.byType(KletsoVoiceButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
    backend.close();
  });

  test('KletsoClientAvatar follows voice state and mood events', () async {
    final backend = KletsoFakeBackend();
    final client = await _connect(backend);
    client.voice.setHostHandlesAudio(true);
    final avatar = KletsoClientAvatar(client);
    final seen = <KletsoAvatarMood>[];
    avatar.controller.addListener(() => seen.add(avatar.controller.mood));
    expect(avatar.style, KletsoAvatarStyle.kletso);
    expect(avatar.controller.mood, KletsoAvatarMood.neutral);
    await client.voice.start();
    expect(avatar.controller.mood, KletsoAvatarMood.listening);
    for (var i = 0; i < 26; i++) {
      client.voice.sendAudio(_pcm(1920));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, contains(KletsoAvatarMood.thinking));
    expect(seen, contains(KletsoAvatarMood.speaking));
    await client.voice.stop();
    await Future<void>.delayed(Duration.zero);
    expect(avatar.controller.mood, KletsoAvatarMood.neutral);
    avatar.dispose();
    await client.dispose();
    backend.close();
  });
}

final class _FakeIo implements KletsoAudioIo {
  StreamController<Uint8List>? _c;
  bool captureOpen = false;
  int enqueued = 0;
  @override
  final KletsoValueNotifier<double> outputLevel = KletsoValueNotifier<double>(
    0,
  );
  @override
  final KletsoValueNotifier<double> inputLevel = KletsoValueNotifier<double>(0);
  void emit(Uint8List pcm) => _c?.add(pcm);
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Stream<Uint8List>> openCapture() async {
    captureOpen = true;
    _c = StreamController<Uint8List>();
    return _c!.stream;
  }

  @override
  Future<void> closeCapture() async {
    captureOpen = false;
    await _c?.close();
    _c = null;
  }

  @override
  void enqueue(Uint8List pcm) {
    enqueued += pcm.length;
    outputLevel.value = 0.6;
  }

  @override
  Future<void> flush() async => outputLevel.value = 0;
  @override
  int get playedMs => enqueued ~/ 48;
  @override
  Future<void> dispose() async {}
}
