---
name: kletso_flutter-integrate
description: Integrate the Kletso AI chat SDK (kletso_flutter) into a Flutter app - init, authenticate end users, launcher/open/embed, register custom components with specs, local actions, context and triggers, theming, url handling, testing with the fake backend, and the sync command for the dashboard. Use whenever a Flutter project adds or changes Kletso.
---

# Integrate kletso_flutter

## 1. Install
`flutter pub add kletso_flutter` (+ `url_launcher` if you want `url` actions to open a browser). Nothing else: no platform setup, no codegen, Wasm-clean.

## 2. Initialise once, before `runApp`
```dart
await Kletso.init(KletsoConfig(publishableKey: 'kl_pub_…', agentId: 'agt_…'));
```
Never put a `kl_sec_` key in the app; `KletsoConfig` throws if you try. Options: `environment`, `transport` (auto → ws then sse), `baseUrl`, `logLevel`, `reportLocalActions`.

## 3. Identify the user
- Logged in: your backend signs a short-lived JWT for the user; `await Kletso.instance.authenticate(token: jwt, onTokenExpired: () => fetchNewJwt())`.
- Anonymous: `await Kletso.instance.identifyAnonymous()` (visitor id persisted via `KletsoTokenStore`; default memory, implement the interface for secure storage).
- `logout()` on sign-out. Call `Kletso.instance.bindAppLifecycle()` once to pause/resume the socket with the app.

## 4. Show the chat
- `KletsoLauncher()` in a `Stack`/`floatingActionButton` → tap opens a sheet.
- `Kletso.instance.open(context, presentation: KletsoPresentation.fullscreen)` from any button.
- `KletsoChat()` to embed in your own screen (tabs, side panels).
Theme: register `KletsoTheme` on `ThemeData.extensions`, or pass `theme:`; `KletsoTheme.fromServer(client.session.value!.theme)` applies dashboard branding.

## 5. Custom components (your widgets, the agent's data)
1. Declare a spec in `lib/kletso_components.dart`. That file imports only `package:kletso_core/kletso_core.dart` (no Flutter) so the sync command can run it with plain `dart`:
```dart
import 'package:kletso_core/kletso_core.dart';
const productCardSpec = KletsoComponentSpec(type: 'acme.productCard', description: '…', props: {json schema}, example: {...}, actions: ['view','add']);
const kletsoComponents = <KletsoComponentSpec>[productCardSpec];
```
2. Register the builder: `Kletso.instance.registerComponent(productCardSpec.type, (ctx, node) => MyWidget(name: node.string('name'), onTap: () => ctx.executeAction('view')), spec: productCardSpec);`
   - `node.string/number/boolean/list/map/mapList` never throw; bindings are already resolved.
   - `ctx.child(id)` / `ctx.children()` render nested components; `ctx.theme` gives roles; `ctx.openUrl(url)` respects the allowlist.
3. Local actions: `registerAction('open_product', (args, ctx) => Navigator.of(ctx.context).push(...))`. `agent`/`submit`/`confirm`/`workflow` actions are sent by the SDK; you never build frames.
4. `dart run kletso_flutter:sync` → `kletso.components.json`; import in the dashboard (Components → Sync from code) so the model's `render_ui` tool only emits your props.

## 5b. Interaction directions (checklist)
- Chat → app: `registerAction(name, handler)`; handler gets `args`, `ctx.context`, `ctx.client` (call `ctx.client!.close()` to dismiss the chat before navigating, `ctx.client!.send(...)` to also tell the agent). Local actions are echoed to the runtime as analytics (`ui.action` with `{local, handled}`), never as a user turn.
- Both in one tap: in your component builder do your app change and `ctx.executeAction('add')` together.
- Agent → app without a tap: `KletsoConfig(allowServerCommands: true)`, `client.ui.contextProvider = () => navigatorKey.currentContext`, register the names you allow. Unregistered names are ignored; watch `client.ui.commandResults`.
- App → chat: `Kletso.instance.open(context)`, `Kletso.instance.close()`, `switchConversation(id)`.

## 5c. Proactive notifications and push
- Mount `KletsoNotificationHost(client: Kletso.instance, child: child!)` in `MaterialApp.builder` and set `client.ui.contextProvider`. Silent events (`track('geofence_entered', {...})`) let server rules answer with `app.notify`: banner / toast / alert appear without a chat message; `openChat` opens the chat on that conversation; `action` runs your `local` handler (origin `KletsoActionOrigin.notification`), a URL, or sends a value to the agent.
- OS tray: `client.onSystemNotification = (n) async { ...show with your plugin...; return true; }`; on tap call `client.ui.openNotification(n)`. Return `false` (or leave it unset) to get the SDK banner.
- Push: after auth `client.registerPushToken(KletsoPushToken(platform: KletsoPushPlatform.fcm, token: t))`; feed every push data map to `client.handlePushPayload(data)` (ignores non-Kletso pushes, dedupes on `notificationId`). Do not add a push plugin to the SDK; it lives in the app.
- Test without a backend: `KletsoFakeBackend.notify(userId, KletsoAppNotification(...))` (live) and `sendPush(...)` (returns the push data map).

## 6. Context and triggers
`setContext({...})` / `updateContext({...})` for runtime facts (plan, orderId, screen). `track('cart_abandoned', {...})` and `screen('checkout')` fire dashboard triggers. `useAgent('agt_sales')` switches the agent for new conversations.

## 7. URLs
Set `Kletso.instance.onOpenUrl = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);` (or route internally). Only https hosts in the session allowlist reach it.

## 8. Test without a backend
```dart
final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
await Kletso.init(config, api: backend, transport: backend);
```
Say "flight", "hotel", "products", "sales", "where is my courier" (map/video/audio/rating/countdown), "my trip plan" (tabs/steps/accordion/progress), "cancel my order", "callback", "order", "human", "error", "long". Triggers: `track('cart_abandoned')`, `screen('checkout')`. Scenario knobs: `dropSocketAfterEvents`, `duplicateEveryNth`, `expireTokenAfterEvents`, `failHandshakes`, `rejectToken`, `rateLimitEveryNthMessage`, `seedConversationLog`. Widget tests: render any `KletsoSurface` with `KletsoSurfaceView(surface:, registry:, dispatcher:)` and an observer.

## 9. Observe state
`client.messages`, `client.connection`, `client.agentTyping`, `client.conversations`, `client.activeConversation`, `client.session` are `KletsoValueListenable`s (`.asFlutter()` for `ValueListenableBuilder`); `client.events` is a broadcast stream of `KletsoServerEvent | KletsoConnectionChanged | KletsoClientError | KletsoUnknownComponent | KletsoLocalActionRan`.

## 10. Voice and avatar (0.2.0)
Voice is configured per agent in the dashboard (Agent → Voice, customer's OpenAI key). The chat shows a mic button once the bootstrap says voice is enabled **and** audio is installed: `flutter pub add kletso_voice`, then `KletsoVoice.install(client)` right after `Kletso.init`. Add `RECORD_AUDIO` (Android) / `NSMicrophoneUsageDescription` (iOS, macOS). `client.voice` is a `KletsoVoiceController` (`start`, `stop`, `commit` for push-to-talk, `state`, captions). `KletsoVoiceSheet` is the full-screen voice UI; `KletsoVoiceButton` the compact one.
The avatar (`KletsoAvatar`, `KletsoClientAvatar`) follows the dashboard's Avatar tab: mascot with colours, or the customer's pictures (`avatar.imageUrl` default + `avatar.images[mood]` per mood, crossfade / breathing / talk bounce handled by the widget), moods from rules (`avatar.mood` events) and lip-sync from the voice level. Pass `moodImages` when you build `KletsoAvatar` yourself; `KletsoClientAvatar` does it from the bootstrap and re-renders when the agent is republished.

## Don'ts
No secret keys in the app · don't parse surfaces yourself · don't await `Kletso.instance.open()` inside `initState` · don't register a builder that throws on missing props (use the typed getters' defaults).
