import 'dart:typed_data';

import '../value_listenable.dart';

/// Microphone capture and speaker playback for voice sessions, implemented
/// outside this package (`package:kletso_voice` on Flutter, or the host's
/// own audio stack; D82). All audio is PCM16 little-endian mono 24 kHz.
///
/// `KletsoVoiceController` drives it: it opens capture when a session
/// starts, forwards every chunk, enqueues the assistant's audio as it
/// arrives, flushes on interruption and closes capture when the session
/// ends.
abstract interface class KletsoAudioIo {
  /// Asks the platform for microphone permission. Returns `true` when
  /// granted (or already granted).
  Future<bool> requestPermission();

  /// Starts the microphone and returns its PCM16 chunks (20–60 ms each).
  /// The stream ends when [closeCapture] is called.
  Future<Stream<Uint8List>> openCapture();

  /// Stops the microphone.
  Future<void> closeCapture();

  /// Queues assistant audio for playback, in order.
  void enqueue(Uint8List pcm);

  /// Drops everything queued and stops playback immediately (the user
  /// interrupted). Resets [playedMs].
  Future<void> flush();

  /// Milliseconds of audio actually played since the last [flush] (or since
  /// playback began), for `voice.played` reports and interruption cuts.
  int get playedMs;

  /// Loudness of what is playing right now, 0..1, for lip-sync and meters.
  KletsoValueListenable<double> get outputLevel;

  /// Loudness of the microphone input, 0..1.
  KletsoValueListenable<double> get inputLevel;

  /// Releases platform resources.
  Future<void> dispose();
}
