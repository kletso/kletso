import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_voice/kletso_voice.dart';

Uint8List _pcm(int ms, {int amplitude = 8000}) {
  final samples = 24 * ms;
  final b = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    b.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  test('capture chunks pass through and drive the input level', () async {
    final capture = _FakeCapture();
    final io = KletsoDeviceAudioIo(capture: capture, sink: _FakeSink());
    expect(await io.requestPermission(), isTrue);
    final stream = await io.openCapture();
    final got = <Uint8List>[];
    final sub = stream.listen(got.add);
    capture.emit(_pcm(40));
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    expect(io.inputLevel.value, greaterThan(0.2));
    await io.closeCapture();
    expect(capture.started, isFalse);
    expect(io.inputLevel.value, 0);
    await sub.cancel();
    await io.dispose();
  });

  test('playback clock advances with the sink and levels follow chunks', () {
    fakeAsync((FakeAsync async) {
      final sink = _FakeSink();
      final io = KletsoDeviceAudioIo(
        capture: _FakeCapture(),
        sink: sink,
        levelInterval: const Duration(milliseconds: 10),
      );
      io.enqueue(_pcm(100));
      io.enqueue(_pcm(100, amplitude: 0));
      async.flushMicrotasks();
      expect(sink.opened, isTrue);
      expect(sink.fedBytes, 200 * 48);
      // the sink "plays" in real time: 10 ms per 10 ms poll
      sink.playRateMsPerPoll = 10;
      async.elapse(const Duration(milliseconds: 30));
      expect(io.playedMs, greaterThan(0));
      expect(io.outputLevel.value, greaterThan(0.2), reason: 'loud chunk');
      async.elapse(const Duration(milliseconds: 120));
      expect(io.playedMs, greaterThanOrEqualTo(100));
      expect(io.outputLevel.value, 0, reason: 'silent chunk');
      async.elapse(const Duration(milliseconds: 200));
      expect(io.playedMs, 200);
      unawaited(io.flush());
      async.flushMicrotasks();
      expect(io.playedMs, 0);
      expect(sink.stopped, 1);
      unawaited(io.dispose());
      async.flushMicrotasks();
    });
  });
}

final class _FakeCapture implements KletsoCapture {
  StreamController<Uint8List>? _c;
  bool started = false;
  void emit(Uint8List pcm) => _c?.add(pcm);
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Stream<Uint8List>> start(KletsoCaptureConfig config) async {
    started = true;
    _c = StreamController<Uint8List>();
    return _c!.stream;
  }

  @override
  Future<void> stop() async {
    started = false;
    await _c?.close();
    _c = null;
  }

  @override
  Future<void> dispose() => stop();
}

final class _FakeSink implements KletsoPcmSink {
  bool opened = false;
  int fedBytes = 0;
  int stopped = 0;
  int _playedMs = 0;
  int playRateMsPerPoll = 0;
  @override
  Future<void> open() async => opened = true;
  @override
  Future<void> feed(Uint8List pcm) async => fedBytes += pcm.length;
  @override
  Future<void> stop() async {
    stopped++;
    fedBytes = 0;
    _playedMs = 0;
  }

  @override
  Future<Duration> buffered() async {
    final totalMs = fedBytes ~/ 48;
    _playedMs = (_playedMs + playRateMsPerPoll).clamp(0, totalMs);
    return Duration(milliseconds: totalMs - _playedMs);
  }

  @override
  Future<void> dispose() async {}
}
