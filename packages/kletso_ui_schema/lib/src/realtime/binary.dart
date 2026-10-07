import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A binary WebSocket frame of `kletso.realtime/v1`: one byte of kind
/// followed by PCM16 little-endian mono audio at 24 kHz.
///
/// Binary frames carry voice audio only; they are never logged, never
/// replayed and never acknowledged. Everything else stays JSON.
@immutable
final class KletsoAudioFrame {
  /// Creates a frame.
  const KletsoAudioFrame({required this.kind, required this.pcm});

  /// Audio from the microphone, client to server.
  static const int audioIn = 0x01;

  /// Audio from the model, server to client.
  static const int audioOut = 0x02;

  /// Sample rate of every audio frame.
  static const int sampleRate = 24000;

  /// Bytes per second of audio (16-bit mono).
  static const int bytesPerSecond = sampleRate * 2;

  /// Largest frame either side accepts (1 byte of kind + PCM).
  static const int maxBytes = 16 * 1024;

  /// [audioIn] or [audioOut].
  final int kind;

  /// PCM16LE mono samples; even length.
  final Uint8List pcm;

  /// Duration of the audio in this frame.
  Duration get duration =>
      Duration(microseconds: pcm.lengthInBytes * 1000000 ~/ bytesPerSecond);

  /// Parses a wire frame; returns `null` when it is not a valid audio frame
  /// (unknown kind, odd PCM length, too large), so callers can drop it.
  static KletsoAudioFrame? decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    final kind = bytes[0];
    if (kind != audioIn && kind != audioOut) return null;
    final body = bytes.length - 1;
    if (body.isOdd) return null;
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return KletsoAudioFrame(kind: kind, pcm: Uint8List.sublistView(data, 1));
  }

  /// Wire form.
  Uint8List encode() {
    final out = Uint8List(pcm.lengthInBytes + 1);
    out[0] = kind;
    out.setRange(1, out.length, pcm);
    return out;
  }

  /// Root-mean-square level of the samples, 0..1, for meters and lip-sync.
  double get rms {
    final samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return 0;
    final view = ByteData.sublistView(pcm);
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final s = view.getInt16(i * 2, Endian.little) / 32768.0;
      sum += s * s;
    }
    var r = 0.0;
    final mean = sum / samples;
    // Newton iterations avoid importing dart:math for one sqrt.
    if (mean > 0) {
      r = mean;
      for (var i = 0; i < 20; i++) {
        r = 0.5 * (r + mean / r);
      }
    }
    return r > 1 ? 1 : r;
  }
}
