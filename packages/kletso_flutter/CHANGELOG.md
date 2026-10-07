## 0.2.0 — %s

- Voice UI (D78–D83): mic button in the composer, `KletsoVoiceButton`, `KletsoVoiceSheet` (avatar, captions, surfaces, mute / type instead / End, push-to-talk), `KletsoClientAvatar` binding (mood rules, `avatar.mood`, lip-sync level). Install `package:kletso_voice` for microphone and speaker.
- Requires `kletso_core ^0.2.0` and `kletso_ui_schema ^0.2.0`.

- Per-mood avatar pictures: `KletsoAvatar.moodImages` (one `ImageProvider` per `KletsoAvatarMood`, crossfade on mood change, breathing idle loop, lip-sync bounce, pre-cached, animated GIF/WebP play as-is; falls back to `imageProvider`, then the mascot). `KletsoClientAvatar` parses the bootstrap's `avatar.images` (`images`, `imageFor`, `parseImages`), is now a `Listenable`, and `build()` rebuilds when a new bootstrap changes the pictures.
- Animated Kletso mascot avatar (D81): `KletsoAvatar` widget (styles `kletso`/`image`/`none`), `KletsoAvatarController` (mood, allowed moods, ttl rules, lip-sync `level`), `KletsoAvatarMood`, `KletsoAvatarFaceParams`, `KletsoAvatarPainter`/`KletsoAvatarColors`, generated `KletsoAvatarFaceData` from `packages/design/avatar.json` (`tool/gen_avatar.dart`). Wired into `KletsoBotBubble` (small avatar, optional shared controller) and `KletsoLauncher` (new `KletsoTheme.launcherIcon`: `chat`/`sparkle`/`mascot`, wink on unread, thinking while `client.agentTyping`); `KletsoTheme.fromServer` now parses `launcher.icon`.

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
