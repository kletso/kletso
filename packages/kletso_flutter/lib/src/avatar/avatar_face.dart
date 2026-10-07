import 'dart:ui' show lerpDouble;

import 'package:flutter/painting.dart' show Offset;
import 'package:meta/meta.dart' show immutable;

import 'kletso_avatar_face.g.dart';

/// The mascot's expression. Drives [KletsoAvatarFaceParams.forMood] and the
/// default client-side mood rules (`packages/design/avatar.json`, D81/D83).
///
/// Every vocabulary in the Kletso protocol has an [unknown] member so a
/// future server can send a mood this SDK does not know about yet without
/// breaking older clients; [unknown] renders exactly like [neutral].
enum KletsoAvatarMood {
  /// Resting face: no particular emotion.
  neutral(wire: 'neutral'),

  /// A warm smile.
  happy(wire: 'happy'),

  /// Eyes shut, wide open laughing mouth.
  laughing(wire: 'laughing'),

  /// Wide eyes, small round open mouth.
  surprised(wire: 'surprised'),

  /// Gaze drifts up and to the side, slight head tilt.
  thinking(wire: 'thinking'),

  /// One eye closed in a wink.
  wink(wire: 'wink'),

  /// Attentive: slightly wider eyes, head tilted toward the speaker.
  listening(wire: 'listening'),

  /// Mouth opening follows [KletsoAvatarController.level] (lip-sync).
  speaking(wire: 'speaking'),

  /// Apologetic: eyes and mouth soften downward.
  sorry(wire: 'sorry'),

  /// Puzzled: gaze to the side, head tilted further than [thinking].
  confused(wire: 'confused'),

  /// Drowsy: eyes nearly closed, a slow droop.
  sleepy(wire: 'sleepy'),

  /// An unrecognised mood from a newer server; renders as [neutral].
  unknown(wire: 'unknown');

  const KletsoAvatarMood({required this.wire});

  /// The wire value used by `avatar.mood` events and agent configuration.
  final String wire;

  /// Parses [value] into a [KletsoAvatarMood]; `null` or anything this SDK
  /// does not recognise becomes [unknown]. Never throws.
  static KletsoAvatarMood parse(String? value) => KletsoAvatarMood.values
      .firstWhere((mood) => mood.wire == value, orElse: () => unknown);
}

/// Whether an eye is drawn as a filled dot ([round]) or a closed, stroked
/// curve ([arc]), as set by a mood's `eyeShape`.
enum KletsoAvatarEyeShape {
  /// A filled circle/oval (open eye).
  round,

  /// A thin closed-eye curve (e.g. [KletsoAvatarMood.laughing]).
  arc,
}

/// The resolved, numeric face parameters [KletsoAvatarPainter] draws:
/// `defaults` merged with one mood's overrides from
/// `packages/design/avatar.json` (D81).
///
/// Values are already in "ready to paint" units; geometry constants that
/// turn them into pixels live in [KletsoAvatarFaceData].
@immutable
final class KletsoAvatarFaceParams {
  /// Creates an explicit parameter set. Prefer [forMood].
  const KletsoAvatarFaceParams({
    required this.eyeOpen,
    required this.eyeShape,
    required this.winkRight,
    required this.gaze,
    required this.eyeTilt,
    required this.mouthCurve,
    required this.mouthOpen,
    required this.mouthIsLipsync,
    required this.mouthWidth,
    required this.tongue,
    required this.teeth,
    required this.blush,
    required this.headTilt,
    required this.bounce,
  });

  /// Builds the params for [mood]: `defaults` overridden by
  /// `moods[mood.wire]` (empty for [KletsoAvatarMood.neutral] and
  /// [KletsoAvatarMood.unknown], so both render as the plain default face).
  factory KletsoAvatarFaceParams.forMood(KletsoAvatarMood mood) {
    final merged = <String, Object?>{
      ...KletsoAvatarFaceData.defaults,
      ...?KletsoAvatarFaceData.moods[mood.wire],
    };
    final mouthOpenRaw = merged['mouthOpen'];
    final isLipsync = mouthOpenRaw is String;
    final gazeList = merged['gaze']! as List<double>;
    return KletsoAvatarFaceParams(
      eyeOpen: (merged['eyeOpen']! as num).toDouble(),
      eyeShape: merged['eyeShape'] == 'arc'
          ? KletsoAvatarEyeShape.arc
          : KletsoAvatarEyeShape.round,
      winkRight: merged['winkRight']! as bool,
      gaze: Offset(gazeList[0], gazeList[1]),
      eyeTilt: (merged['eyeTilt']! as num).toDouble(),
      mouthCurve: (merged['mouthCurve']! as num).toDouble(),
      mouthOpen: isLipsync ? 0.0 : (mouthOpenRaw! as num).toDouble(),
      mouthIsLipsync: isLipsync,
      mouthWidth: (merged['mouthWidth']! as num).toDouble(),
      tongue: (merged['tongue']! as num).toDouble(),
      teeth: (merged['teeth']! as num).toDouble(),
      blush: (merged['blush']! as num).toDouble(),
      headTilt: (merged['headTilt']! as num).toDouble(),
      bounce: (merged['bounce']! as num).toDouble(),
    );
  }

  /// How open the eyes are (`1.0` normal, `0.0` shut, `>1.0` wide).
  final double eyeOpen;

  /// Whether the eyes are drawn open (filled) or closed (stroked arc).
  final KletsoAvatarEyeShape eyeShape;

  /// Whether only the right eye is shut in a wink, regardless of [eyeShape].
  final bool winkRight;

  /// Where the eyes look, as a fraction of [KletsoAvatarFaceData.gazeTravel].
  final Offset gaze;

  /// Asymmetric eyebrow-like vertical offset between the two eyes, as a
  /// fraction of [KletsoAvatarFaceData.eyeTiltTravel].
  final double eyeTilt;

  /// Smile (positive) to frown (negative) curvature of the mouth.
  final double mouthCurve;

  /// How open the mouth is (`0`..`~1`). Ignored (always driven live) when
  /// [mouthIsLipsync] is `true`.
  final double mouthOpen;

  /// Whether [mouthOpen] should instead follow
  /// [KletsoAvatarController.level] (the `speaking` mood).
  final bool mouthIsLipsync;

  /// Mouth half-width as a fraction of the head radius.
  final double mouthWidth;

  /// How much pink tongue shows at the bottom of an open mouth (`0`..`~1`).
  final double tongue;

  /// How much white teeth show at the top of an open mouth (`0`..`1`).
  final double teeth;

  /// Cheek blush opacity (`0`..`1`).
  final double blush;

  /// Head rotation in degrees.
  final double headTilt;

  /// Bounce direction/amplitude (`-1`..`1`); animated by the idle loop.
  final double bounce;

  /// Returns a copy with [mouthOpen] replaced (used once [mouthIsLipsync]
  /// has been resolved against the live lip-sync level).
  KletsoAvatarFaceParams withMouthOpen(double mouthOpen) =>
      KletsoAvatarFaceParams(
        eyeOpen: eyeOpen,
        eyeShape: eyeShape,
        winkRight: winkRight,
        gaze: gaze,
        eyeTilt: eyeTilt,
        mouthCurve: mouthCurve,
        mouthOpen: mouthOpen,
        mouthIsLipsync: mouthIsLipsync,
        mouthWidth: mouthWidth,
        tongue: tongue,
        teeth: teeth,
        blush: blush,
        headTilt: headTilt,
        bounce: bounce,
      );

  /// Linearly interpolates every numeric field; discrete fields ([eyeShape],
  /// [winkRight], [mouthIsLipsync]) step from [a] to [b] at `t >= 0.5`.
  static KletsoAvatarFaceParams lerp(
    KletsoAvatarFaceParams a,
    KletsoAvatarFaceParams b,
    double t,
  ) {
    double d(double x, double y) => lerpDouble(x, y, t)!;
    return KletsoAvatarFaceParams(
      eyeOpen: d(a.eyeOpen, b.eyeOpen),
      eyeShape: t < 0.5 ? a.eyeShape : b.eyeShape,
      winkRight: t < 0.5 ? a.winkRight : b.winkRight,
      gaze: Offset.lerp(a.gaze, b.gaze, t)!,
      eyeTilt: d(a.eyeTilt, b.eyeTilt),
      mouthCurve: d(a.mouthCurve, b.mouthCurve),
      mouthOpen: d(a.mouthOpen, b.mouthOpen),
      mouthIsLipsync: t < 0.5 ? a.mouthIsLipsync : b.mouthIsLipsync,
      mouthWidth: d(a.mouthWidth, b.mouthWidth),
      tongue: d(a.tongue, b.tongue),
      teeth: d(a.teeth, b.teeth),
      blush: d(a.blush, b.blush),
      headTilt: d(a.headTilt, b.headTilt),
      bounce: d(a.bounce, b.bounce),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KletsoAvatarFaceParams &&
          eyeOpen == other.eyeOpen &&
          eyeShape == other.eyeShape &&
          winkRight == other.winkRight &&
          gaze == other.gaze &&
          eyeTilt == other.eyeTilt &&
          mouthCurve == other.mouthCurve &&
          mouthOpen == other.mouthOpen &&
          mouthIsLipsync == other.mouthIsLipsync &&
          mouthWidth == other.mouthWidth &&
          tongue == other.tongue &&
          teeth == other.teeth &&
          blush == other.blush &&
          headTilt == other.headTilt &&
          bounce == other.bounce;

  @override
  int get hashCode => Object.hash(
    eyeOpen,
    eyeShape,
    winkRight,
    gaze,
    eyeTilt,
    mouthCurve,
    Object.hash(
      mouthOpen,
      mouthIsLipsync,
      mouthWidth,
      tongue,
      teeth,
      blush,
      headTilt,
      bounce,
    ),
  );
}
