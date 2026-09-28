import 'dart:math';

import 'package:http/http.dart' as http;

import 'api/api.dart';
import 'client.dart';
import 'config.dart';
import 'exceptions.dart';
import 'log.dart';
import 'session.dart';
import 'token_store.dart';
import 'transport/transport.dart';

/// Process-wide entry point: `Kletso.init(config)` once, then
/// `Kletso.instance` everywhere. A thin wrapper over [KletsoClient]; create
/// clients directly for tests or multi-tenant hosts.
abstract final class Kletso {
  static KletsoClient? _instance;

  /// Creates the shared client. Calling it again disposes the previous one.
  static Future<KletsoClient> init(
    KletsoConfig config, {
    KletsoApi? api,
    KletsoTransport? transport,
    http.Client? httpClient,
    Random? random,
    KletsoLogger? logger,
    KletsoDevice? device,
    KletsoTokenStore? tokenStore,
  }) async {
    await _instance?.dispose();
    return _instance = KletsoClient(
      config,
      api: api,
      transport: transport,
      httpClient: httpClient,
      random: random,
      logger: logger,
      device: device,
      tokenStore: tokenStore,
    );
  }

  /// The shared client. Throws [KletsoStateException] before [init].
  static KletsoClient get instance {
    final client = _instance;
    if (client == null) {
      throw const KletsoStateException('Kletso.init() has not been called');
    }
    return client;
  }

  /// Whether [init] has been called.
  static bool get isInitialized => _instance != null;

  /// Disposes the shared client (tests, hot restart).
  static Future<void> reset() async {
    await _instance?.dispose();
    _instance = null;
  }
}
