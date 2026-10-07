# kletso_voice

Microphone and speaker for [Kletso](https://kletso.ai) voice sessions. `package:kletso_flutter` draws the mic button, the voice sheet and the avatar; this package adds the audio and installs itself into `KletsoClient` in one line.

```dart
import 'package:kletso_core/kletso_core.dart';
import 'package:kletso_voice/kletso_voice.dart';

final client = await Kletso.init(config);
KletsoVoice.install(client);   // capture + playback for client.voice
```

After that, `KletsoChat` shows the mic button whenever the agent has voice enabled in the Kletso dashboard, and `client.voice` (a `KletsoVoiceController`) can be driven directly: `start()`, `stop()`, `commit()` for push-to-talk, `state`, captions and interruption events.

## What it does

| Platform | Capture | Playback |
| --- | --- | --- |
| Android, iOS, macOS, Windows, Linux | `record_*` platform packages, PCM16 24 kHz | `audio_stream_player` |
| Web (JS and Wasm) | Web Audio through `package:web` (no `dart:html`) | `audio_stream_player` |

- Audio travels as binary PCM frames on the same `kletso.v1` WebSocket as the chat (`KletsoAudioFrame` from `kletso_ui_schema`).
- A level meter feeds the avatar lip-sync in `kletso_flutter`.
- `KletsoDeviceAudioIo` is the default `KletsoAudioIo`; hosts with their own audio stack implement `KletsoAudioIo` from `package:kletso_core` instead and skip this package.

## Permissions

- **Android**: `RECORD_AUDIO` in `AndroidManifest.xml`.
- **iOS / macOS**: `NSMicrophoneUsageDescription` in `Info.plist` (macOS also needs the audio-input entitlement).
- **Web**: the browser asks on first use; serve over https.

`KletsoVoice.requestPermission()` asks ahead of time; the controller asks on `start()` otherwise.

## Low-level pieces

- `KletsoCapture` / `KletsoCaptureConfig`: the platform capture interface (`requestPermission`, `start` → `Stream<Uint8List>` of PCM16, `stop`, `dispose`).
- `KletsoDeviceAudioIo`, `KletsoPcmSink`: capture + playback bundle used by `install`.

## See also

- Docs: [Voice and avatar](https://kletso.ai/docs/flutter/voice)
- `kletso_flutter`: chat UI, voice sheet, avatar
- `kletso_core`: client, `KletsoVoiceController`, `KletsoAudioIo`
