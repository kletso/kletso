import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

void main() {
  testWidgets(
    '/host bindings read client.ui.hostData and rebuild when it changes',
    (tester) async {
      final backend = KletsoFakeBackend();
      final client = KletsoClient(
        KletsoConfig(
          publishableKey: 'kl_pub_test',
          agentId: KletsoFakeBackend.agentId,
          logLevel: KletsoLogLevel.none,
        ),
        api: backend,
        transport: backend,
      );
      final surface = KletsoSurface.fromJson({
        'schema': 'kletso.ui/v1',
        'surfaceId': 'sfc_h',
        'root': 'p',
        'components': {
          'p': {
            'type': 'progress',
            'props': {
              'value': {'path': '/host/cart/progress'},
              'label': 'Cart',
              'detail': {'path': '/host/cart/label'},
            },
          },
        },
        'data': {
          'host': {
            'cart': {'progress': 0.0, 'label': 'Add items'},
          },
        },
        'fallbackText': 'cart',
      });
      tallViewport(tester);
      await tester.pumpWidget(
        harness(KletsoSurfaceView(surface: surface, client: client)),
      );
      await tester.pump();
      expect(
        find.text('Add items'),
        findsOneWidget,
        reason: 'surface default when the host has nothing',
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.0,
      );
      client.setHostData({
        'cart': {'progress': 0.8, 'label': '₹400 to go'},
      });
      await tester.pump();
      expect(find.text('₹400 to go'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(0.8, 1e-9),
      );
      client.updateHostData({
        'cart': {'progress': 1.0, 'label': 'Free shipping unlocked'},
      });
      await tester.pump();
      expect(find.text('Free shipping unlocked'), findsOneWidget);
      await tester.pumpWidget(
        harness(
          KletsoSurfaceView(
            surface: surface,
            client: client,
            bindingResolver: (b) => b.path.endsWith('label') ? 'custom' : 0.5,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('custom'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );
}
