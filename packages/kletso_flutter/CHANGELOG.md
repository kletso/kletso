## 0.1.0 — 2026-09-29

- `KletsoNotificationHost` (banner/toast/alert, `system` → `onSystemNotification` with banner fallback, `silent`), `KletsoUi.openNotification`, `notificationResults`, `KletsoActionOrigin.notification` (D58).
- API review (D56): `KletsoFormat.duration` (was `kletsoDuration`), `runLocalAction` internal, `KletsoUi.isOpen` read-only, `onOpenUrl` getter, `KletsoBotBubble.agentName` removed.
- Host data bindings (`setHostData`/`updateHostData`, `/host/` paths), `KletsoTheme.dark()`/`forBrightness`, live `ui.patch` rendering.
- `client.close()`, `app.command` handling (opt-in, `KletsoUi.contextProvider`, `commandResults`), `KletsoActionOrigin`, `runLocalAction`.
- Complex blocks: map, video, audio, rating, steps, accordion, tabs, countdown, progress (plugin-free defaults, host-overridable).
- Initial release: `KletsoChat`, `KletsoLauncher`, `open()`/`bindAppLifecycle()`,
  `KletsoSurfaceView` with the 21 built-in blocks, host `registerComponent` /
  `registerAction` / `onOpenUrl`, `KletsoComponentSpec` + `kletso_flutter:sync`,
  `KletsoTheme` generated from the design tokens, `KletsoPlainMarkdownRenderer`,
  `KletsoUrlPolicy`, `KletsoConversationList`.
