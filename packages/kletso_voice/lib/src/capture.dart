import 'dart:typed_data';

import 'capture_stub.dart'
    if (dart.library.js_interop) 'capture_web.dart'
    if (dart.library.io) 'capture_native.dart'
    as impl;

/// Microphone options. Everything is PCM16 mono; the rate is fixed by the
/// protocol.
final class KletsoCaptureConfig {
  /// Creates a config.
  const KletsoCaptureConfig({
    this.echoCancel = true,
    this.noiseSuppress = true,
    this.autoGain = true,
  });

  /// Sample rate of the frames (the protocol's 24 kHz).
  int get sampleRate => 24000;

  /// Let the platform cancel the speaker's echo (needed for barge-in).
  final bool echoCancel;

  /// Platform noise suppression.
  final bool noiseSuppress;

  /// Platform automatic gain control.
  final bool autoGain;
}

/// A microphone source producing PCM16 mono 24 kHz chunks.
abstract interface class KletsoCapture {
  /// The platform implementation for this build (native `record`
  /// implementations or Web Audio).
  factory KletsoCapture.platform() = impl.PlatformCapture;

  /// Asks for microphone permission; `true` when granted.
  Future<bool> requestPermission();

  /// Starts capturing. The stream ends after [stop].
  Future<Stream<Uint8List>> start(KletsoCaptureConfig config);

  /// Stops capturing.
  Future<void> stop();

  /// Releases platform resources.
  Future<void> dispose();
}
