import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

void main() {
  group('rendering fixtures', () {
    for (final path in KletsoFixtures.validSurfaces) {
      testWidgets('$path renders without exceptions', (tester) async {
        final registry = KletsoComponentRegistry()
          ..register(
            'acme.productCard',
            (ctx, node) => Text('product ${node.string('name')}'),
          );
        await pumpSurface(tester, fixture(path), registry: registry);
        expect(tester.takeException(), isNull);
        expect(find.byType(KletsoFallback), findsNothing, reason: path);
      });
    }

    testWidgets('flight card shows resolved bindings and badge', (
      tester,
    ) async {
      await pumpSurface(tester, fixture('ui/valid/flight_card.json'));
      expect(find.text('Tokyo → Osaka'), findsOneWidget);
      expect(find.text('¥14,800'), findsOneWidget);
      expect(find.text('HND'), findsOneWidget);
      expect(find.text('On time'), findsOneWidget);
      expect(
        find.widgetWithText(KletsoButton, 'Select flight'),
        findsOneWidget,
      );
    });

    testWidgets('catalog_all renders every built-in without fallback', (
      tester,
    ) async {
      await pumpSurface(tester, fixture('ui/valid/catalog_all.json'));
      expect(find.text('Order ORD-4521'), findsOneWidget);
      expect(find.text('Shipped'), findsOneWidget);
      expect(find.text('Trail Runner 2'), findsWidgets);
      expect(find.text('Shipment timeline'), findsOneWidget);
      expect(find.text('Out for delivery'), findsOneWidget);
      expect(find.text('Carrier API timed out'), findsOneWidget);
      expect(find.text('Carrier tracking page'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(KletsoFallback), findsNothing);
    });
  });

  group('precedence and fallback', () {
    testWidgets(
      'host builder beats built-in; unknown type renders fallback text',
      (tester) async {
        final registry = KletsoComponentRegistry()
          ..register(
            'text',
            (ctx, node) => Text('HOST:${node.string('text')}'),
          );
        final surface = fixture('ui/invalid/unknown_type.json');
        await pumpSurface(tester, surface, registry: registry);
        expect(find.text('HOST:This part renders.'), findsOneWidget);
        expect(find.byType(KletsoFallback), findsOneWidget);
        expect(find.text(surface.fallbackText), findsOneWidget);
      },
    );

    testWidgets(
      'registered custom type renders the host widget with typed props and actions',
      (tester) async {
        final log = ActionLog();
        final registry = KletsoComponentRegistry()
          ..registerSpec(
            const KletsoComponentSpec(
              type: 'acme.productCard',
              description: 'x',
              props: {},
            ),
            (ctx, node) => TextButton(
              onPressed: () => ctx.executeAction('view'),
              child: Text(
                '${node.string('name')} ${node.number('price')} ${node.boolean('inStock')}',
              ),
            ),
          );
        await pumpSurface(
          tester,
          fixture('ui/valid/product_cards.json'),
          registry: registry,
          dispatcher: log.dispatcher(),
        );
        expect(find.text('Trail Runner 2 1899 true'), findsOneWidget);
        expect(find.text('Steel Bottle 750 999 false'), findsOneWidget);
        await tester.tap(find.text('Trail Runner 2 1899 true'));
        await tester.pump();
        expect(log.fired, [('p1', 'local', 'view')]);
        expect(registry.specs.keys, ['acme.productCard']);
        registry.unregister('acme.productCard');
        expect(registry.contains('acme.productCard'), isFalse);
      },
    );

    testWidgets('dangling child, cycle and depth limit degrade to fallback', (
      tester,
    ) async {
      await pumpSurface(tester, fixture('ui/invalid/dangling_child.json'));
      expect(find.text('I exist.'), findsOneWidget);
      expect(find.byType(KletsoFallback), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpSurface(tester, fixture('ui/invalid/cycle.json'));
      expect(find.byType(KletsoFallback), findsOneWidget);
      expect(tester.takeException(), isNull);

      final deep = KletsoSurface.fromJson(
        KletsoFixtureGenerators.depthOverflow(),
      );
      await pumpSurface(tester, deep);
      expect(find.byType(KletsoFallback), findsOneWidget);
      expect(find.text('leaf at depth 17'), findsNothing);

      final ok = KletsoSurface.fromJson(
        KletsoFixtureGenerators.depthOverflow(depth: 16),
      );
      await pumpSurface(tester, ok);
      expect(find.text('leaf at depth 16'), findsOneWidget);

      final many = KletsoSurface.fromJson(
        KletsoFixtureGenerators.tooManyComponents(),
      );
      await pumpSurface(tester, many);
      expect(find.byType(KletsoFallback), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets(
      'each action kind reaches the dispatcher; url honours the allowlist',
      (tester) async {
        final log = ActionLog();
        var localArgs = <String, Object?>{};
        final actions = KletsoActionRegistry()
          ..register('open_hotel', (args, ctx) {
            localArgs = args;
            expect(ctx.node!.id, 'b1');
            expect(ctx.origin, KletsoActionOrigin.surface);
            expect(ctx.client, isNull);
          });
        final policy = const KletsoUrlPolicy(allowedHosts: ['acme.com']);
        await pumpSurface(
          tester,
          fixture('ui/valid/hotel_card.json'),
          dispatcher: log.dispatcher(actions: actions, policy: policy),
        );
        await tester.tap(find.widgetWithText(KletsoButton, 'View details'));
        await tester.pump();
        expect(localArgs, {'id': 'h_1'});
        await tester.tap(find.widgetWithText(KletsoButton, 'Book'));
        await tester.pump();
        expect(log.fired.map((f) => f.$2), ['local', 'agent']);

        // url action on the flight card: acme.com allowed
        await pumpSurface(
          tester,
          fixture('ui/valid/flight_card.json'),
          dispatcher: log.dispatcher(policy: policy),
        );
        await tester.tap(find.widgetWithText(KletsoButton, 'Details'));
        await tester.pump();
        expect(log.opened.single.toString(), 'https://acme.com/flights/NH873');

        // blocked host: nothing opens
        await pumpSurface(
          tester,
          fixture('ui/valid/flight_card.json'),
          dispatcher: log.dispatcher(
            policy: const KletsoUrlPolicy(allowedHosts: ['other.com']),
          ),
        );
        await tester.tap(find.widgetWithText(KletsoButton, 'Details'));
        await tester.pump();
        expect(log.opened, hasLength(1));
        expect(actions.names, ['open_hotel']);
      },
    );

    testWidgets(
      'confirm block fires approve/deny; list items fire their own action',
      (tester) async {
        final log = ActionLog();
        await pumpSurface(
          tester,
          fixture('ui/valid/confirm.json'),
          dispatcher: log.dispatcher(),
        );
        await tester.tap(find.text('Keep order'));
        await tester.tap(find.text('Yes, cancel order'));
        await tester.pump();
        expect(log.fired.map((f) => f.$3), ['no', 'yes']);

        await pumpSurface(
          tester,
          fixture('ui/valid/catalog_all.json'),
          dispatcher: log.dispatcher(),
        );
        await tester.tap(find.text('Trail Runner 2').first);
        await tester.pump();
        expect(log.fired.last, ('list', 'local', 'open'));
        // workflow button and destructive agent button
        await tester.tap(find.text('Reschedule delivery'));
        await tester.tap(find.text('Report a problem'));
        await tester.pump();
        expect(
          log.fired.map((f) => f.$2).toList().sublist(log.fired.length - 2),
          ['workflow', 'agent'],
        );
        // link opens through the policy
        await tester.tap(find.text('Carrier tracking page'));
        await tester.pump();
        expect(log.opened.single.host, 'track.carrier.example');
      },
    );

    testWidgets('button without actions is disabled', (tester) async {
      final log = ActionLog();
      await pumpSurface(
        tester,
        fixture('ui/invalid/button_without_action.json'),
        dispatcher: log.dispatcher(),
      );
      await tester.tap(find.text('Does nothing'));
      await tester.pump();
      expect(log.fired, isEmpty);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    });
  });

  group('form', () {
    testWidgets('validates required/email/number and submits values', (
      tester,
    ) async {
      final log = ActionLog();
      final values = log.args;
      tallViewport(tester);
      await tester.pumpWidget(
        harness(
          KletsoSurfaceView(
            surface: fixture('ui/valid/form.json'),
            dispatcher: log.dispatcher(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Request callback'));
      await tester.pump();
      expect(
        find.text('Required'),
        findsNWidgets(3),
        reason: 'name, email, topic',
      );
      expect(values, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Ada',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'not-an-email',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'People on the call'),
        '9',
      );
      await tester.tap(find.text('Request callback'));
      await tester.pump();
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Maximum 5'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ada@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'People on the call'),
        '2',
      );
      await tester.tap(find.byType(DropdownButtonFormField<Object?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Billing').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Request callback'));
      await tester.pump();
      expect(values, hasLength(1));
      expect(values.single['name'], 'Ada');
      expect(values.single['email'], 'ada@example.com');
      expect(values.single['topic'], 'billing');
      expect(values.single['guests'], 2);
      expect(values.single['urgent'], isTrue);
      expect(log.fired.single.$2, 'submit');
    });

    testWidgets('input and select blocks submit through the node action', (
      tester,
    ) async {
      final log = ActionLog();
      final values = log.args;
      final surface = KletsoSurface.fromJson({
        'schema': 'kletso.ui/v1',
        'surfaceId': 'sfc_t',
        'root': 'col',
        'components': {
          'col': {
            'type': 'column',
            'props': {
              'children': ['otp', 'slot'],
            },
          },
          'otp': {
            'type': 'input',
            'props': {'name': 'otp', 'kind': 'number', 'label': 'OTP'},
            'actions': [
              {
                'id': 'go',
                'kind': 'agent',
                'value': {'intent': 'otp'},
              },
            ],
          },
          'slot': {
            'type': 'select',
            'props': {
              'name': 'slot',
              'label': 'Slot',
              'options': [
                {'value': 'am', 'label': 'Morning'},
              ],
              'multiple': true,
            },
            'actions': [
              {
                'id': 'go',
                'kind': 'agent',
                'value': {'intent': 'slot'},
              },
            ],
          },
        },
        'fallbackText': 'x',
      });
      tallViewport(tester);
      await tester.pumpWidget(
        harness(
          KletsoSurfaceView(surface: surface, dispatcher: log.dispatcher()),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(values.single['otp'], 123456);
      await tester.tap(find.text('Morning'));
      await tester.pump();
      await tester.tap(find.widgetWithText(KletsoButton, 'Send').last);
      await tester.pump();
      expect(values.last['slot'], ['am']);
    });
  });
}
