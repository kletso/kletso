import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

void main() {
  group('KletsoTheme', () {
    test('light theme comes from the tokens', () {
      final t = KletsoTheme.light();
      expect(t.primary, KletsoTokens.dutchOrange);
      expect(t.background, KletsoTokens.cream);
      expect(t.text, KletsoTokens.deepNavy);
      expect(t.radiusLg, KletsoTokens.radiusLg);
      expect(t.body.fontFamily, contains('Plus Jakarta Sans'));
      expect(KletsoTheme.light(useHostFont: true).body.fontFamily, isNull);
      expect(KletsoTheme.dark(), isNot(equals(KletsoTheme.light())));
      expect(KletsoTheme.dark().isDark, isTrue);
      expect(KletsoTheme.light().isDark, isFalse);
      expect(
        KletsoTheme.dark().primary,
        KletsoTheme.light().primary,
        reason: 'same orange',
      );
      expect(
        KletsoTheme.dark().materialTheme(ThemeData.dark()).brightness,
        Brightness.dark,
      );
      expect(KletsoTheme.forBrightness(Brightness.dark), KletsoTheme.dark());
      expect(t.colorScheme.primary, t.primary);
    });

    test('lerp touches every field and copyWith round-trips', () {
      final a = KletsoTheme.light();
      final b = a.copyWith(
        primary: const Color(0xFF000000),
        onPrimary: const Color(0xFF111111),
        primaryHover: const Color(0xFF222222),
        primarySoft: const Color(0xFF333333),
        surface: const Color(0xFF444444),
        background: const Color(0xFF555555),
        text: const Color(0xFF666666),
        textMuted: const Color(0xFF777777),
        line: const Color(0xFF888888),
        bubbleUser: const Color(0xFF999999),
        bubbleBot: const Color(0xFFAAAAAA),
        success: const Color(0xFFBBBBBB),
        warning: const Color(0xFFCCCCCC),
        error: const Color(0xFFDDDDDD),
        info: const Color(0xFFEEEEEE),
        infoSoft: const Color(0xFF010101),
        successSoft: const Color(0xFF020202),
        warningSoft: const Color(0xFF030303),
        errorSoft: const Color(0xFF040404),
        radiusSm: 1,
        radiusMd: 2,
        radiusLg: 3,
        radiusPill: 4,
        fontFamily: 'Other',
        title: const TextStyle(fontSize: 40),
        subtitle: const TextStyle(fontSize: 30),
        body: const TextStyle(fontSize: 20),
        caption: const TextStyle(fontSize: 10),
        code: const TextStyle(fontSize: 11),
        launcherPosition: KletsoLauncherPosition.bottomLeft,
        launcherSize: 80,
        useHostFont: true,
      );
      expect(b, isNot(equals(a)));
      final mid = a.lerp(b, 0.5);
      expect(mid.primary, Color.lerp(a.primary, b.primary, 0.5));
      expect(mid.errorSoft, Color.lerp(a.errorSoft, b.errorSoft, 0.5));
      expect(mid.radiusLg, (a.radiusLg + 3) / 2);
      expect(mid.launcherSize, (56 + 80) / 2);
      expect(mid.title.fontSize, (18 + 40) / 2);
      expect(mid.fontFamily, b.fontFamily, reason: 't >= 0.5 takes other');
      expect(a.lerp(b, 0).primary, a.primary);
      expect(a.lerp(b, 1).primary, b.primary);
      expect(a.lerp(b, 1).launcherPosition, b.launcherPosition);
      expect(a.lerp(null, 0.5), a);
      expect(a.copyWith(), a);
      expect(a.copyWith().hashCode, a.hashCode);
    });

    test('fromServer applies branding and ignores garbage', () {
      final t = KletsoTheme.fromServer({
        'primary': '#112233',
        'onPrimary': 'FFFFFF',
        'text': '#000000',
        'radius': 8,
        'fontFamily': 'Inter',
        'launcher': {'position': 'bottomLeft'},
        'surface': 'not a colour',
        'background': 12,
      });
      expect(t.primary, const Color(0xFF112233));
      expect(t.onPrimary, const Color(0xFFFFFFFF));
      expect(t.text, const Color(0xFF000000));
      expect(t.body.color, const Color(0xFF000000));
      expect(t.radiusLg, 8);
      expect(t.radiusMd, 6);
      expect(t.radiusSm, 4);
      expect(t.fontFamily, 'Inter');
      expect(t.launcherPosition, KletsoLauncherPosition.bottomLeft);
      expect(t.surface, KletsoTheme.light().surface);
      expect(t.background, KletsoTheme.light().background);
      expect(KletsoTheme.fromServer(const {}), KletsoTheme.light());
    });

    testWidgets(
      'of() follows the ambient brightness when the host registered nothing',
      (tester) async {
        late KletsoTheme seen;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                seen = KletsoTheme.of(c);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(seen, KletsoTheme.light());
        await tester.pumpWidget(
          MaterialApp(
            key: const Key('dark'),
            theme: ThemeData.dark(),
            home: Builder(
              builder: (c) {
                seen = KletsoTheme.of(c);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pump();
        expect(
          seen.isDark,
          isTrue,
          reason: 'ambient brightness dark → dark theme',
        );
        expect(seen, KletsoTheme.dark());
      },
    );

    test('generated tokens are current', () {
      // The design tokens live in the Kletso monorepo (packages/design). In a
      // packages-only checkout (github.com/kletso/kletso) there is nothing to
      // compare against, so the check is skipped there.
      if (!File('../design/tokens.json').existsSync()) {
        markTestSkipped('packages/design/tokens.json not in this checkout');
        return;
      }
      final result = Process.runSync('dart', [
        'run',
        'tool/gen_tokens.dart',
        '--check',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });
  });

  group('KletsoPlainMarkdownRenderer', () {
    Future<void> pump(
      WidgetTester tester,
      String md, {
      void Function(String)? onLink,
    }) => tester.pumpWidget(
      harness(
        Builder(
          builder: (c) => const KletsoPlainMarkdownRenderer().build(
            c,
            KletsoMarkdownRequest(
              markdown: md,
              theme: KletsoTheme.of(c),
              onLinkTap: onLink ?? (_) {},
            ),
          ),
        ),
      ),
    );

    testWidgets('renders blocks and inline styles, links tap through', (
      tester,
    ) async {
      String? tapped;
      await pump(
        tester,
        '# Title\n\nSome **bold** and *it* and `code`.\n\n- one\n- two\n\n1. first\n2. second\n\n> quoted\n\n---\n\n```\nlet x = 1;\n```\n\nA [link](https://acme.com/x) and <b>html</b>.',
        onLink: (u) => tapped = u,
      );
      expect(find.textContaining('Title'), findsOneWidget);
      expect(find.textContaining('quoted'), findsOneWidget);
      expect(find.text('let x = 1;'), findsOneWidget);
      expect(
        find.textContaining('<b>html</b>'),
        findsOneWidget,
        reason: 'HTML is shown as text',
      );
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      final rich = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.textSpan?.toPlainText().contains('link') ?? false)
          .single;
      final span = rich.textSpan! as TextSpan;
      TextSpan? linkSpan;
      span.visitChildren((s) {
        if (s is TextSpan && s.text == 'link') linkSpan = s;
        return true;
      });
      expect(linkSpan, isNotNull);
      (linkSpan!.recognizer! as TapGestureRecognizer).onTap!();
      expect(tapped, 'https://acme.com/x');
    });

    testWidgets(
      'unterminated fence while streaming does not throw; images need allowlist',
      (tester) async {
        await pump(tester, 'Working:\n\n```dart\nfinal a =');
        expect(find.text('final a ='), findsOneWidget);
        await pump(tester, '![alt text](https://cdn.acme.com/x.png)');
        expect(find.textContaining('alt text'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        await pump(tester, '');
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('KletsoUrlPolicy', () {
    test('https only, subdomains of allowed hosts', () {
      const p = KletsoUrlPolicy(allowedHosts: ['acme.com']);
      expect(p.allows(Uri.parse('https://acme.com/a')), isTrue);
      expect(p.allows(Uri.parse('https://cdn.acme.com/a')), isTrue);
      expect(p.allows(Uri.parse('https://notacme.com/a')), isFalse);
      expect(p.allows(Uri.parse('http://acme.com/a')), isFalse);
      expect(p.allows(Uri.parse('javascript:alert(1)')), isFalse);
      expect(p.allows(Uri.parse('data:text/html,hi')), isFalse);
      expect(p.allows(null), isFalse);
      expect(
        KletsoUrlPolicy.permissive.allows(
          Uri.parse('https://anything.example'),
        ),
        isTrue,
      );
      expect(
        KletsoUrlPolicy.permissive.allows(Uri.parse('file:///etc/passwd')),
        isFalse,
      );
      expect(p.check('https://acme.com')!.host, 'acme.com');
      expect(p.check('::'), isNull);
      expect(p.check(null), isNull);
    });
  });

  test('KletsoComponentSpec serialises for the manifest', () {
    const spec = KletsoComponentSpec(
      type: 'acme.productCard',
      description: 'Product tile',
      props: {
        'type': 'object',
        'properties': {
          'sku': {'type': 'string'},
        },
      },
      example: {'sku': 'SKU-1'},
      actions: ['view'],
    );
    expect(spec.toJson(), {
      'type': 'acme.productCard',
      'description': 'Product tile',
      'props': {
        'type': 'object',
        'properties': {
          'sku': {'type': 'string'},
        },
      },
      'example': {'sku': 'SKU-1'},
      'actions': ['view'],
      'version': 1,
    });
  });
}
