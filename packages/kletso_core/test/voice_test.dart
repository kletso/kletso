import 'dart:async';
import 'dart:typed_data';

import 'package:kletso_core/fake.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

KletsoConfig get _config => KletsoConfig(
  publishableKey: 'kl_pub_test',
  agentId: KletsoFakeBackend.agentId,
  transport: KletsoTransportMode.webSocket,
);

Uint8List _pcm(int bytes, {int amplitude = 8000}) {
  final b = ByteData(bytes);
  for (var i = 0; i < bytes ~/ 2; i++) {
    b.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return b.buffer.asUint8List();
}

Future<void> _until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late KletsoFakeBackend backend;
  late KletsoClient client;

  setUp(() async {
    backend = KletsoFakeBackend();
    client = KletsoClient(_config, api: backend, transport: backend);
    await client.identifyAnonymous();
  });
  tearDown(() async {
    await client.dispose();
    backend.close();
  });

  test('bootstrap reports voice and avatar; voice is available on ws', () {
    final b = client.session.value!;
    expect(b.voice.enabled, isTrue);
    expect(b.voice.model, 'gpt-realtime-2.1');
    expect(b.voice.pushToTalk, isFalse);
    expect(b.avatar['style'], 'kletso');
    expect(client.voice.available, isFalse, reason: 'no audio IO installed');
    client.voice.setHostHandlesAudio(true);
    expect(client.voice.available, isTrue);
  });

  test(
    'a spoken turn: states, transcript, caption, audio out, interruption, stop',
    () async {
      final voice = client.voice..setHostHandlesAudio(true);
      final statuses = <KletsoVoiceStatus>[];
      voice.status.addListener(() => statuses.add(voice.status.value));
      final audio = <KletsoAudioFrame>[];
      final sub = voice.audioOut.listen(audio.add);
      await voice.start();
      expect(voice.status.value, KletsoVoiceStatus.listening);
      expect(voice.isActive, isTrue);
      // one second of microphone audio in 40 ms frames
      for (var i = 0; i < 26; i++) {
        voice.sendAudio(_pcm(1920));
      }
      await _until(() => backend.audioBytesReceived >= 26 * 1920);
      await _until(() => voice.caption.value.contains('catalogue'));
      expect(voice.userTranscript.value, 'Show me products under 2000');
      expect(statuses, contains(KletsoVoiceStatus.thinking));
      expect(statuses, contains(KletsoVoiceStatus.speaking));
      expect(audio, isNotEmpty);
      expect(audio.first.kind, KletsoAudioFrame.audioOut);
      expect(audio.first.duration.inMilliseconds, 40);
      expect(voice.outputLevel.value, greaterThan(0));
      // the transcript also lands in the chat as voice messages
      await _until(
        () => client.messages.value.any(
          (m) => m.role == KletsoRole.user && m.text.contains('under 2000'),
        ),
      );
      await _until(() => voice.status.value == KletsoVoiceStatus.listening);
      // typed text during voice is answered aloud too
      voice.sendText('show my cart');
      await _until(() => voice.caption.value.contains('cart'));
      await voice.stop();
      await _until(() => voice.status.value == KletsoVoiceStatus.idle);
      expect(voice.endReason, KletsoVoiceEndReason.user);
      expect(voice.isActive, isFalse);
      await sub.cancel();
    },
  );

  test('interrupting while the assistant speaks flushes playback', () async {
    final slow = KletsoFakeBackend(
      scenario: const KletsoFakeScenario(
        deltaDelay: Duration(milliseconds: 30),
      ),
    );
    final c = KletsoClient(_config, api: slow, transport: slow);
    await c.identifyAnonymous();
    final io = _RecordingIo();
    final voice = c.voice..setAudioIo(io);
    expect(voice.available, isTrue);
    await voice.start();
    expect(io.captureOpen, isTrue);
    io.emit(_pcm(1920 * 26));
    await _until(() => voice.status.value == KletsoVoiceStatus.speaking);
    await _until(() => io.enqueued > 0);
    io.emit(_pcm(1920));
    await _until(
      () =>
          c.events.isBroadcast &&
          voice.status.value == KletsoVoiceStatus.listening,
      timeout: const Duration(seconds: 8),
    );
    expect(io.flushes, greaterThanOrEqualTo(1));
    await voice.stop();
    expect(io.captureOpen, isFalse);
    await c.dispose();
    slow.close();
  });

  test('voice off in the scenario → start throws voice_unavailable', () async {
    final off = KletsoFakeBackend(
      scenario: const KletsoFakeScenario(voice: false),
    );
    final c = KletsoClient(_config, api: off, transport: off);
    await c.identifyAnonymous();
    expect(c.session.value!.voice.enabled, isFalse);
    c.voice.setHostHandlesAudio(true);
    expect(c.voice.available, isFalse);
    await expectLater(
      c.voice.start(),
      throwsA(
        isA<KletsoServerException>().having(
          (e) => e.code,
          'code',
          'voice_unavailable',
        ),
      ),
    );
    expect(c.voice.status.value, KletsoVoiceStatus.idle);
    await c.dispose();
    off.close();
  });
}

/// Minimal audio IO that records what the controller does with it.
final class _RecordingIo implements KletsoAudioIo {
  StreamController<Uint8List>? _capture;
  bool captureOpen = false;
  int enqueued = 0;
  int flushes = 0;
  @override
  final KletsoValueNotifier<double> outputLevel = KletsoValueNotifier<double>(
    0,
  );
  @override
  final KletsoValueNotifier<double> inputLevel = KletsoValueNotifier<double>(0);

  void emit(Uint8List pcm) => _capture?.add(pcm);

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Stream<Uint8List>> openCapture() async {
    captureOpen = true;
    _capture = StreamController<Uint8List>();
    return _capture!.stream;
  }

  @override
  Future<void> closeCapture() async {
    captureOpen = false;
    await _capture?.close();
    _capture = null;
  }

  @override
  void enqueue(Uint8List pcm) {
    enqueued += pcm.length;
    outputLevel.value = 0.5;
  }

  @override
  Future<void> flush() async {
    flushes++;
    outputLevel.value = 0;
  }

  @override
  int get playedMs => enqueued ~/ 48;
  @override
  Future<void> dispose() async {}
}
