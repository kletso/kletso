# Kletso Flutter SDK

[Kletso](https://kletso.ai) is an embeddable AI assistant for Flutter apps. The assistant answers with **your own
widgets** (server-driven UI over the `kletso.ui/v1` protocol), calls **your own APIs** as the signed-in user, and
speaks up proactively when rules you write in the dashboard say so. Pure Dart: Android, iOS, web (JS and Wasm), desktop.

| Package | What it is |
|---|---|
| [`kletso_flutter`](packages/kletso_flutter) | Chat UI, launcher, 30 built-in blocks, component and action registries, notification host, `kletso_flutter:sync` |
| [`kletso_voice`](packages/kletso_voice) | Microphone and speaker for voice sessions (`KletsoVoice.install(client)`); Wasm-safe web capture |
| [`kletso_core`](packages/kletso_core) | `KletsoClient`: sessions, WebSocket/SSE transports with replay, context and events, notifications and push handoff, fake backend for tests |
| [`kletso_ui_schema`](packages/kletso_ui_schema) | JSON schemas, fixtures and Dart models for `kletso.ui/v1`, `kletso.events/v1` and the realtime frames |

```dart
final client = await Kletso.init(KletsoConfig(publishableKey: 'kl_pub_…', agentId: 'agt_…'));
await client.identifyAnonymous();                     // or authenticate(token: hostJwt)
client.registerComponent('acme.productCard', (ctx, node) => ProductCard(name: node.string('name')));
// in the tree: KletsoLauncher(), and KletsoNotificationHost(client: client, child: app)
```

Documentation: https://kletso.ai/docs · Quickstart: https://kletso.ai/docs/start/quickstart

## Develop

```bash
flutter pub get            # pub workspace: resolves all packages together
cd packages/kletso_core && dart test
cd packages/kletso_flutter && flutter test
```

Licence: MIT.
