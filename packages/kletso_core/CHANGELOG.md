## 0.2.5 — 2026-10-14

- Frames sent right after `attach()`/`startConversation()` are held until the server's `ready` for that conversation; fixes `not attached to a conversation` errors and lost first messages.

## 0.2.4 — 2026-10-13

- `clock` constraint relaxed to `^1.1.1`. `^1.1.3` (released 2026-08-28) could not be solved on Flutter 3.38 and older, whose `flutter_test` pins `clock 1.1.2`, so any app with `flutter_test` failed version solving. Only `clock.now()` is used. No code changes.

## 0.2.3 — 2026-10-09

- `KletsoMessage.pending`: loaders for surfaces still streaming (`ui.pending`), replaced by the matching `ui.render` (same tool call, else same surface id, else the oldest) and cleared on `message.completed`.

## 0.2.2 — 2026-10-09

- A dropped socket no longer surfaces as a `KletsoNetworkException("connection lost …")` error event; the loop reconnects and replays from the last `seq` as before, and hosts see `KletsoConnectionChanged(reconnecting → open)`. Errors are still reported when the reconnect itself fails. (On Android, dart:io reports any socket-level failure, such as the OS aborting an idle socket after backgrounding, as close code 1002.)
- `KletsoConnectionChanged.reason` and `KletsoConnection.stateReason` carry the close info or error behind a state change.

## 0.2.1 — 2026-10-07

- Shorter pubspec description (pub.dev conventions). No code changes.

## 0.2.0 — 2026-10-07

- Voice: `KletsoClient.voice` (`KletsoVoiceController`: start/stop/commit, push-to-talk, state, captions, interruption), `KletsoAudioIo` (plug a microphone/speaker implementation such as `package:kletso_voice`), binary audio over the WebSocket transport and connection (`supportsBinary`, `audio` stream, `sendAudio`), `KletsoVoiceInfo` in the session bootstrap (`voiceEnabled`, `pushToTalk`).
- Avatar: bootstrap `avatar` block parsed for the Flutter SDK (`style`, colours, `imageUrl`, per-mood `images`, moods, rules, agent-picked moods); `avatar.mood` events relayed.
- Fake backend: voice turns (`onVoiceStart`/`onVoiceStop`/`onAudioIn`/`onVoiceCommit`/`onVoiceText`), synthetic audio tones, moods, `fakeAvatar`.
- Depends on `kletso_ui_schema ^0.2.0`.

## 0.1.0 — 2026-09-29

- Proactive notifications: `KletsoClient.notifications`, `KletsoNotification`, `registerPushToken`/`unregisterPushToken` (`KletsoPushToken`, `KletsoApi` + HTTP `PUT/DELETE /sessions/current/push-token`), `handlePushPayload` with dedupe (D57, D59).
- Fake: `notify()`, `sendPush()`, `pushTokens`; trigger rules `geofence_entered`, `payment_failed`, `order_shipped`; `_Reply.notification`.
- API review (D56): transports renamed `KletsoWebSocketTransport`/`KletsoSseTransport`/`KletsoAutoTransport`; `KletsoSseParser.retry`/`lastEventId` read-only.
- `ui.patch` reducer support; host-bound surfaces.
- Initial client: `KletsoConfig`, `KletsoClient` + `Kletso.init()/instance`,
  sessions (`authenticate`, `identifyAnonymous`, refresh, `logout`),
  conversations, `send(KletsoOutbound)`, context, triggers, typed exceptions,
  `KletsoValueListenable` observables and a broadcast `Stream<KletsoEvent>`.
- `KletsoConnection`: first-frame auth via the transport, heartbeat, full-jitter
  backoff, `seq` replay with id dedupe, bounded outbound queue, 4401/4403 handling,
  pause/resume.
- Transports: `KletsoWebSocketTransport` (`package:web_socket`), `KletsoSseTransport`
  (`package:http` streaming + REST upstream), `KletsoAutoTransport` fallback.
- `KletsoConversationState` reducer (deltas, tool calls, surfaces, pending echo).
- `package:kletso_core/fake.dart`: `KletsoFakeBackend` + `KletsoFakeScenario`.
- `KletsoConfig.allowServerCommands`; fake replies with `app.command` for "open trail runner"; `KletsoFakeBackend.contextOf`.
- Fake backend: trigger rules (cart_abandoned, checkout), session-level delivery for unattached sockets, `sampleMedia` scenario flag, media/trip replies.
- `KletsoComponentSpec` (custom component declaration for the sync manifest).
