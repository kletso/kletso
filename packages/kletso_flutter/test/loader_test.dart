// Component loaders (D88): per-type loaders in the registry, the `loading`
// block with `for`/`count`, and the bot bubble showing placeholders for a
// surface that is still streaming until its ui.render arrives.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

KletsoSurface _loadingSurface({required String forType, int count = 2}) =>
    KletsoSurface.fromJson(<String, Object?>{
      'schema': 'kletso.ui/v1',
      'surfaceId': 'sfc_loading',
      'root': 'l',
      'fallbackText': 'Loading',
      'components': <String, Object?>{
        'l': <String, Object?>{
          'type': 'loading',
          'props': <String, Object?>{'for': forType, 'count': count},
        },
      },
    });

void main() {
  testWidgets('loading block with `for` uses the registered loader, else the '
      'generic shimmer', (tester) async {
    final registry = KletsoComponentRegistry()
      ..registerLoader(
        'ds.eventCard',
        (ctx) => SizedBox(
          key: ValueKey<String>('ev_${ctx.index}'),
          height: 40,
          child: Text('loading ${ctx.type}'),
        ),
      );
    await pumpSurface(
      tester,
      _loadingSurface(forType: 'ds.eventCard', count: 3),
      registry: registry,
    );
    expect(find.text('loading ds.eventCard'), findsNWidgets(3));
    expect(find.byKey(const ValueKey<String>('ev_2')), findsOneWidget);
    expect(find.byType(KletsoShimmer), findsNothing);

    await pumpSurface(tester, _loadingSurface(forType: 'ds.other'));
    expect(find.byType(KletsoShimmer), findsNWidgets(2));
  });

  testWidgets('bot bubble shows loaders for a pending surface and swaps in '
      'the rendered one', (tester) async {
    const pending = KletsoUiPending(
      toolCallId: 'toolu_1',
      surfaceId: 'sfc_pending01',
      components: <KletsoPendingComponent>[
        KletsoPendingComponent(id: 'col', type: 'column'),
        KletsoPendingComponent(id: 'a', type: 'card'),
        KletsoPendingComponent(id: 'b', type: 'card'),
      ],
    );
    final streaming = KletsoMessage(
      id: 'm1',
      role: KletsoRole.assistant,
      createdAt: DateTime(2026),
      text: 'Two events tonight:',
      status: KletsoMessageStatus.streaming,
      pending: const <KletsoUiPending>[pending],
    );
    Widget bubble(KletsoMessage m) => harness(
      KletsoBotBubble(
        message: m,
        markdownRenderer: const KletsoPlainMarkdownRenderer(),
      ),
    );
    await tester.pumpWidget(bubble(streaming));
    await tester.pump();
    expect(find.text('Two events tonight:'), findsOneWidget);
    expect(find.byType(KletsoPendingSurfaceView), findsOneWidget);
    // one loader per non-layout component: the column gets none
    expect(find.byType(KletsoShimmer), findsNWidgets(2));
    expect(find.byType(KletsoTypingDots), findsNothing);

    final rendered = streaming.copyWith(
      surfaces: <KletsoSurface>[fixture('ui/valid/quick_replies.json')],
      pending: const <KletsoUiPending>[],
    );
    await tester.pumpWidget(bubble(rendered));
    await tester.pump();
    expect(find.byType(KletsoPendingSurfaceView), findsNothing);
    expect(find.byType(KletsoSurfaceView), findsOneWidget);
  });

  testWidgets('a pending surface with no components yet shows one generic '
      'loader', (tester) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => KletsoPendingSurfaceView(
            pending: const KletsoUiPending(toolCallId: 'toolu_2'),
            theme: KletsoTheme.of(context),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(KletsoShimmer), findsOneWidget);
  });
}
