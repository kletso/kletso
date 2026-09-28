import 'package:flutter/foundation.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

/// Demo switches: identity, fake-backend scenario, presentation, theme.
/// Applying re-creates the Kletso client (as a real app would on login).
final class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  bool signedIn = false;
  bool brandedTheme = false;
  bool darkMode = false;
  bool seedHistory = false;
  bool dropSockets = false;
  bool expireToken = false;
  bool duplicates = false;
  bool slowNetwork = false;
  bool sampleMedia = true;
  bool systemTray = true;

  /// Talk to a real Kletso runtime instead of the in-process fake.
  /// `--dart-define=LIVE_API=https://api.kletso.ai --dart-define=LIVE_KEY=kl_pub_...`
  /// starts the app on a real runtime (used for live testing in a browser).
  static const String _liveApiDefine = String.fromEnvironment('LIVE_API');
  static const String _liveKeyDefine = String.fromEnvironment('LIVE_KEY');
  bool liveApi = _liveApiDefine.isNotEmpty;
  String apiBase = _liveApiDefine.isEmpty
      ? 'http://127.0.0.1:8788'
      : _liveApiDefine;
  String publishableKey = _liveKeyDefine.isEmpty
      ? 'kl_pub_dev_acme_demo_000000000000000000000000'
      : _liveKeyDefine;
  KletsoPresentation presentation = KletsoPresentation.sheet;
  KletsoFakeBackend? backend;
  String status = 'starting…';

  KletsoFakeScenario get scenario => KletsoFakeScenario.demo(
    seedConversationLog: seedHistory,
    dropSocketAfterEvents: dropSockets ? 6 : null,
    expireTokenAfterEvents: expireToken ? 4 : null,
    duplicateEveryNth: duplicates ? 3 : null,
    sampleMedia: sampleMedia,
  );

  Future<void> apply() async {
    final b = liveApi ? null : KletsoFakeBackend(scenario: scenario);
    backend = b;
    final client = await Kletso.init(
      KletsoConfig(
        publishableKey: liveApi ? publishableKey : 'kl_pub_demo_acme',
        agentId: KletsoFakeBackend.agentId,
        environment: KletsoEnvironment.development,
        baseUrl: liveApi ? Uri.parse(apiBase) : null,
        logLevel: kDebugMode ? KletsoLogLevel.info : KletsoLogLevel.warning,
        heartbeatInterval: slowNetwork
            ? const Duration(seconds: 5)
            : const Duration(seconds: 25),
        allowServerCommands: true,
      ),
      api: b,
      transport: b,
      device: const KletsoDevice(
        platform: kIsWeb ? 'web' : 'android',
        sdk: 'acme_shop',
      ),
    );
    try {
      if (signedIn) {
        await client.authenticate(
          token: 'eyJhbGciOiJIUzI1NiJ9.demo-user-ada',
          onTokenExpired: () async =>
              'eyJhbGciOiJIUzI1NiJ9.demo-user-ada-refreshed',
        );
        status = liveApi ? 'signed in as Ada · live API' : 'signed in as Ada';
      } else {
        await client.identifyAnonymous();
        status = liveApi
            ? 'anonymous visitor · live API $apiBase'
            : 'anonymous visitor';
      }
      client.setContext(<String, Object?>{
        'plan': signedIn ? 'pro' : 'free',
        'cartValue': 0,
      });
      // A real app passes the token from firebase_messaging / Web Push.
      await client.registerPushToken(
        KletsoPushToken(
          platform: kIsWeb
              ? KletsoPushPlatform.webPush
              : KletsoPushPlatform.fcm,
          token: 'demo-device-token-${signedIn ? 'ada' : 'visitor'}',
        ),
      );
    } on KletsoException catch (e) {
      status = 'error: ${e.message}';
    }
    notifyListeners();
  }

  void update(void Function() change) {
    change();
    notifyListeners();
  }
}
