// Android-only proof that a `system` notification reaches the OS tray
// through the app's flutter_local_notifications wiring:
//   flutter test integration_test/system_tray_test.dart -d <device>
//   adb shell dumpsys notification --noredact | grep -A3 'ai.kletso.acme_shop'
import 'package:acme_shop/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('order_shipped → system channel → OS tray', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    final outcomes = <KletsoNotificationOutcome>[];
    Kletso.instance.ui.notificationResults.listen(
      (r) => outcomes.add(r.outcome),
    );
    Kletso.instance.track('order_shipped', <String, Object?>{
      'orderId': 'ORD-TRAY',
    });
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (outcomes.isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(outcomes, isNotEmpty);
    if (kIsWeb) {
      // headless Chrome has no notification permission: banner fallback
      expect(outcomes.first, KletsoNotificationOutcome.bannerFallback);
    } else {
      expect(outcomes.first, KletsoNotificationOutcome.system);
    }
    // leave the notification in the tray for `adb shell dumpsys notification`
    await tester.pump(const Duration(seconds: 2));
  });
}
