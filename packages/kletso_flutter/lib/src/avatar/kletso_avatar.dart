import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../theme/kletso_theme.dart';
import 'avatar_controller.dart';
import 'avatar_face.dart';
import 'avatar_painter.dart';
import 'kletso_avatar_face.g.dart';

/// How [KletsoAvatar] renders.
enum KletsoAvatarStyle {
  /// The procedural Kletso mascot face.
  kletso,

  /// A host-supplied image, clipped to a circle with a speaking ring.
  image,

  /// A plain primary-colour circle with a chat icon (today's bubble dot).
  none,
}

/// The animated Kletso mascot avatar: a live vector face that breathes,
/// blinks, looks around, tweens between moods and lip-syncs to
/// [KletsoAvatarController.level] (`packages/design/avatar.json`, D81).
///
/// Drop it anywhere a small face or a big "voice mode" face is needed; it
/// owns a default controller when [controller] is `null`. Respects
/// `MediaQuery.disableAnimations`: idle motion stops, but mood changes still
/// apply instantly rather than freezing the face on the wrong expression.
///
/// With [KletsoAvatarStyle.image] the host's own pictures replace the vector
/// face: one per mood through [moodImages] (crossfade on mood change,
/// breathing idle loop, a bounce that follows the lip-sync level) or a single
/// [imageProvider].
final class KletsoAvatar extends StatefulWidget {
  /// Creates the avatar.
  const KletsoAvatar({
    super.key,
    this.controller,
    this.size = 64,
    this.style = KletsoAvatarStyle.kletso,
    this.colors,
    this.imageProvider,
    this.moodImages,
    this.animate = true,
    this.semanticsLabel,
  });

  /// Drives mood and lip-sync; a private neutral controller is used (and
  /// disposed) when `null`.
  final KletsoAvatarController? controller;

  /// Diameter in logical pixels.
  final double size;

  /// Which face to draw.
  final KletsoAvatarStyle style;

  /// Brand colour overrides for [KletsoAvatarStyle.kletso].
  final KletsoAvatarColors? colors;

  /// The image for [KletsoAvatarStyle.image] (ignored otherwise); the
  /// fallback when [moodImages] has no entry for the current mood.
  final ImageProvider? imageProvider;

  /// One picture per mood for [KletsoAvatarStyle.image]: the face crossfades
  /// to `moodImages[mood]` when the mood changes, falling back to
  /// [imageProvider], then to the procedural mascot when neither exists.
  /// Animated GIF/WebP files play on their own. The other moods' pictures
  /// are pre-cached after the first frame so the first crossfade is never
  /// blank.
  final Map<KletsoAvatarMood, ImageProvider>? moodImages;

  /// Whether to idle-animate (breathe/blink/gaze/bounce) and tween between
  /// moods. When `false`, mood changes apply instantly with no motion.
  final bool animate;

  /// Accessible label; defaults to a label derived from the current mood.
  final String? semanticsLabel;

  @override
  State<KletsoAvatar> createState() => _KletsoAvatarState();
}

final class _KletsoAvatarState extends State<KletsoAvatar>
    with SingleTickerProviderStateMixin {
  late KletsoAvatarController _controller;
  bool _ownsController = false;
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;
  Duration _transitionStart = Duration.zero;
  bool _transitioning = false;
  KletsoAvatarMood? _lastMood;
  late KletsoAvatarFaceParams _fromParams;
  late KletsoAvatarFaceParams _toParams;
  late final double _blinkPhaseMs;
  late final double _gazePhase;

  @override
  void initState() {
    super.initState();
    final rand = math.Random();
    _blinkPhaseMs = rand.nextDouble() * 6000;
    _gazePhase = rand.nextDouble() * math.pi * 2;
    _bindController(widget.controller);
  }

  void _bindController(KletsoAvatarController? external) {
    if (external == null) {
      _ownsController = true;
      _controller = KletsoAvatarController();
    } else {
      _ownsController = false;
      _controller = external;
    }
    _lastMood = _controller.mood;
    _toParams = KletsoAvatarFaceParams.forMood(_controller.mood);
    _fromParams = _toParams;
    _controller.addListener(_onControllerChanged);
  }

  void _unbindController() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
    _precacheMoodImages();
  }

  @override
  void didUpdateWidget(covariant KletsoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _unbindController();
      _bindController(widget.controller);
    }
    if (widget.animate != oldWidget.animate) _syncTicker();
    if (!identical(widget.moodImages, oldWidget.moodImages)) {
      _precached.clear();
      _precacheMoodImages();
    }
  }

  /// Providers already handed to [precacheImage] for this widget.
  final Set<ImageProvider> _precached = <ImageProvider>{};

  /// Warms the image cache with every mood picture after the first frame, so
  /// the first crossfade shows a picture rather than a blank circle. Load
  /// failures are ignored here; the visible [Image] reports them.
  void _precacheMoodImages() {
    final images = widget.moodImages;
    if (widget.style != KletsoAvatarStyle.image || images == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final provider in images.values) {
        if (!_precached.add(provider)) continue;
        unawaited(
          precacheImage(
            provider,
            context,
            onError: (_, _) {},
          ).catchError((Object _) {}),
        );
      }
    });
  }

  bool get _reducedMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _syncTicker() {
    final shouldRun = widget.animate && !_reducedMotion;
    if (shouldRun && _ticker == null) {
      _ticker = createTicker(_onTick)..start();
    } else if (!shouldRun && _ticker != null) {
      _ticker!
        ..stop()
        ..dispose();
      _ticker = null;
      _elapsed = Duration.zero;
      _transitioning = false;
      _toParams = KletsoAvatarFaceParams.forMood(_controller.mood);
      _fromParams = _toParams;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    setState(() {
      _elapsed = elapsed;
      if (_transitioning) {
        final t =
            (elapsed - _transitionStart).inMilliseconds /
            KletsoAvatarFaceData.transitionMs;
        if (t >= 1) _transitioning = false;
      }
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.mood != _lastMood) {
      _lastMood = _controller.mood;
      final next = KletsoAvatarFaceParams.forMood(_controller.mood);
      if (_ticker != null) {
        setState(() {
          _fromParams = _currentBaseParams();
          _toParams = next;
          _transitionStart = _elapsed;
          _transitioning = true;
        });
      } else {
        setState(() {
          _toParams = next;
          _fromParams = next;
          _transitioning = false;
        });
      }
    } else {
      // Level changed (speaking) or a same-mood ttl refresh; just repaint.
      setState(() {});
    }
  }

  KletsoAvatarFaceParams _currentBaseParams() {
    if (!_transitioning) return _toParams;
    final rawT =
        (_elapsed - _transitionStart).inMilliseconds /
        KletsoAvatarFaceData.transitionMs;
    final t = KletsoAvatarFaceData.transitionCurve.transform(
      rawT.clamp(0.0, 1.0).toDouble(),
    );
    return KletsoAvatarFaceParams.lerp(_fromParams, _toParams, t);
  }

  double _resolveMouthOpen(KletsoAvatarFaceParams params) {
    if (!params.mouthIsLipsync) return params.mouthOpen;
    final level = _controller.level;
    return KletsoAvatarFaceData.minOpen +
        level * (KletsoAvatarFaceData.maxOpen - KletsoAvatarFaceData.minOpen);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _unbindController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.semanticsLabel ?? 'Kletso mascot, ${_controller.mood.wire}';
    return Semantics(
      label: label,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: switch (widget.style) {
          KletsoAvatarStyle.none => _buildNone(context),
          KletsoAvatarStyle.image => _buildImage(context),
          KletsoAvatarStyle.kletso => _buildKletso(context),
        },
      ),
    );
  }

  Widget _buildNone(BuildContext context) {
    final t = KletsoTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
      child: Center(
        child: Icon(
          Icons.chat_bubble,
          size: widget.size * 0.5,
          color: t.onPrimary,
        ),
      ),
    );
  }

  /// The picture for the current mood, the single fallback picture, or
  /// `null` when the host configured neither (the mascot is drawn instead).
  ImageProvider? _resolveImage() =>
      widget.moodImages?[_controller.mood] ?? widget.imageProvider;

  Widget _buildImage(BuildContext context) {
    final provider = _resolveImage();
    if (provider == null) return _buildKletso(context);
    final t = KletsoTheme.of(context);
    final level = _controller.level;
    final animated = _ticker != null;
    final seconds = _elapsed.inMicroseconds / 1e6;
    // Breathing idle loop (1.0 → 1.03, ~3.2 s there and back) plus a talk
    // bounce that follows the same lip-sync level as the vector mouth.
    final breath = animated
        ? 1.015 + 0.015 * math.sin(2 * math.pi * seconds / _imageBreathSeconds)
        : 1.0;
    final scale = breath * (1 + level * 0.06);
    final lift = level * 4;
    final crossfade = animated
        ? const Duration(milliseconds: _imageCrossfadeMs)
        : Duration.zero;
    return Transform.translate(
      offset: Offset(0, -lift),
      child: Transform.scale(
        scale: scale,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: t.primary,
              width: 2 + level * (widget.size * 0.06),
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: AnimatedSwitcher(
              duration: crossfade,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              layoutBuilder: _stackedLayout,
              child: Image(
                key: ValueKey<ImageProvider>(provider),
                image: provider,
                fit: BoxFit.cover,
                width: widget.size,
                height: widget.size,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => ColoredBox(color: t.primarySoft),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the outgoing and incoming pictures on top of each other during the
  /// crossfade (the default layout would centre them in a loose stack).
  static Widget _stackedLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) => Stack(
    fit: StackFit.expand,
    children: <Widget>[...previousChildren, ?currentChild],
  );

  /// Crossfade length between two mood pictures.
  static const int _imageCrossfadeMs = 220;

  /// One full breath (in and out) for picture avatars.
  static const double _imageBreathSeconds = 3.2;

  Widget _buildKletso(BuildContext context) {
    final base = _currentBaseParams();
    final resolved = base.withMouthOpen(_resolveMouthOpen(base));
    final animated = _ticker != null;
    final seconds = _elapsed.inMicroseconds / 1e6;
    final breath = animated
        ? 1 +
              KletsoAvatarFaceData.breathScale *
                  math.sin(
                    2 * math.pi * seconds / KletsoAvatarFaceData.breathSeconds,
                  )
        : 1.0;
    final blinkPeriodMs =
        (KletsoAvatarFaceData.blinkEverySeconds[0] +
            KletsoAvatarFaceData.blinkEverySeconds[1]) *
        500;
    final phaseMs = animated
        ? (_elapsed.inMilliseconds + _blinkPhaseMs) % blinkPeriodMs
        : blinkPeriodMs;
    final blinkMs = KletsoAvatarFaceData.blinkMs;
    final blink = animated && phaseMs < blinkMs
        ? (1 - math.sin(math.pi * phaseMs / blinkMs)).clamp(0.0, 1.0).toDouble()
        : 1.0;
    final gazeDx = animated
        ? KletsoAvatarFaceData.gazeDriftAmount *
              0.5 *
              math.sin(
                2 * math.pi * seconds / KletsoAvatarFaceData.gazeDriftSeconds +
                    _gazePhase,
              )
        : 0.0;
    final gazeDy = animated
        ? KletsoAvatarFaceData.gazeDriftAmount *
              0.5 *
              math.cos(
                2 *
                        math.pi *
                        seconds /
                        (KletsoAvatarFaceData.gazeDriftSeconds * 1.3) +
                    _gazePhase,
              )
        : 0.0;
    final bouncePhase = animated && resolved.bounce != 0
        ? 0.5 -
              0.5 *
                  math.cos(
                    2 * math.pi * seconds / KletsoAvatarFaceData.bounceSeconds,
                  )
        : 0.0;
    return CustomPaint(
      size: Size.square(widget.size),
      painter: KletsoAvatarPainter(
        params: resolved,
        colors: widget.colors,
        breathScale: breath,
        blinkMultiplier: blink,
        gazeDrift: Offset(gazeDx, gazeDy),
        bounceAmount: resolved.bounce * bouncePhase,
      ),
    );
  }
}
