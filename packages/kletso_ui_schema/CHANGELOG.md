## 0.2.0 — 2026-10-07

- Voice protocol: client frames `voice.start` / `voice.stop` / `voice.commit` / `voice.played` / `voice.text` (`KletsoVoiceStartFrame`, `KletsoVoiceStopFrame`, …, `KletsoVoiceMode`, `KletsoVoiceStopReason`) and binary PCM16 24 kHz audio frames (`KletsoAudioFrame`, kinds `audioIn` 0x01 / `audioOut` 0x02, `decode`, `rms`, `duration`).
- Events `voice.started`, `voice.state`, `voice.transcript`, `voice.interrupted`, `voice.ended` (`KletsoVoiceStarted`, `KletsoVoiceStateEvent`, `KletsoVoiceTranscript`, `KletsoVoiceInterrupted`, `KletsoVoiceEnded`, `KletsoVoiceState`, `KletsoVoiceEndReason`) and `avatar.mood` (`KletsoAvatarMoodEvent`, `KletsoMoodSource`).
- `message.*` payloads carry `modality` (`KletsoMessageModality`: text / voice).
- Session bootstrap documents `voice` and `avatar` blocks (`avatar.images`: one https picture per mood, next to `imageUrl`).
- Fixtures: `eventsVoiceTurn`; JSON Schemas updated for the new frames and events.

## 0.1.0 — 2026-09-29

- `app.notify` event type + `KletsoAppNotification` payload (`KletsoNotificationChannel`), schema `appNotification` def (D57).
- `ui.patch` event + `KletsoUiPatch`; `KletsoSurface.patched`, host-first `/host/` bindings (`resolveNode(external:)`).
- `app.command` event type + `KletsoAppCommand` payload.
- Built-in types map, video, audio, rating, steps, accordion, tabs, countdown, progress; `KletsoNode.allChildIds`; fixtures media_hub and trip_plan.
- Initial protocol package: `kletso.ui/v1` surface model with validation and
  limits, `kletso.events/v1` envelope with typed payloads, realtime frames,
  JSON Schemas (Draft 2020-12), conformance fixtures (valid/invalid surfaces,
  20-message conversation log, frames) embedded as Dart constants, fixture
  generators and the canonical `KletsoConversationScript`.
