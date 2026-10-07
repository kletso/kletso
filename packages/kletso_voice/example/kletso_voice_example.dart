// Add microphone and speaker to a Kletso client in one line. In a real app use
// your publishable key; the fake backend here only shows the wiring.
import 'dart:io';

import 'package:kletso_core/fake.dart';
import 'package:kletso_core/kletso_core.dart';
import 'package:kletso_voice/kletso_voice.dart';

Future<void> main() async {
  final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
  final client = await Kletso.init(
    KletsoConfig(publishableKey: 'kl_pub_dev_example', agentId: 'agt_demo'),
    api: backend,
    transport: backend,
  );

  // Capture (record_* / Web Audio) and playback (audio_stream_player) for client.voice.
  final audio = KletsoVoice.install(client);
  stdout.writeln('voice audio installed: $audio');

  // From here the chat widgets show a mic button when the agent has voice
  // enabled; or drive the controller yourself:
  //   await client.voice.start();   // asks for the microphone on first use
  //   await client.voice.stop();
  await client.dispose();
}
