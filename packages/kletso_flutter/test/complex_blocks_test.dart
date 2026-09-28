import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

void main() {
  testWidgets(
    'media hub renders map, countdown, video, audio and interactive rating',
    (tester) async {
      final log = ActionLog();
      await pumpSurface(
        tester,
        fixture('ui/valid/media_hub.json'),
        dispatcher: log.dispatcher(),
      );
      expect(find.byType(KletsoFallback), findsNothing);
      expect(find.text('Courier location'), findsOneWidget);
      expect(find.text('Courier'), findsOneWidget);
      expect(find.text('How to set up your Trail Runner 2'), findsOneWidget);
      expect(find.text('1:34'), findsOneWidget);
      expect(find.text('Care tips (2 min)'), findsOneWidget);
      expect(find.text('2:02'), findsOneWidget);
      expect(find.byType(KletsoCountdown), findsOneWidget);
      expect(
        find.text('Arriving now'),
        findsOneWidget,
        reason: 'fixture endsAt is in the past',
      );
      // map marker action + open in maps
      final markerPins = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.place && w.size == 28,
      );
      expect(markerPins, findsNWidgets(3));
      await tester.tap(markerPins.at(1)); // 'You' carries the url action
      await tester.tap(find.widgetWithText(KletsoButton, 'Open in Maps'));
      await tester.pump();
      expect(log.opened.map((u) => u.host).toSet(), {'maps.google.com'});
      expect(log.opened, hasLength(2));
      // video play + audio play open the sources through the policy
      final plays = find.byIcon(Icons.play_arrow_rounded);
      expect(plays, findsNWidgets(2));
      await tester.tap(plays.first); // video
      await tester.tap(plays.last); // audio
      await tester.pump();
      expect(log.opened.last.path, '/help/care-tips.mp3');
      // interactive rating fires the agent action with the star count
      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
      await tester.pump();
      expect(log.fired.last, ('rating', 'agent', 'rate'));
      expect(log.args.last, {'rating': 4});
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      await tester.pump(
        const Duration(seconds: 2),
      ); // countdown ticks are harmless
    },
  );

  testWidgets(
    'trip plan: tabs switch children, accordion expands, steps and progress render',
    (tester) async {
      final log = ActionLog();
      await pumpSurface(
        tester,
        fixture('ui/valid/trip_plan.json'),
        dispatcher: log.dispatcher(),
      );
      expect(find.byType(KletsoFallback), findsNothing);
      expect(
        find.text('2 of 4 steps done'),
        findsOneWidget,
        reason: 'binding resolved',
      );
      expect(find.text('Flight selected'), findsOneWidget);
      expect(
        find.text('Baggage allowance'),
        findsNothing,
        reason: 'other tab hidden',
      );
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(find.text('Baggage allowance'), findsOneWidget);
      expect(
        find.textContaining('23 kg'),
        findsOneWidget,
        reason: 'expanded by default',
      );
      expect(find.text('From 15:00. Early check-in on request.'), findsNothing);
      await tester.tap(find.text('Hotel check-in'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('From 15:00. Early check-in on request.'),
        findsOneWidget,
        reason: 'child component inside accordion',
      );
      await tester.tap(find.text('Baggage allowance'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('23 kg'), findsNothing);
      await tester.tap(find.text('Feedback'));
      await tester.pump();
      expect(find.text('4.0'), findsOneWidget);
      expect(find.text(' (128)'), findsOneWidget);
      await tester.tap(find.text('Change hotel'));
      await tester.pump();
      expect(log.fired.single, ('rateBtn', 'agent', 'change'));
    },
  );

  testWidgets('countdown ticks with an injected clock and disposes its timer', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 28, 12);
    await tester.pumpWidget(
      harness(
        KletsoCountdown(
          endsAt: DateTime.utc(2026, 9, 28, 12, 0, 5),
          label: 'Ends in',
          now: () => now,
        ),
      ),
    );
    expect(find.text('05'), findsOneWidget);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('02'), findsOneWidget);
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Time is up'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('host override for map/video wins over the built-ins', (
    tester,
  ) async {
    final registry = KletsoComponentRegistry()
      ..register(
        'map',
        (ctx, node) =>
            Text('HOST MAP ${node.mapList('markers').length} markers'),
      )
      ..register(
        'video',
        (ctx, node) => Text('HOST VIDEO ${node.string('src')}'),
      );
    await pumpSurface(
      tester,
      fixture('ui/valid/media_hub.json'),
      registry: registry,
    );
    expect(find.text('HOST MAP 3 markers'), findsOneWidget);
    expect(
      find.text('HOST VIDEO https://cdn.acme.com/help/unboxing.mp4'),
      findsOneWidget,
    );
    expect(find.text('Courier location'), findsNothing);
  });

  test('duration formatting', () {
    expect(KletsoFormat.duration(94), '1:34');
    expect(KletsoFormat.duration(5), '0:05');
    expect(KletsoFormat.duration(3725), '1:02:05');
  });
}
