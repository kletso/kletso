import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

import 'capture.dart';

/// Microphone through the `record` platform implementations (Android, iOS,
/// macOS, Windows, Linux). The web implementation of `record` is not used
/// (it imports `dart:html`); see `capture_web.dart`.
final class PlatformCapture implements KletsoCapture {
  /// Creates a capture.
  PlatformCapture();

  static int _ids = 0;
  final String _id = 'kletso_voice_${++_ids}';
  bool _created = false;
  bool _recording = false;

  RecordPlatform get _p => RecordPlatform.instance;

  Future<void> _ensure() async {
    if (_created) return;
    await _p.create(_id);
    _created = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensure();
    return _p.hasPermission(_id);
  }

  @override
  Future<Stream<Uint8List>> start(KletsoCaptureConfig config) async {
    await _ensure();
    final stream = await _p.startStream(
      _id,
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: config.sampleRate,
        numChannels: 1,
        echoCancel: config.echoCancel,
        noiseSuppress: config.noiseSuppress,
        autoGain: config.autoGain,
      ),
    );
    _recording = true;
    return stream;
  }

  @override
  Future<void> stop() async {
    if (!_recording) return;
    _recording = false;
    await _p.stop(_id);
  }

  @override
  Future<void> dispose() async {
    await stop();
    if (_created) {
      _created = false;
      await _p.dispose(_id);
    }
  }
}
