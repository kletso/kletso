import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart' show immutable;

import 'avatar_face.dart';
import 'kletso_avatar_face.g.dart';

/// Colour overrides for [KletsoAvatarPainter] (a customer's brand colours
/// instead of the default Kletso orange). Any field left `null` falls back
/// to [KletsoAvatarFaceData].
@immutable
final class KletsoAvatarColors {
  /// Creates an override set; every field defaults to the Kletso palette.
  const KletsoAvatarColors({this.body, this.eye, this.mouth, this.tongue});

  /// Replaces [KletsoAvatarFaceData.bodyColor].
  final Color? body;

  /// Replaces [KletsoAvatarFaceData.eyeColor].
  final Color? eye;

  /// Replaces [KletsoAvatarFaceData.mouthColor].
  final Color? mouth;

  /// Replaces [KletsoAvatarFaceData.tongueColor].
  final Color? tongue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KletsoAvatarColors &&
          body == other.body &&
          eye == other.eye &&
          mouth == other.mouth &&
          tongue == other.tongue;

  @override
  int get hashCode => Object.hash(body, eye, mouth, tongue);
}

/// Draws the procedural Kletso mascot face from [params] plus the ambient
/// animation phases computed by [KletsoAvatar] (breathing, blinking, gaze
/// drift, bounce). Geometry and colours come from [KletsoAvatarFaceData]
/// unless overridden by [colors].
///
/// Below [detailThreshold] logical pixels, the gloss highlight and blush are
/// skipped (they are sub-pixel noise at avatar-in-a-bubble sizes).
final class KletsoAvatarPainter extends CustomPainter {
  /// Creates the painter.
  KletsoAvatarPainter({
    required this.params,
    this.colors,
    this.breathScale = 1,
    this.blinkMultiplier = 1,
    this.gazeDrift = Offset.zero,
    this.bounceAmount = 0,
    this.detailThreshold = 32,
  });

  /// The resolved face parameters to draw.
  final KletsoAvatarFaceParams params;

  /// Optional brand colour overrides.
  final KletsoAvatarColors? colors;

  /// Head scale from the idle breathing loop (around `1.0`).
  final double breathScale;

  /// `0` = eyes fully shut (blink), `1` = normal; interpolates [params]'s
  /// `eyeOpen` down during a blink.
  final double blinkMultiplier;

  /// Ambient gaze wander added to [KletsoAvatarFaceParams.gaze], in face
  /// units.
  final Offset gazeDrift;

  /// Bounce amount in `-1..1`, scaled by [KletsoAvatarFaceData.bounceTravel].
  final double bounceAmount;

  /// Minimum size (logical pixels, the smaller of width/height) at which the
  /// gloss dot and blush are drawn.
  final double detailThreshold;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final r = radius * breathScale;
    final detailed = math.min(size.width, size.height) >= detailThreshold;
    final center = size.center(Offset.zero);
    canvas.save();
    canvas.translate(
      center.dx,
      center.dy - bounceAmount * KletsoAvatarFaceData.bounceTravel * radius,
    );
    canvas.rotate(params.headTilt * math.pi / 180);

    _paintBody(canvas, r, detailed: detailed);
    _paintEye(canvas, r, detailed: detailed, isRight: true);
    _paintEye(canvas, r, detailed: detailed, isRight: false);
    _paintMouth(canvas, r);
    if (detailed && params.blush > 0) _paintBlush(canvas, r);

    canvas.restore();
  }

  void _paintBody(Canvas canvas, double r, {required bool detailed}) {
    final body = colors?.body ?? KletsoAvatarFaceData.bodyColor;
    canvas.drawCircle(Offset.zero, r, Paint()..color = body);
    if (!detailed) return;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.drawCircle(
      Offset(-r * 0.35, -r * 0.4),
      r * 0.55,
      Paint()
        ..color = KletsoAvatarFaceData.bodyHighlight.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      Offset(r * 0.25, r * 0.55),
      r * 0.6,
      Paint()..color = KletsoAvatarFaceData.bodyShadow.withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  void _paintEye(
    Canvas canvas,
    double r, {
    required bool detailed,
    required bool isRight,
  }) {
    final side = isRight ? 1.0 : -1.0;
    final eyeColor = colors?.eye ?? KletsoAvatarFaceData.eyeColor;
    final tiltOffset =
        side * params.eyeTilt * KletsoAvatarFaceData.eyeTiltTravel * r;
    final baseX = side * KletsoAvatarFaceData.eyeCenterX * r;
    final baseY = KletsoAvatarFaceData.eyeCenterY * r + tiltOffset;
    final gazeX =
        (params.gaze.dx + gazeDrift.dx) * KletsoAvatarFaceData.gazeTravel * r;
    final gazeY =
        (params.gaze.dy + gazeDrift.dy) * KletsoAvatarFaceData.gazeTravel * r;
    final eyeCenter = Offset(baseX + gazeX, baseY + gazeY);

    final shut =
        params.eyeShape == KletsoAvatarEyeShape.arc ||
        (isRight && params.winkRight);
    final openAmount = (params.eyeOpen * blinkMultiplier).clamp(0.0, 1.4);

    if (shut || openAmount < 0.08) {
      final hw = KletsoAvatarFaceData.eyeRadius * r;
      final path = Path()
        ..moveTo(eyeCenter.dx - hw, eyeCenter.dy)
        ..quadraticBezierTo(
          eyeCenter.dx,
          eyeCenter.dy - hw * 0.9,
          eyeCenter.dx + hw,
          eyeCenter.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = eyeColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = KletsoAvatarFaceData.arcEyeStroke * r,
      );
      return;
    }

    final rx = KletsoAvatarFaceData.eyeRadius * r;
    final ry = rx * openAmount.clamp(0.18, 1.3).toDouble();
    canvas.drawOval(
      Rect.fromCenter(center: eyeCenter, width: rx * 2, height: ry * 2),
      Paint()..color = eyeColor,
    );
    if (detailed && openAmount > 0.3) {
      canvas.drawCircle(
        eyeCenter + KletsoAvatarFaceData.eyeGlossOffset * r,
        KletsoAvatarFaceData.eyeGlossRadius * r,
        Paint()..color = KletsoAvatarFaceData.eyeGloss,
      );
    }
  }

  void _paintMouth(Canvas canvas, double r) {
    final hw = params.mouthWidth * r;
    final halfOpen =
        params.mouthOpen * KletsoAvatarFaceData.mouthOpenTravel * 0.5 * r;
    final curveOffset =
        params.mouthCurve * KletsoAvatarFaceData.mouthCurveTravel * r;
    final centerY = KletsoAvatarFaceData.mouthCenterY * r;
    final mouthColor = colors?.mouth ?? KletsoAvatarFaceData.mouthColor;

    // Scales with mouthOpenTravel (ratio tuned at the original 0.42 travel)
    // so a closed-ish mood (thinking/sorry/sleepy/listening/confused) stays
    // a simple line regardless of how far the shared travel knob is raised
    // for the moods that should look clearly open.
    final closedThreshold =
        r * KletsoAvatarFaceData.mouthOpenTravel * (0.03 / 0.42);
    if (halfOpen < closedThreshold) {
      final path = Path()
        ..moveTo(-hw, centerY)
        ..quadraticBezierTo(0, centerY + curveOffset, hw, centerY);
      canvas.drawPath(
        path,
        Paint()
          ..color = mouthColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = KletsoAvatarFaceData.lipStroke * r,
      );
      return;
    }

    final Path mouthPath;
    final Rect localBounds;
    if (hw < halfOpen * 2.2) {
      // Roughly as tall as it is wide (e.g. surprised): a round "o", not a
      // smile shape.
      final center = Offset(0, curveOffset * 0.3);
      localBounds = Rect.fromCenter(
        center: center,
        width: hw * 2,
        height: halfOpen * 2,
      );
      mouthPath = Path()..addOval(localBounds);
    } else {
      // A bulging capsule: fuller in the middle (bent by curveOffset, like a
      // grin or a frown), tapering a little — but not to a point — at the
      // corners. A lens/vesica shape tapered fully to zero height at the
      // edges, leaving teeth/tongue no room to show in; a plain
      // straight-sided capsule had no smile/frown shape at all.
      final cornerHalf = halfOpen * 0.55;
      final topCtrl = Offset(0, -halfOpen + curveOffset);
      final botCtrl = Offset(0, halfOpen + curveOffset);
      mouthPath = Path()
        ..moveTo(-hw, -cornerHalf)
        ..quadraticBezierTo(topCtrl.dx, topCtrl.dy, hw, -cornerHalf)
        ..lineTo(hw, cornerHalf)
        ..quadraticBezierTo(botCtrl.dx, botCtrl.dy, -hw, cornerHalf)
        ..close();
      // A quadratic Bezier does not reach its control point: at x == 0 (the
      // curve's midpoint, t == 0.5) the curve only gets a quarter of the way
      // from the corner to the control point. Path.getBounds() would use the
      // control point itself and badly overestimate how tall the shape
      // really is, leaving teeth/tongue positioned outside it and clipped
      // away entirely — so the true top/bottom are computed directly here.
      final trueTop = 0.5 * (-cornerHalf + topCtrl.dy);
      final trueBottom = 0.5 * (cornerHalf + botCtrl.dy);
      localBounds = Rect.fromLTRB(-hw, trueTop, hw, trueBottom);
    }

    // Everything above is in "mouth-local" coordinates (0,0 == the mouth's
    // resting centre); translate once so drawing and clipping agree.
    canvas.save();
    canvas.translate(0, centerY);
    canvas.drawPath(mouthPath, Paint()..color = mouthColor);

    if (params.tongue <= 0 && params.teeth <= 0) {
      canvas.restore();
      return;
    }
    final bounds = localBounds;
    canvas.clipPath(mouthPath);
    if (params.teeth > 0) {
      final teethColor = KletsoAvatarFaceData.teethColor;
      final teethHeightPx =
          bounds.height *
          KletsoAvatarFaceData.teethHeight *
          params.teeth.clamp(0.0, 1.0).toDouble();
      canvas.drawRect(
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, teethHeightPx),
        Paint()..color = teethColor,
      );
    }
    if (params.tongue > 0) {
      final tongueColor = colors?.tongue ?? KletsoAvatarFaceData.tongueColor;
      final tongueAmount = params.tongue.clamp(0.0, 1.0).toDouble();
      final tongueHeightPx =
          KletsoAvatarFaceData.tongueHeight * bounds.height * tongueAmount;
      canvas.drawOval(
        Rect.fromCenter(
          // Nudged up from the very bottom edge so most of the oval lands
          // inside the (possibly curved) mouth outline instead of being
          // clipped away.
          center: Offset(
            bounds.center.dx,
            bounds.bottom - tongueHeightPx * 0.3,
          ),
          width: KletsoAvatarFaceData.tongueWidth * bounds.width * tongueAmount,
          height: tongueHeightPx,
        ),
        Paint()..color = tongueColor,
      );
    }
    canvas.restore();
  }

  void _paintBlush(Canvas canvas, double r) {
    final blushColor = KletsoAvatarFaceData.blushColor.withValues(
      alpha: 0.5 * params.blush.clamp(0.0, 1.0).toDouble(),
    );
    for (final side in <double>[-1, 1]) {
      canvas.drawCircle(
        Offset(
          side * KletsoAvatarFaceData.blushCenter.dx * r,
          KletsoAvatarFaceData.blushCenter.dy * r,
        ),
        KletsoAvatarFaceData.blushRadius * r,
        Paint()..color = blushColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant KletsoAvatarPainter oldDelegate) =>
      params != oldDelegate.params ||
      colors != oldDelegate.colors ||
      breathScale != oldDelegate.breathScale ||
      blinkMultiplier != oldDelegate.blinkMultiplier ||
      gazeDrift != oldDelegate.gazeDrift ||
      bounceAmount != oldDelegate.bounceAmount;

  @override
  bool? hitTest(Offset position) => false;
}
