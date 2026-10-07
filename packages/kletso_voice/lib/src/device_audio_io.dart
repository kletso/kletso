import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:kletso_core/kletso_core.dart';

import 'capture.dart';

/// Where assistant PCM goes. The default wraps `audio_stream_player`; tests
/// inject a fake.
abstract interface class KletsoPcmSink {
  /// Prepares the device output.
  Future<void> open();

  /// Appends PCM16 mono 24 kHz bytes.
  Future<void> feed(Uint8List pcm);

  /// Drops buffered audio and stops.
  Future<void> stop();

  /// Audio fed but not yet played.
  Future<Duration> buffered();

  /// Releases the output.
  Future<void> dispose();
}

final class _PlayerSink implements KletsoPcmSink {
  AudioStreamPlayer? _player;

  @override
  Future<void> open() async {
    _player ??= await AudioStreamPlayer.create(
      sampleRate: KletsoAudioFrame.sampleRate,
    );
    await _player!.play();
  }

  @override
  Future<void> feed(Uint8List pcm) async {
    final p = _player;
    if (p == null) return;
    await p.feed(pcm);
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<Duration> buffered() async =>
      _player?.bufferedDuration() ?? Duration.zero;

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}

/// [KletsoAudioIo] for real devices: platform microphone in, streaming PCM
/// player out, with input/output levels and a playback clock for
/// `voice.played` reports.
final class KletsoDeviceAudioIo implements KletsoAudioIo {
  /// Creates the device audio. [capture] and [sink] default to the platform
  /// microphone and `audio_stream_player`.
  KletsoDeviceAudioIo({
    KletsoCapture? capture,
    KletsoPcmSink? sink,
    this.captureConfig = const KletsoCaptureConfig(),
    this.levelInterval = const Duration(milliseconds: 50),
  }) : _capture = capture ?? KletsoCapture.platform(),
       _sink = sink ?? _PlayerSink();

  /// Microphone options.
  final KletsoCaptureConfig captureConfig;

  /// How often the playback clock and output level are refreshed.
  final Duration levelInterval;

  final KletsoCapture _capture;
  final KletsoPcmSink _sink;
  final KletsoValueNotifier<double> _outputLevel = KletsoValueNotifier<double>(
    0,
  );
  final KletsoValueNotifier<double> _inputLevel = KletsoValueNotifier<double>(
    0,
  );
  final Queue<_Chunk> _queued = Queue<_Chunk>();
  StreamController<Uint8List>? _captureOut;
  StreamSubscription<Uint8List>? _captureSub;
  Timer? _clock;
  bool _sinkOpen = false;
  int _fedMs = 0;
  int _playedMs = 0;
  bool _disposed = false;

  @override
  KletsoValueListenable<double> get outputLevel => _outputLevel;

  @override
  KletsoValueListenable<double> get inputLevel => _inputLevel;

  @override
  int get playedMs => _playedMs;

  @override
  Future<bool> requestPermission() => _capture.requestPermission();

  @override
  Future<Stream<Uint8List>> openCapture() async {
    await closeCapture();
    final raw = await _capture.start(captureConfig);
    final out = _captureOut = StreamController<Uint8List>();
    _captureSub = raw.listen(
      (chunk) {
        if (out.isClosed) return;
        _inputLevel.value = KletsoAudioFrame(
          kind: KletsoAudioFrame.audioIn,
          pcm: chunk,
        ).rms;
        out.add(chunk);
      },
      onDone: () {
        if (!out.isClosed) unawaited(out.close());
      },
    );
    return out.stream;
  }

  @override
  Future<void> closeCapture() async {
    await _captureSub?.cancel();
    _captureSub = null;
    await _capture.stop();
    final out = _captureOut;
    _captureOut = null;
    if (out != null && !out.isClosed) await out.close();
    _inputLevel.value = 0;
  }

  @override
  void enqueue(Uint8List pcm) {
    if (_disposed || pcm.isEmpty) return;
    final frame = KletsoAudioFrame(kind: KletsoAudioFrame.audioOut, pcm: pcm);
    final ms = frame.duration.inMilliseconds;
    _queued.add(_Chunk(startMs: _fedMs, endMs: _fedMs + ms, level: frame.rms));
    _fedMs += ms;
    unawaited(_feed(pcm));
    _clock ??= Timer.periodic(levelInterval, (_) => unawaited(_tick()));
  }

  Future<void> _feed(Uint8List pcm) async {
    try {
      if (!_sinkOpen) {
        _sinkOpen = true;
        await _sink.open();
      }
      await _sink.feed(pcm);
    } on Object {
      // Device output failed; levels keep working, audio is silent.
    }
  }

  /// Advances the playback clock from what the sink still holds and sets the
  /// level of the chunk under the playhead.
  Future<void> _tick() async {
    if (_disposed) return;
    Duration buffered;
    try {
      buffered = await _sink.buffered();
    } on Object {
      buffered = Duration.zero;
    }
    _playedMs = max(_playedMs, _fedMs - buffered.inMilliseconds);
    while (_queued.isNotEmpty && _queued.first.endMs <= _playedMs) {
      _queued.removeFirst();
    }
    if (_queued.isEmpty) {
      _outputLevel.value = 0;
      if (_playedMs >= _fedMs) {
        _clock?.cancel();
        _clock = null;
      }
      return;
    }
    final current = _queued.first;
    _outputLevel.value = current.startMs <= _playedMs ? current.level : 0;
  }

  @override
  Future<void> flush() async {
    _queued.clear();
    _fedMs = 0;
    _playedMs = 0;
    _outputLevel.value = 0;
    _clock?.cancel();
    _clock = null;
    if (_sinkOpen) {
      try {
        await _sink.stop();
      } on Object {
        // Nothing to drop.
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await closeCapture();
    await flush();
    await _capture.dispose();
    await _sink.dispose();
    _outputLevel.dispose();
    _inputLevel.dispose();
  }
}

final class _Chunk {
  const _Chunk({
    required this.startMs,
    required this.endMs,
    required this.level,
  });
  final int startMs;
  final int endMs;
  final double level;
}
