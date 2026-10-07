import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'capture.dart';

/// Microphone through Web Audio: `getUserMedia` with echo cancellation and a
/// 24 kHz `AudioContext`, PCM16 chunks of ~85 ms. Pure `package:web`, so
/// `flutter build web --wasm` works.
final class PlatformCapture implements KletsoCapture {
  /// Creates a capture.
  PlatformCapture();

  web.MediaStream? _stream;
  web.AudioContext? _context;
  web.ScriptProcessorNode? _processor;
  web.MediaStreamAudioSourceNode? _source;
  StreamController<Uint8List>? _out;

  @override
  Future<bool> requestPermission() async {
    try {
      final stream = await _getUserMedia(const KletsoCaptureConfig());
      for (final t in stream.getTracks().toDart) {
        t.stop();
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<web.MediaStream> _getUserMedia(KletsoCaptureConfig config) => web
      .window
      .navigator
      .mediaDevices
      .getUserMedia(
        web.MediaStreamConstraints(
          audio: web.MediaTrackConstraints(
            echoCancellation: config.echoCancel.toJS,
            noiseSuppression: config.noiseSuppress.toJS,
            autoGainControl: config.autoGain.toJS,
            channelCount: 1.toJS,
            sampleRate: config.sampleRate.toJS,
          ),
        ),
      )
      .toDart;

  @override
  Future<Stream<Uint8List>> start(KletsoCaptureConfig config) async {
    await stop();
    final stream = _stream = await _getUserMedia(config);
    web.AudioContext context;
    try {
      context = web.AudioContext(
        web.AudioContextOptions(sampleRate: config.sampleRate),
      );
    } on Object {
      // Some browsers refuse a custom rate; resample below.
      context = web.AudioContext();
    }
    _context = context;
    if (context.state == 'suspended') await context.resume().toDart;
    final out = _out = StreamController<Uint8List>();
    final source = _source = context.createMediaStreamSource(stream);
    final processor = _processor = context.createScriptProcessor(4096, 1, 1);
    final ratio = context.sampleRate / config.sampleRate;
    processor.onaudioprocess = ((web.AudioProcessingEvent e) {
      if (out.isClosed) return;
      final input = e.inputBuffer.getChannelData(0).toDart;
      out.add(_toPcm16(input, ratio));
    }).toJS;
    source.connect(processor);
    // A ScriptProcessorNode only runs while connected to the destination;
    // its output is silence (we never copy input to output).
    processor.connect(context.destination);
    return out.stream;
  }

  static Uint8List _toPcm16(Float32List input, double ratio) {
    final n = ratio == 1 ? input.length : (input.length / ratio).floor();
    final bytes = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      final v = ratio == 1 ? input[i] : input[(i * ratio).floor()];
      final s = (v.clamp(-1.0, 1.0) * 32767).round();
      bytes.setInt16(i * 2, s, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  @override
  Future<void> stop() async {
    final out = _out;
    _out = null;
    _processor?.disconnect();
    _source?.disconnect();
    _processor = null;
    _source = null;
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final t in stream.getTracks().toDart) {
        t.stop();
      }
    }
    final context = _context;
    _context = null;
    if (context != null) {
      try {
        await context.close().toDart;
      } on Object {
        // Already closed.
      }
    }
    await out?.close();
  }

  @override
  Future<void> dispose() => stop();
}
