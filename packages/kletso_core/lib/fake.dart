/// In-memory backend for demos and tests: implements both `KletsoApi` and
/// `KletsoTransport`, replies from the protocol fixtures, and can simulate
/// latency, socket drops, duplicate frames, token expiry and errors.
///
/// ```dart
/// final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
/// final client = KletsoClient(config, api: backend, transport: backend);
/// ```
library;

export 'src/fake/fake_backend.dart' show KletsoFakeBackend;
export 'src/fake/scenario.dart' show KletsoFakeScenario;
