## 0.1.0 — 2026-10-07

- Initial release: `KletsoVoice.install(client)` wires microphone capture and speaker playback into `KletsoClient.voice`. PCM16 24 kHz capture through `record_*` platform packages (Android, iOS, macOS, Windows, Linux) and the package's own `package:web` Web Audio capture on the web (Wasm-safe, no `dart:html`); low-latency playback through `audio_stream_player`. Permission request helper, level metering for the avatar lip-sync.
