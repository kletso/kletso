import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'support.dart';

/// A [Timer] substitute that never actually waits: the test fires
/// [callback] itself by calling [fire].
final class _FakeTimer implements Timer {
  _FakeTimer(this.callback);

  final void Function() callback;
  bool _active = true;

  void fire() {
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  moodImageTests();
  group('KletsoAvatarMood', () {
    test('parse round-trips the wire values and falls back to unknown', () {
      for (final mood in KletsoAvatarMood.values) {
        expect(KletsoAvatarMood.parse(mood.wire), mood);
      }
      expect(KletsoAvatarMood.parse('nonsense'), KletsoAvatarMood.unknown);
      expect(KletsoAvatarMood.parse(null), KletsoAvatarMood.unknown);
    });
  });

  group('KletsoAvatarFaceParams', () {
    test('neutral and unknown both render the plain default face', () {
      final neutral = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.neutral);
      final unknown = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.unknown);
      expect(unknown, neutral);
      expect(neutral.mouthCurve, 0.35);
      expect(neutral.eyeShape, KletsoAvatarEyeShape.round);
    });

    test('happy overrides only the fields avatar.json lists', () {
      final happy = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.happy);
      expect(happy.mouthCurve, 0.8);
      expect(happy.mouthOpen, 0.7);
      expect(happy.tongue, 0.45);
      expect(happy.blush, 0.5);
      // Unspecified fields keep the default.
      expect(happy.eyeOpen, 1.0);
      expect(happy.headTilt, 0);
    });

    test('laughing closes the eyes as an arc and shows teeth', () {
      final laughing = KletsoAvatarFaceParams.forMood(
        KletsoAvatarMood.laughing,
      );
      expect(laughing.eyeShape, KletsoAvatarEyeShape.arc);
      expect(laughing.eyeOpen, 0.0);
      expect(laughing.teeth, 1.0);
      expect(laughing.bounce, 1.0);
    });

    test('wink only shuts the right eye', () {
      final wink = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.wink);
      expect(wink.winkRight, isTrue);
      expect(wink.eyeShape, KletsoAvatarEyeShape.round);
    });

    test('speaking marks mouthOpen as lip-sync driven', () {
      final speaking = KletsoAvatarFaceParams.forMood(
        KletsoAvatarMood.speaking,
      );
      expect(speaking.mouthIsLipsync, isTrue);
    });

    test('lerp interpolates numeric fields and steps discrete ones', () {
      final a = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.neutral);
      final b = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.happy);
      final mid = KletsoAvatarFaceParams.lerp(a, b, 0.5);
      expect(mid.mouthCurve, closeTo((a.mouthCurve + b.mouthCurve) / 2, 1e-9));
      expect(KletsoAvatarFaceParams.lerp(a, b, 0).mouthCurve, a.mouthCurve);
      expect(KletsoAvatarFaceParams.lerp(a, b, 1).mouthCurve, b.mouthCurve);
      final laughing = KletsoAvatarFaceParams.forMood(
        KletsoAvatarMood.laughing,
      );
      expect(
        KletsoAvatarFaceParams.lerp(a, laughing, 0.4).eyeShape,
        a.eyeShape,
        reason: 't < 0.5 keeps the first discrete value',
      );
      expect(
        KletsoAvatarFaceParams.lerp(a, laughing, 0.6).eyeShape,
        laughing.eyeShape,
      );
    });

    test('withMouthOpen replaces only mouthOpen', () {
      final base = KletsoAvatarFaceParams.forMood(KletsoAvatarMood.speaking);
      final resolved = base.withMouthOpen(0.42);
      expect(resolved.mouthOpen, 0.42);
      expect(resolved.mouthIsLipsync, base.mouthIsLipsync);
      expect(resolved.mouthWidth, base.mouthWidth);
    });
  });

  group('KletsoAvatarController', () {
    test('defaults to neutral and reflects an initial defaultMood', () {
      final c = KletsoAvatarController(defaultMood: KletsoAvatarMood.happy);
      expect(c.mood, KletsoAvatarMood.happy);
      c.dispose();
    });

    test('clamps a disallowed default mood to neutral', () {
      final c = KletsoAvatarController(
        defaultMood: KletsoAvatarMood.happy,
        allowedMoods: const {KletsoAvatarMood.neutral, KletsoAvatarMood.sorry},
      );
      expect(c.mood, KletsoAvatarMood.neutral);
      c.dispose();
    });

    test('setMood clamps a disallowed mood to defaultMood', () {
      final c = KletsoAvatarController(
        allowedMoods: const {KletsoAvatarMood.neutral, KletsoAvatarMood.sorry},
      );
      c.setMood(KletsoAvatarMood.happy);
      expect(c.mood, KletsoAvatarMood.neutral);
      c.setMood(KletsoAvatarMood.sorry);
      expect(c.mood, KletsoAvatarMood.sorry);
      c.dispose();
    });

    test('setMood notifies listeners and ttl reverts via a fake timer', () {
      Duration? capturedDuration;
      void Function()? capturedCallback;
      final c = KletsoAvatarController(
        createTimer: (duration, callback) {
          capturedDuration = duration;
          capturedCallback = callback;
          return _FakeTimer(callback);
        },
      );
      var notifications = 0;
      c.addListener(() => notifications++);

      c.setMood(KletsoAvatarMood.wink, ttl: const Duration(milliseconds: 1500));
      expect(c.mood, KletsoAvatarMood.wink);
      expect(notifications, 1);
      expect(capturedDuration, const Duration(milliseconds: 1500));

      capturedCallback!();
      expect(c.mood, KletsoAvatarMood.neutral);
      expect(notifications, 2);
      c.dispose();
    });

    test('a later setMood cancels the pending ttl timer', () {
      final timers = <_FakeTimer>[];
      final c = KletsoAvatarController(
        createTimer: (duration, callback) {
          final timer = _FakeTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      c.setMood(KletsoAvatarMood.wink, ttl: const Duration(seconds: 1));
      c.setMood(KletsoAvatarMood.happy);
      expect(c.mood, KletsoAvatarMood.happy);
      expect(
        timers.first.isActive,
        isFalse,
        reason: 'the first ttl timer was cancelled',
      );
      c.dispose();
    });

    test('applyRule uses the protocol default rule set', () {
      final c = KletsoAvatarController();
      c.applyRule('tool.failed');
      expect(c.mood, KletsoAvatarMood.sorry);
      c.applyRule('voice.idle');
      expect(c.mood, KletsoAvatarMood.neutral);
      c.applyRule('this.does.not.exist');
      expect(c.mood, KletsoAvatarMood.neutral, reason: 'no-op on no match');
      c.dispose();
    });

    test('applyRule prefers custom rules over the defaults', () {
      final c = KletsoAvatarController(
        rules: const [('custom.event', KletsoAvatarMood.confused, 0)],
      );
      c.applyRule('custom.event');
      expect(c.mood, KletsoAvatarMood.confused);
      // The default set is not consulted once a custom list is supplied.
      c.applyRule('tool.failed');
      expect(c.mood, KletsoAvatarMood.confused);
      c.dispose();
    });

    test('setLevel envelope: first sample jumps, later samples ease', () {
      var now = DateTime.utc(2026);
      final c = KletsoAvatarController(clock: () => now);

      // No prior sample: alpha == 1, level jumps straight to the target.
      c.setLevel(0.4); // target = clamp(0.4 * gain=2.5, 0, 1) = 1.0
      expect(c.level, 1.0);

      // A big drop right away (tiny dt) should ease only partway down.
      now = now.add(const Duration(milliseconds: 1));
      c.setLevel(0.0);
      expect(c.level, greaterThan(0.0));
      expect(c.level, lessThan(1.0));

      // After much longer than the release time, it settles at the target.
      now = now.add(const Duration(milliseconds: 500));
      c.setLevel(0.0);
      expect(c.level, 0.0);
      c.dispose();
    });

    test('setLevel clamps raw input outside 0..1', () {
      final c = KletsoAvatarController();
      c.setLevel(5);
      expect(c.level, 1.0);
      c.dispose();
    });

    test('dispose cancels a pending ttl timer', () {
      late _FakeTimer timer;
      final c = KletsoAvatarController(
        createTimer: (duration, callback) => timer = _FakeTimer(callback),
      );
      c.setMood(KletsoAvatarMood.wink, ttl: const Duration(seconds: 5));
      c.dispose();
      expect(timer.isActive, isFalse);
      // Dispose must not itself revert the mood or throw.
      expect(c.mood, KletsoAvatarMood.wink);
    });
  });

  group('KletsoAvatar widget', () {
    Widget harnessFor(Widget child, {bool reducedMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: harness(child),
    );

    KletsoAvatarPainter painterOf(WidgetTester tester) {
      final widget = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is KletsoAvatarPainter,
        ),
      );
      return widget.painter! as KletsoAvatarPainter;
    }

    testWidgets('renders the kletso style and finds the painter', (
      tester,
    ) async {
      await tester.pumpWidget(harnessFor(const KletsoAvatar(size: 64)));
      await tester.pump();
      expect(painterOf(tester).params.eyeShape, KletsoAvatarEyeShape.round);
    });

    testWidgets('renders the none style like the bubble dot', (tester) async {
      await tester.pumpWidget(
        harnessFor(const KletsoAvatar(style: KletsoAvatarStyle.none)),
      );
      await tester.pump();
      expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
    });

    testWidgets('renders the image style with a ClipOval', (tester) async {
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(style: KletsoAvatarStyle.image, imageProvider: _png1),
        ),
      );
      await tester.pump();
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('tweens to the new mood and settles on the target params', (
      tester,
    ) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        harnessFor(KletsoAvatar(controller: controller, size: 64)),
      );
      await tester.pump();
      expect(painterOf(tester).params.mouthCurve, 0.35);

      controller.setMood(KletsoAvatarMood.happy);
      await tester.pump(const Duration(milliseconds: 80)); // mid-tween.
      final mid = painterOf(tester).params.mouthCurve;
      expect(mid, greaterThan(0.35));
      expect(mid, lessThan(0.8));

      await tester.pump(const Duration(milliseconds: 250));
      expect(painterOf(tester).params.mouthCurve, 0.8);
    });

    testWidgets('reduced motion changes mood instantly with no idle motion', (
      tester,
    ) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(controller: controller, size: 64),
          reducedMotion: true,
        ),
      );
      await tester.pump();

      controller.setMood(KletsoAvatarMood.happy);
      await tester.pump();
      // No tween: the very next frame already shows the target mood.
      expect(painterOf(tester).params.mouthCurve, 0.8);
      expect(painterOf(tester).breathScale, 1.0);

      await tester.pump(const Duration(seconds: 2));
      expect(
        painterOf(tester).breathScale,
        1.0,
        reason: 'idle breathing stays off under reduced motion',
      );
    });

    testWidgets('animate: false never tweens or idles', (tester) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(controller: controller, size: 64, animate: false),
        ),
      );
      await tester.pump();
      controller.setMood(KletsoAvatarMood.laughing);
      await tester.pump();
      expect(painterOf(tester).params.eyeShape, KletsoAvatarEyeShape.arc);
      expect(painterOf(tester).breathScale, 1.0);
    });

    testWidgets('speaking mouth opening follows controller.level', (
      tester,
    ) async {
      final controller = KletsoAvatarController(
        defaultMood: KletsoAvatarMood.speaking,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(controller: controller, size: 64, animate: false),
        ),
      );
      await tester.pump();
      final closed = painterOf(tester).params.mouthOpen;

      controller.setLevel(0.4); // saturates the envelope to 1.0
      await tester.pump();
      final open = painterOf(tester).params.mouthOpen;
      expect(open, greaterThan(closed));
    });

    testWidgets('disposes its own controller but not a host-provided one', (
      tester,
    ) async {
      final hostController = KletsoAvatarController();
      addTearDown(hostController.dispose);
      await tester.pumpWidget(
        harnessFor(KletsoAvatar(controller: hostController)),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      // The host controller must still be usable (not disposed by the
      // widget); calling a method after the widget is gone must not throw.
      hostController.setMood(KletsoAvatarMood.happy);
      expect(hostController.mood, KletsoAvatarMood.happy);
    });
  });

  group('goldens', () {
    // One mood per reference art in apps/site/public/img/char-expr-*.png
    // (plus the moods that have no reference stills yet).
    const moods = <KletsoAvatarMood>[
      KletsoAvatarMood.neutral,
      KletsoAvatarMood.happy,
      KletsoAvatarMood.laughing,
      KletsoAvatarMood.surprised,
      KletsoAvatarMood.thinking,
      KletsoAvatarMood.wink,
      KletsoAvatarMood.listening,
      KletsoAvatarMood.speaking,
      KletsoAvatarMood.sorry,
      KletsoAvatarMood.confused,
      KletsoAvatarMood.sleepy,
    ];

    Future<void> golden(
      WidgetTester tester,
      List<KletsoAvatarController> controllers,
      String name,
    ) async {
      const avatarSize = 96.0;
      const gap = 8.0;
      final width =
          controllers.length * avatarSize + (controllers.length + 1) * gap;
      tester.view.physicalSize = Size(width, 132);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: KletsoTheme.light(
            useHostFont: true,
          ).materialTheme(ThemeData.light()),
          home: Scaffold(
            backgroundColor: KletsoTokens.cream,
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final c in controllers) ...<Widget>[
                    const SizedBox(width: gap),
                    KletsoAvatar(
                      controller: c,
                      size: avatarSize,
                      animate: false,
                    ),
                  ],
                  const SizedBox(width: gap),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    testWidgets('all moods, 96px, in a row', (tester) async {
      final controllers = [
        for (final mood in moods) KletsoAvatarController(defaultMood: mood),
      ];
      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
        }
      });
      await golden(tester, controllers, 'avatar_moods');
    });

    testWidgets('speaking at four lip-sync levels', (tester) async {
      const levels = <double>[0, 0.3, 0.7, 1.0];
      final controllers = [
        for (final level in levels)
          KletsoAvatarController(defaultMood: KletsoAvatarMood.speaking)
            ..setLevel(level / KletsoAvatarFaceData.gain),
      ];
      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
        }
      });
      await golden(tester, controllers, 'avatar_speaking_levels');
    });
  });
}

/// A 1×1 transparent PNG, enough for an [ImageProvider] in widget tests.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A single picture for the plain image-style test.
final MemoryImage _png1 = MemoryImage(_png);

/// Distinct providers per mood (different byte copies compare unequal).
MemoryImage _picture(int seed) =>
    MemoryImage(Uint8List.fromList(<int>[..._png, seed]));

void moodImageTests() {
  group('KletsoAvatar mood pictures', () {
    Widget harnessFor(Widget child, {bool reducedMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: harness(child),
    );

    Iterable<ImageProvider> shownProviders(WidgetTester tester) =>
        tester.widgetList<Image>(find.byType(Image)).map((w) => w.image);

    testWidgets('crossfades to the new mood picture', (tester) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      final neutral = _picture(1);
      final happy = _picture(2);
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(
            controller: controller,
            style: KletsoAvatarStyle.image,
            moodImages: <KletsoAvatarMood, ImageProvider>{
              KletsoAvatarMood.neutral: neutral,
              KletsoAvatarMood.happy: happy,
            },
          ),
        ),
      );
      await tester.pump();
      expect(shownProviders(tester), <ImageProvider>[neutral]);
      controller.setMood(KletsoAvatarMood.happy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // mid-crossfade: both pictures are on screen, stacked
      expect(shownProviders(tester).toSet(), <ImageProvider>{neutral, happy});
      await tester.pump(const Duration(milliseconds: 300));
      expect(shownProviders(tester), <ImageProvider>[happy]);
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('reduced motion swaps the picture instantly', (tester) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      final neutral = _picture(1);
      final sorry = _picture(3);
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(
            controller: controller,
            style: KletsoAvatarStyle.image,
            moodImages: <KletsoAvatarMood, ImageProvider>{
              KletsoAvatarMood.neutral: neutral,
              KletsoAvatarMood.sorry: sorry,
            },
          ),
          reducedMotion: true,
        ),
      );
      await tester.pump();
      controller.setMood(KletsoAvatarMood.sorry);
      await tester.pump();
      expect(shownProviders(tester), <ImageProvider>[sorry]);
    });

    testWidgets('a mood without its own picture falls back to imageProvider', (
      tester,
    ) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      final fallback = _picture(9);
      await tester.pumpWidget(
        harnessFor(
          KletsoAvatar(
            controller: controller,
            style: KletsoAvatarStyle.image,
            imageProvider: fallback,
            moodImages: <KletsoAvatarMood, ImageProvider>{
              KletsoAvatarMood.happy: _picture(2),
            },
            animate: false,
          ),
        ),
      );
      await tester.pump();
      expect(shownProviders(tester), <ImageProvider>[fallback]);
      controller.setMood(KletsoAvatarMood.thinking);
      await tester.pump();
      expect(shownProviders(tester), <ImageProvider>[fallback]);
    });

    testWidgets('no picture at all draws the procedural mascot', (
      tester,
    ) async {
      await tester.pumpWidget(
        harnessFor(const KletsoAvatar(style: KletsoAvatarStyle.image)),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is KletsoAvatarPainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a new moodImages map is picked up without restart', (
      tester,
    ) async {
      final controller = KletsoAvatarController();
      addTearDown(controller.dispose);
      final first = _picture(1);
      final second = _picture(2);
      Widget build(ImageProvider p) => harnessFor(
        KletsoAvatar(
          controller: controller,
          style: KletsoAvatarStyle.image,
          moodImages: <KletsoAvatarMood, ImageProvider>{
            KletsoAvatarMood.neutral: p,
          },
          animate: false,
        ),
      );
      await tester.pumpWidget(build(first));
      await tester.pump();
      expect(shownProviders(tester), <ImageProvider>[first]);
      await tester.pumpWidget(build(second));
      await tester.pump();
      expect(shownProviders(tester), <ImageProvider>[second]);
    });
  });

  group('KletsoClientAvatar.parseImages', () {
    test('keeps https URLs for known moods and drops the rest', () {
      final images = KletsoClientAvatar.parseImages(<String, Object?>{
        'happy': 'https://cdn.acme.com/happy.webp',
        'sorry': 'http://cdn.acme.com/sorry.png',
        'wink': 'not a url',
        'bogus': 'https://cdn.acme.com/bogus.png',
        'thinking': 42,
      });
      expect(images.keys, <KletsoAvatarMood>[KletsoAvatarMood.happy]);
      expect(
        images[KletsoAvatarMood.happy],
        Uri.parse('https://cdn.acme.com/happy.webp'),
      );
      expect(KletsoClientAvatar.parseImages(null), isEmpty);
      expect(KletsoClientAvatar.parseImages('x'), isEmpty);
      expect(
        () => images[KletsoAvatarMood.wink] = Uri(),
        throwsUnsupportedError,
      );
    });
  });
}
