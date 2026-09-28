# kletso_core

Pure-Dart client for [Kletso](https://kletso.ai): sessions, a realtime
connection with reconnect and replay, conversation state and typed events.
No Flutter, no platform channels, no `dart:html`; runs on mobile, desktop,
Flutter Web and Wasm. Flutter apps use `kletso_flutter`, which builds on this.

## Quick start

```dart
import 'package:kletso_core/kletso_core.dart';

final client = await Kletso.init(KletsoConfig(
  publishableKey: 'kl_pub_…',   // never a secret key
  agentId: 'agt_…',
));
await client.authenticate(token: userJwt, onTokenExpired: fetchNewJwt);
// or: await client.identifyAnonymous();

client.messages.addListener(() => render(client.messages.value));   // List<KletsoMessage>
client.connection.addListener(() => banner(client.connection.value)); // closed|connecting|open|reconnecting
client.events.listen((e) => switch (e) {
  KletsoServerEvent(:final payload) => handle(payload),   // typed kletso.events/v1 payload
  KletsoClientError(:final exception) => log(exception),
  _ => null,
});

await client.send(const KletsoOutbound.text('Show me flights to Osaka'));
await client.send(KletsoOutbound.action(surfaceId: s, componentId: c, actionId: 'book', value: v));
client.setContext({'plan': 'pro'});
client.track('cart_abandoned', {'value': 129});
```

## Try it without a backend

```dart
import 'package:kletso_core/fake.dart';

final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
final client = KletsoClient(config, api: backend, transport: backend);
```

The fake speaks the real protocol from the `kletso_ui_schema` fixtures: say
"flight", "hotel", "products", "sales", "cancel my order", "callback", "order",
"human" or "error". `KletsoFakeScenario` adds latency, socket drops, duplicate
frames, token expiry, auth rejection and rate limits so reconnect paths can be
exercised in an app.

## How it fits together

| layer | class | job |
|---|---|---|
| entry | `Kletso` / `KletsoClient` | session, conversations, observables, `send` |
| state | `KletsoConversationState` | reduces the event log into immutable `KletsoMessage`s (deltas, tool calls, surfaces) |
| connection | `KletsoConnection` | reconnect loop with full-jitter backoff, heartbeat, `seq` replay and dedupe, bounded outbound queue |
| transport | `KletsoTransport` → `KletsoWebSocketTransport`, `KletsoSseTransport`, `KletsoAutoTransport` | first-frame auth, frame codec, close-code semantics |
| REST | `KletsoApi` → `KletsoHttpApi` | `/v1/sessions`, conversations, events, messages, actions, triggers |
| errors | `KletsoException` (sealed) | network, timeout, auth (`expired`), rate limit, protocol, server, tool, workflow, state, queue overflow |

Observables are `KletsoValueListenable`s (same shape as Flutter's
`ValueListenable`) plus one broadcast `Stream<KletsoEvent>`; wrap them with any
state library or none.

## Connection behaviour

- WebSocket first; after two consecutive handshake failures the session falls back to SSE (`KletsoTransportMode.auto`).
- Auth is the first frame (`{"t":"auth",…}`), never a query parameter. `ready{seq}` gates sending.
- Ping every 25 s; no pong in 10 s → close 4000 and reconnect. Backoff 500 ms → 30 s with full jitter, reset on `ready`.
- Resume with the last `seq`; duplicates and out-of-order events are dropped by `seq` and `id`.
- 4401 stops with `KletsoAuthException`; 4403 calls the refresher, then reconnects.
- Frames sent while not open are queued (100) and flushed after `ready` with their original `clientId`, so the server dedupes retries.
- `pause()`/`resume()` for app lifecycle; `dispose()` cancels every timer and subscription.

## Dependencies

`http`, `web_socket`, `clock`, `meta`, `kletso_ui_schema`. Dev: `test`, `fake_async`, `lints`.
