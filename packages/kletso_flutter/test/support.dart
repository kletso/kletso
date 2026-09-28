import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

/// Wraps [child] in a MaterialApp with the Kletso theme registered.
Widget harness(Widget child, {KletsoTheme? theme}) => MaterialApp(
  theme: (theme ?? KletsoTheme.light(useHostFont: true)).materialTheme(
    ThemeData.light(),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(8), child: child),
    ),
  ),
);

/// Records every action fired on a surface.
final class ActionLog {
  final List<(String node, String kind, String id)> fired =
      <(String, String, String)>[];
  final List<Uri> opened = <Uri>[];
  final List<Map<String, Object?>> args = <Map<String, Object?>>[];

  KletsoActionDispatcher dispatcher({
    KletsoActionRegistry? actions,
    KletsoUrlPolicy policy = KletsoUrlPolicy.permissive,
  }) => KletsoActionDispatcher(
    actions: actions ?? KletsoActionRegistry(),
    urlPolicy: policy,
    onOpenUrl: (uri) async => opened.add(uri),
    observer: (surface, node, action, a) {
      fired.add((node.id, action.kind, action.id));
      args.add(a);
    },
  );
}

KletsoSurface fixture(String path) =>
    KletsoSurface.fromJson(KletsoFixtures.json(path));

/// A tall test viewport so nothing scrolls out of reach of `tester.tap`.
void tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> pumpSurface(
  WidgetTester tester,
  KletsoSurface surface, {
  KletsoComponentRegistry? registry,
  KletsoActionDispatcher? dispatcher,
  KletsoUiLimits limits = KletsoUiLimits.standard,
}) async {
  tallViewport(tester);
  await tester.pumpWidget(
    harness(
      KletsoSurfaceView(
        surface: surface,
        registry: registry,
        dispatcher: dispatcher,
        limits: limits,
      ),
    ),
  );
  await tester.pump();
}
