import 'package:kletso_core/kletso_core.dart';

import 'device_audio_io.dart';

/// Entry point: installs the device audio into a client.
abstract final class KletsoVoice {
  /// Creates a [KletsoDeviceAudioIo] and hands it to `client.voice`. Returns
  /// it so hosts can dispose it with the client or tweak capture options.
  static KletsoDeviceAudioIo install(KletsoClient client) {
    final io = KletsoDeviceAudioIo();
    client.voice.setAudioIo(io);
    return io;
  }
}
