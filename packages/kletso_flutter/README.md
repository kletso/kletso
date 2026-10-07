# kletso_flutter

Embeddable [Kletso](https://kletso.ai) AI chat for Flutter apps: a streaming
chat widget, a floating launcher, and server-driven UI (`kletso.ui/v1`) rendered
through **your own widgets**. Pure Dart, no platform channels, works on
Android, iOS, web (JS and Wasm) and desktop. One dependency.

## 20-line quick start

```dart
import 'package:flutter/material.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

Future<void> main() async {
  await Kletso.init(KletsoConfig(publishableKey: 'kl_pub_…', agentId: 'agt_…'));
  await Kletso.instance.identifyAnonymous();              // or authenticate(token: jwt)
  Kletso.instance
    ..registerComponent('acme.productCard', (ctx, node) => ProductCard(
          name: node.string('name'),
          price: node.number('price'),
          onView: () => ctx.executeAction('view'),
        ))
    ..registerAction('open_product', (args, ctx) =>
        Navigator.of(ctx.context).pushNamed('/product/${args['sku']}'))
    ..onOpenUrl = (uri) => launchUrl(uri);                  // url_launcher, or your router
  runApp(const MyApp());
}

// anywhere in the tree:
//   KletsoLauncher()                          floating bubble → opens the chat sheet
//   Kletso.instance.open(context)             open programmatically
//   KletsoChat()                              embed the chat in your own page
```

Try it without a backend:

```dart
final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
await Kletso.init(config, api: backend, transport: backend);
```

## What you get

| widget | purpose |
|---|---|
| `KletsoChat` | header, connection banner, reverse message list, streaming bubbles, tool-call chips, rendered surfaces, typing indicator, composer |
| `KletsoLauncher` | floating bubble with unread dot; `open()` shows a sheet (phone) or a docked panel (wide screens) or a full-screen route |
| `KletsoSurfaceView` | renders one `kletso.ui/v1` surface; use it to preview surfaces or embed them outside the chat |
| `KletsoConversationList` | the user's conversations with a "new conversation" row |
| `KletsoTheme` | `ThemeExtension` generated from the Kletso design tokens; `KletsoTheme.fromServer(bootstrap.theme)` applies your dashboard branding |

## Custom components

The agent decides *what* to show; your app decides *how*. Register a builder
per type; the SDK resolves `{ "path": … }` bindings, enforces limits (≤ 500
components, depth ≤ 16, ≤ 256 KB) and falls back to plain text for anything
unknown, so a model mistake never crashes your app.

```dart
Kletso.instance.registerComponent(productCardSpec.type, (ctx, node) => ProductCard(
  sku: node.string('sku'),                 // typed getters never throw
  price: node.number('price'),
  inStock: node.boolean('inStock'),
  onView: () => ctx.executeAction('view'), // local  → your registerAction handler
  onAdd:  () => ctx.executeAction('add'),  // agent  → posted back as the user's next turn
), spec: productCardSpec);
```

Declare the props schema once as a `KletsoComponentSpec` in
`lib/kletso_components.dart` (import `package:kletso_core` only, no Flutter)
and run `dart run kletso_flutter:sync` to produce `kletso.components.json` for
the dashboard, so the model's `render_ui` tool schema always matches your
widgets.

Built-ins shipped (30): text, markdown, card, row, column, divider, image,
avatar, button, list, table, chart (bar/line/pie, no dependency), carousel,
form, input, select, confirm, loading, error, badge, link, **map** (schematic
map with markers and route), **video** and **audio** (poster/waveform, open
through `onOpenUrl`), **rating** (interactive stars), **steps** (timeline),
**accordion**, **tabs**, **countdown** (live), **progress**. Host builders may
override any of them by name: the example app swaps `map` for `flutter_map`
tiles and `video`/`audio` for `video_player`, so the agent emits the same JSON
and the app decides how rich it looks.


### Avatar pictures per mood

With the avatar style set to **Your image** in the dashboard, the host app can
show its own pictures instead of the mascot, one per mood. `KletsoChat` and
`KletsoLauncher` pick them up from the session bootstrap automatically; a
hand-rolled surface does the same through `KletsoClientAvatar`:

```dart
final avatar = KletsoClientAvatar(client);
// avatar.imageFor(KletsoAvatarMood.happy) → the URL from the dashboard, or null
Widget face = avatar.build(size: 96); // crossfades between moods, breathes, bounces while speaking
```

Or drive `KletsoAvatar` directly with `moodImages` (any `ImageProvider`,
including animated GIF/WebP). Pictures change at runtime whenever a new
bootstrap arrives; nothing to restart.

## Every interaction direction

| direction | how |
|---|---|
| app → Kletso | `track`, `screen`, `setContext`/`updateContext`, `open`, `close`, `useAgent`, `logout`, `pause`/`resume` |
| Kletso → app UI | streamed text, `ui.render` surfaces, proactive trigger turns |
| user in chat → agent | `agent`/`submit`/`confirm`/`workflow` actions and text |
| user in chat → your app | `local` actions → `registerAction` handler (navigate, add to cart, `ctx.client!.close()`); echoed to the runtime as analytics only |
| both in one tap | your builder changes app state **and** calls `ctx.executeAction('add')`; or a `local` handler calls `ctx.client!.send(...)` |
| agent → your app, no tap | `app.command` → your registered handler, only with `KletsoConfig(allowServerCommands: true)` and `client.ui.contextProvider` set; outcomes on `client.ui.commandResults` |
| silent app event → proactive UI | `track('geofence_entered')` → server rule → `app.notify` → `KletsoNotificationHost` banner/toast/alert (or your OS tray via `onSystemNotification`); tap opens the chat and/or runs a `local`/`url`/`agent` action |
| runtime → device while backgrounded | push: `registerPushToken(KletsoPushToken(...))` once, then `handlePushPayload(message.data)` from your push plugin; same rendering and dedupe as live |

Triggers: `track('cart_abandoned')` and `screen('checkout')` let the agent
speak first. A trigger that opens a new conversation still reaches the device
(session-level events), lights the launcher's unread dot, and `open()` lands
on that conversation.

## Proactive notifications

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) =>
      KletsoNotificationHost(client: Kletso.instance, child: child!),
);
Kletso.instance.ui.contextProvider = () => navigatorKey.currentContext;
// optional: OS tray for `system` notifications (your plugin, not ours)
Kletso.instance.onSystemNotification = (n) async {
  await localNotifications.show(/* n.title, n.payload.body, payload: n.id */);
  return true; // false → the SDK shows its banner instead
};
// on OS-notification tap: Kletso.instance.ui.openNotification(n)
// push while backgrounded:
await Kletso.instance.registerPushToken(
  KletsoPushToken(platform: KletsoPushPlatform.fcm, token: fcmToken),
);
FirebaseMessaging.onMessage.listen((m) => Kletso.instance.handlePushPayload(m.data));
```

Channels: `banner` (top card, auto-dismiss), `toast` (bottom pill), `alert`
(dialog), `system` (your tray, banner fallback), `silent` (no UI: just open the
chat / run the action). Payloads may carry an inline `kletso.ui/v1` surface and a
tap `action`. Outcomes stream on `client.ui.notificationResults`.

## Security defaults

- Only the publishable key ships in the app; user identity is a host-signed token.
- Markdown renders links only; no inline HTML. Links, images and `url` actions
  pass the session's host allowlist; `javascript:`/`data:`/`http:` never open.
- Payload size, depth and count limits are enforced before anything is built.

## Markdown

`KletsoPlainMarkdownRenderer` (default) covers headings, emphasis, code, lists,
quotes, rules and links with zero dependencies and is Wasm-clean. Pass another
`KletsoMarkdownRenderer` (e.g. wrapping `gpt_markdown`) to `KletsoChat` if you
need tables or LaTeX.

## Dependencies

`flutter`, `kletso_core`, `kletso_ui_schema`, `meta`. Fonts: Plus Jakarta Sans
(OFL) bundled; `KletsoTheme.light(useHostFont: true)` to inherit yours.
