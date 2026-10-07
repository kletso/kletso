/// Microphone and speaker for Kletso voice sessions (D82).
///
/// `package:kletso_flutter` draws the mic button, the voice sheet and the
/// avatar, but ships no platform code. This package adds the audio:
///
/// ```dart
/// final client = await Kletso.init(config);
/// KletsoVoice.install(client);
/// ```
///
/// Capture uses the `record` platform implementations on Android, iOS,
/// macOS, Windows and Linux, and Web Audio (`package:web`) in browsers, so
/// Flutter Web builds stay Wasm-compatible. Playback uses
/// `audio_stream_player` everywhere. Hosts with their own audio stack can
/// implement `KletsoAudioIo` from `package:kletso_core` instead.
library;

export 'src/capture.dart' show KletsoCapture, KletsoCaptureConfig;
export 'src/device_audio_io.dart' show KletsoDeviceAudioIo, KletsoPcmSink;
export 'src/kletso_voice.dart' show KletsoVoice;
