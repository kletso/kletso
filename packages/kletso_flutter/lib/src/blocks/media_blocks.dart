import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../registry/build_context.dart';
import '../theme/kletso_theme.dart';
import 'support.dart';

/// `map`: the SDK paints a schematic map (markers and route projected onto
/// the box) with no dependency; tapping a marker fires its first action and
/// the node's own action ("Open in Maps") is offered as a button. Hosts that
/// want live tiles register their own `map` builder (see the example app,
/// which uses `flutter_map`).
Widget buildMapBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final markers = node
      .mapList('markers')
      .map(KletsoMapMarker.fromJson)
      .toList();
  final route = node
      .mapList('route')
      .map(
        (p) => (
          lat: (p['lat'] as num? ?? 0).toDouble(),
          lng: (p['lng'] as num? ?? 0).toDouble(),
        ),
      )
      .toList();
  final title = node.stringOrNull('title');
  final open = node.actions.where((a) => a is! KletsoUnknownAction).firstOrNull;
  final staticImage = node.stringOrNull('staticImage');
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (title != null) ...<Widget>[
        Text(title, style: t.subtitle),
        const SizedBox(height: 8),
      ],
      ClipRRect(
        borderRadius: t.borderRadiusMd,
        child: AspectRatio(
          aspectRatio: kletsoAspect(node.string('aspect', fallback: '16:9')),
          child: Semantics(
            label:
                '${title ?? 'Map'}: ${markers.map((m) => m.label ?? m.id).join(', ')}',
            child:
                staticImage != null && ctx.urlPolicy.check(staticImage) != null
                ? kletsoImage(ctx, staticImage, title ?? 'map')
                : _SchematicMap(
                    markers: markers,
                    route: route,
                    theme: t,
                    onMarkerTap: (m) =>
                        m.action == null ? null : ctx.execute(m.action!),
                  ),
          ),
        ),
      ),
      if (markers.any((m) => m.label != null)) ...<Widget>[
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            for (final m in markers.where((m) => m.label != null))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.place,
                    size: 14,
                    color: kletsoTone(t, m.tone).$2 == t.text
                        ? t.primary
                        : kletsoTone(t, m.tone).$2,
                  ),
                  const SizedBox(width: 4),
                  Text(m.label!, style: t.caption),
                ],
              ),
          ],
        ),
      ],
      if (open != null) ...<Widget>[
        const SizedBox(height: 8),
        KletsoButton(
          label: open.label ?? 'Open in Maps',
          variant: 'secondary',
          icon: 'location',
          onPressed: () => ctx.execute(open),
        ),
      ],
    ],
  );
}

/// One marker of a `map` block.
final class KletsoMapMarker {
  /// Creates a marker.
  const KletsoMapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    this.label,
    this.tone = 'neutral',
    this.action,
  });

  /// Reads a marker; the first usable action becomes [action].
  factory KletsoMapMarker.fromJson(JsonMap m) {
    KletsoAction? action;
    final raw = m['actions'];
    if (raw is List) {
      for (final a in raw) {
        try {
          final parsed = KletsoAction.fromJson(a);
          if (parsed is! KletsoUnknownAction) {
            action = parsed;
            break;
          }
        } on KletsoSchemaException {
          continue;
        }
      }
    }
    return KletsoMapMarker(
      id: m['id'] as String? ?? '',
      lat: (m['lat'] as num? ?? 0).toDouble(),
      lng: (m['lng'] as num? ?? 0).toDouble(),
      label: m['label'] as String?,
      tone: m['tone'] as String? ?? 'neutral',
      action: action,
    );
  }

  /// Marker id.
  final String id;

  /// Latitude.
  final double lat;

  /// Longitude.
  final double lng;

  /// Optional label.
  final String? label;

  /// Colour tone.
  final String tone;

  /// Tap action, if any.
  final KletsoAction? action;
}

final class _SchematicMap extends StatelessWidget {
  const _SchematicMap({
    required this.markers,
    required this.route,
    required this.theme,
    required this.onMarkerTap,
  });
  final List<KletsoMapMarker> markers;
  final List<({double lat, double lng})> route;
  final KletsoTheme theme;
  final Future<void>? Function(KletsoMapMarker) onMarkerTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final proj = _Projection.fit(<({double lat, double lng})>[
        ...markers.map((m) => (lat: m.lat, lng: m.lng)),
        ...route,
      ], size);
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _MapPainter(
                theme: theme,
                route: route.map(proj.point).toList(),
              ),
            ),
          ),
          for (final m in markers)
            Positioned(
              left: proj.point((lat: m.lat, lng: m.lng)).dx - 14,
              top: proj.point((lat: m.lat, lng: m.lng)).dy - 30,
              child: Semantics(
                button: m.action != null,
                label: m.label ?? m.id,
                child: GestureDetector(
                  onTap: m.action == null ? null : () => onMarkerTap(m),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.place,
                        size: 28,
                        color: kletsoTone(theme, m.tone).$2 == theme.text
                            ? theme.primary
                            : kletsoTone(theme, m.tone).$2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

final class _Projection {
  _Projection(this.minLat, this.maxLat, this.minLng, this.maxLng, this.size);

  factory _Projection.fit(List<({double lat, double lng})> pts, Size size) {
    if (pts.isEmpty) return _Projection(-1, 1, -1, 1, size);
    var minLat = pts.first.lat,
        maxLat = pts.first.lat,
        minLng = pts.first.lng,
        maxLng = pts.first.lng;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final padLat = math.max((maxLat - minLat) * 0.25, 0.005);
    final padLng = math.max((maxLng - minLng) * 0.25, 0.005);
    return _Projection(
      minLat - padLat,
      maxLat + padLat,
      minLng - padLng,
      maxLng + padLng,
      size,
    );
  }

  final double minLat, maxLat, minLng, maxLng;
  final Size size;

  Offset point(({double lat, double lng}) p) => Offset(
    (p.lng - minLng) / (maxLng - minLng) * size.width,
    (1 - (p.lat - minLat) / (maxLat - minLat)) * size.height,
  );
}

final class _MapPainter extends CustomPainter {
  _MapPainter({required this.theme, required this.route});
  final KletsoTheme theme;
  final List<Offset> route;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    final grid = Paint()
      ..color = theme.line
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // a few "blocks" so it reads as a map, deterministic
    final block = Paint()..color = theme.line.withValues(alpha: 0.5);
    for (var i = 0; i < 12; i++) {
      final x = (i * 97) % (size.width.toInt() + 1);
      final y = (i * 61) % (size.height.toInt() + 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 28, 18),
          const Radius.circular(3),
        ),
        block,
      );
    }
    if (route.length > 1) {
      final path = Path()..moveTo(route.first.dx, route.first.dy);
      for (final p in route.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = theme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.route != route || old.theme != theme;
}

/// `video`: poster with a play button. Without a host `video` builder the
/// SDK opens the source through `onOpenUrl` (allowlisted). The example app
/// overrides this with `video_player`.
Widget buildVideoBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final src = node.string('src');
  final poster = node.stringOrNull('poster');
  final title = node.stringOrNull('title');
  final duration = node.numberOrNull('durationSeconds');
  final allowed = ctx.urlPolicy.check(src) != null;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ClipRRect(
        borderRadius: t.borderRadiusMd,
        child: AspectRatio(
          aspectRatio: kletsoAspect(node.string('aspect', fallback: '16:9')),
          child: Semantics(
            button: allowed,
            label: 'Play video${title == null ? '' : ': $title'}',
            child: InkWell(
              onTap: allowed ? () => ctx.openUrl(src) : null,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (poster != null)
                    kletsoImage(ctx, poster, 'Video poster')
                  else
                    Container(color: t.text),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: t.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: t.onPrimary,
                        size: 34,
                      ),
                    ),
                  ),
                  if (duration != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: t.text.withValues(alpha: 0.75),
                          borderRadius: t.borderRadiusSm,
                        ),
                        child: Text(
                          KletsoFormat.duration(duration),
                          style: t.caption.copyWith(color: t.surface),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (title != null) ...<Widget>[
        const SizedBox(height: 6),
        Text(title, style: t.subtitle),
      ],
    ],
  );
}

/// `audio`: artwork or a painted waveform, title, duration and a play button
/// that opens the source; hosts override with a real player.
Widget buildAudioBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final src = node.string('src');
  final title = node.string('title', fallback: 'Audio');
  final subtitle = node.stringOrNull('subtitle');
  final transcript = node.stringOrNull('transcript');
  final duration = node.numberOrNull('durationSeconds');
  final artwork = node.stringOrNull('artwork');
  final allowed = ctx.urlPolicy.check(src) != null;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: t.background,
      borderRadius: t.borderRadiusMd,
      border: Border.all(color: t.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Semantics(
              button: allowed,
              label: 'Play $title',
              child: Material(
                color: allowed ? t.primary : t.line,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: allowed ? () => ctx.openUrl(src) : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.play_arrow_rounded, color: t.onPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: t.subtitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: t.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (artwork != null &&
                ctx.urlPolicy.check(artwork) != null) ...<Widget>[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: t.borderRadiusSm,
                child: kletsoImage(ctx, artwork, title, width: 44, height: 44),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 28,
                child: CustomPaint(
                  painter: KletsoWaveformPainter(
                    color: t.primary,
                    muted: t.line,
                  ),
                ),
              ),
            ),
            if (duration != null) ...<Widget>[
              const SizedBox(width: 8),
              Text(KletsoFormat.duration(duration), style: t.caption),
            ],
          ],
        ),
        if (transcript != null) ...<Widget>[
          const SizedBox(height: 8),
          Text('Transcript: $transcript', style: t.caption),
        ],
      ],
    ),
  );
}

/// Deterministic waveform bars.
final class KletsoWaveformPainter extends CustomPainter {
  /// Creates the painter.
  KletsoWaveformPainter({
    required this.color,
    required this.muted,
    this.playedFraction = 0,
  });

  /// Played part colour.
  final Color color;

  /// Remaining part colour.
  final Color muted;

  /// 0..1 progress.
  final double playedFraction;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 48;
    final w = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final h =
          size.height *
          (0.25 +
              0.75 *
                  (0.5 + 0.5 * math.sin(i * 0.9) * math.cos(i * 0.37)).abs());
      final x = i * w + w * 0.25;
      final paint = Paint()..color = i / bars < playedFraction ? color : muted;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w * 0.5, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(KletsoWaveformPainter old) =>
      old.playedFraction != playedFraction || old.color != color;
}

/// Formatting helpers shared by blocks and host widgets.
abstract final class KletsoFormat {
  /// `m:ss` or `h:mm:ss` for a duration in seconds.
  static String duration(num seconds) {
    final s = seconds.round();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }
}
