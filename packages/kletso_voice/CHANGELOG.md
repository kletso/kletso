## 0.1.2 — 2026-10-13

- Supports the same toolchain range as the rest of the SDK: Dart ^3.9.0 / Flutter ≥3.35.0 (0.1.x required Dart ^3.13.4 through the `record_*` 2.x platform packages, which need Flutter 3.44 / Dart 3.12). The `record_*` constraints now accept the 1.x and 2.x lines; pub picks 2.x on Flutter 3.44+ and 1.x below. No code changes.

## 0.1.1 — 2026-10-07

- Shorter pubspec description (pub.dev conventions). No code changes.

## 0.1.0 — 2026-10-07

- Initial release: `KletsoVoice.install(client)` wires microphone capture and speaker playback into `KletsoClient.voice`. PCM16 24 kHz capture through `record_*` platform packages (Android, iOS, macOS, Windows, Linux) and the package's own `package:web` Web Audio capture on the web (Wasm-safe, no `dart:html`); low-latency playback through `audio_stream_player`. Permission request helper, level metering for the avatar lip-sync.
