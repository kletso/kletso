## 0.1.0 (unreleased)

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
