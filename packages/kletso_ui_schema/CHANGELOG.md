## 0.1.0 (unreleased)

- `app.notify` event type + `KletsoAppNotification` payload (`KletsoNotificationChannel`), schema `appNotification` def (D57).
- `ui.patch` event + `KletsoUiPatch`; `KletsoSurface.patched`, host-first `/host/` bindings (`resolveNode(external:)`).
- `app.command` event type + `KletsoAppCommand` payload.
- Built-in types map, video, audio, rating, steps, accordion, tabs, countdown, progress; `KletsoNode.allChildIds`; fixtures media_hub and trip_plan.
- Initial protocol package: `kletso.ui/v1` surface model with validation and
  limits, `kletso.events/v1` envelope with typed payloads, realtime frames,
  JSON Schemas (Draft 2020-12), conformance fixtures (valid/invalid surfaces,
  20-message conversation log, frames) embedded as Dart constants, fixture
  generators and the canonical `KletsoConversationScript`.
