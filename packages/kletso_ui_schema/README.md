# kletso_ui_schema

Protocol package for [Kletso](https://kletso.ai): the JSON Schemas, hand-written
Dart models and conformance fixtures for

- `kletso.ui/v1` — server-driven UI surfaces (flat component map, JSON-pointer
  data bindings, actions, mandatory plain-text fallback),
- `kletso.events/v1` — the event envelope with per-conversation `seq`,
- the realtime WebSocket frames (client → server and server → client).

It has no Flutter dependency. `kletso_core` and `kletso_flutter` build on it;
the runtime Worker and the web widget validate against the same schemas and
fixtures.

## Quick start

```dart
import 'package:kletso_ui_schema/kletso_ui_schema.dart';

// Validate a ui.render payload the way an SDK must: bytes → structure → limits.
final result = KletsoSurface.parse(rawJsonText, knownTypes: {'acme.productCard'});
switch (result) {
  case KletsoSurfaceOk(:final surface, :final issues):
    final root = surface.rootNode!;                 // KletsoNode
    final node = surface.resolveNode(root);         // bindings → values
    print(node.string('title'));
    for (final child in root.childIds()) { /* surface.node(child) */ }
    for (final issue in issues) print(issue);       // non-fatal findings
  case KletsoSurfaceRejected(:final fallbackText, :final fatalIssues):
    print(fallbackText ?? fatalIssues.first.message);
}

// Events and frames.
final frame = KletsoServerFrame.fromJson(jsonDecode(wireText));
if (frame case KletsoEventFrame(:final event)) {
  switch (event.payload) {
    case KletsoMessageDelta(:final messageId, :final text): /* append */
    case KletsoUiRender(:final rawSurface): /* KletsoSurface.parseJson(rawSurface) */
    default: break;
  }
}
final out = jsonEncode(const KletsoAuthFrame(token: 'kst_…', after: 41).toJson());
```

## What is in the box

| path | purpose |
|---|---|
| `schemas/kletso.ui.v1.json` | Draft 2020-12 schema for surfaces, every built-in type's props, actions |
| `schemas/kletso.events.v1.json` | Event envelope + per-type `data` shapes |
| `schemas/kletso.realtime.v1.json` | Client and server frames, close codes |
| `fixtures/ui/valid/*.json` | flight card, hotel card, product cards (custom type), chart, form, confirm, quick replies, a surface using every classic built-in, `media_hub` (map, video, audio, rating, countdown), `trip_plan` (tabs, steps, accordion, progress) |
| `fixtures/ui/invalid/*.json` + `manifest.json` | unknown type, cycle, depth overflow, oversize, too many components, long string/array, missing root/fallback, wrong schema… with the expected outcome of each |
| `fixtures/events/conversation_20.json` | a 20-message conversation log with contiguous `seq` (greeting → flights → card → chips → chart → hotel → products → confirmed tool call → handoff) |
| `fixtures/realtime/*.json` | one example of every frame |
| `lib/` | `KletsoSurface`, `KletsoNode`, `KletsoAction` (sealed), `KletsoBinding`, `KletsoUiLimits`, `KletsoUiIssue`, `KletsoEventEnvelope`, `KletsoEventPayload` (sealed), `KletsoClientFrame` / `KletsoServerFrame` (sealed), `KletsoFixtures`, `KletsoSchemas`, `KletsoConversationScript`, `KletsoFixtureGenerators` |

Fixtures and schemas are embedded into Dart (`KletsoFixtures`, `KletsoSchemas`)
so tests in other packages and the fake transport need no file IO and run on
the web. The oversize fixture is produced by `KletsoFixtureGenerators.oversize()`
instead of being embedded.

## Design rules

- **Liberal in, strict out.** `fromJson` throws `KletsoSchemaException` only for
  shape problems. Unknown component types, action kinds, event types and server
  frames are preserved and reported, never thrown.
- **Limits before trust.** `KletsoSurface.parse` checks the byte size before
  decoding, then components ≤ 500, depth ≤ 16, strings ≤ 8 KB, arrays ≤ 200,
  cycles and dangling children. Fatal issues reject the surface but keep the
  `fallbackText` so the client can still show something.
- **Fixtures are the contract.** Every valid fixture must pass the JSON Schema
  and round-trip through the models; every invalid fixture must produce the
  issue code listed in `manifest.json`. The Worker validator and the web widget
  run the same files.

## Regenerating

```sh
dart run tool/gen_fixtures.dart   # conversation_20.json + size-limit fixtures
dart run tool/embed.dart          # lib/src/generated/embedded.g.dart (tests check it is current)
```

## Dependencies

- `meta` — `@immutable` annotations.
- dev: `json_schema` (independent validator for the conformance tests), `lints`, `test`.
