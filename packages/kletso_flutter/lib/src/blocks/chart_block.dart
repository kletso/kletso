import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../registry/build_context.dart';
import '../theme/kletso_theme.dart';

/// `chart`: bar, line or pie drawn with a `CustomPainter`; no dependency.
Widget buildChartBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final series = node
      .mapList('series')
      .map(KletsoChartSeries.fromJson)
      .where((s) => s.points.isNotEmpty)
      .toList();
  final type = node.string('chartType', fallback: 'bar');
  final title = node.stringOrNull('title');
  final currency = node.stringOrNull('currency');
  final palette = <Color>[t.primary, t.info, t.success, t.warning, t.text];
  final label = StringBuffer(title ?? 'Chart');
  for (final s in series) {
    label.write(
      '. ${s.name}: ${s.points.map((p) => '${p.x} ${_fmt(p.y, currency)}').join(', ')}',
    );
  }
  return Semantics(
    label: label.toString(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Text(title, style: t.subtitle),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 180,
          child: series.isEmpty
              ? Center(child: Text('No data', style: t.caption))
              : CustomPaint(
                  painter: KletsoChartPainter(
                    type: type,
                    series: series,
                    palette: palette,
                    theme: t,
                    currency: currency,
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        if (series.length > 1 || type == 'pie') ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              if (type == 'pie')
                for (var i = 0; i < series.first.points.length; i++)
                  _legend(
                    t,
                    palette[i % palette.length],
                    '${series.first.points[i].x}',
                  )
              else
                for (var i = 0; i < series.length; i++)
                  _legend(t, palette[i % palette.length], series[i].name),
            ],
          ),
        ],
        if (node.stringOrNull('xLabel') != null ||
            node.stringOrNull('yLabel') != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              <String>[
                if (node.stringOrNull('xLabel') != null)
                  'x: ${node.string('xLabel')}',
                if (node.stringOrNull('yLabel') != null)
                  'y: ${node.string('yLabel')}',
              ].join(' · '),
              style: t.caption,
            ),
          ),
      ],
    ),
  );
}

Widget _legend(KletsoTheme t, Color c, String name) => Row(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    ),
    const SizedBox(width: 6),
    Text(name, style: t.caption),
  ],
);

String _fmt(num v, String? currency) {
  final abs = v.abs();
  String n;
  if (abs >= 1000000) {
    n = '${(v / 1000000).toStringAsFixed(1)}M';
  } else if (abs >= 1000) {
    n = '${(v / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
  } else {
    n = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }
  return currency == null ? n : '$currency $n';
}

/// One data point.
final class KletsoChartPoint {
  /// Creates a point.
  const KletsoChartPoint(this.x, this.y);

  /// Category or x value.
  final Object x;

  /// Numeric value.
  final num y;
}

/// One series.
final class KletsoChartSeries {
  /// Creates a series.
  const KletsoChartSeries(this.name, this.points);

  /// Reads `{name, data:[{x,y}]}`; non-numeric points are skipped.
  factory KletsoChartSeries.fromJson(JsonMap json) {
    final points = <KletsoChartPoint>[];
    final data = json['data'];
    if (data is List) {
      for (final p in data.take(200)) {
        if (p is Map && p['y'] is num) {
          points.add(
            KletsoChartPoint((p['x'] as Object?) ?? '', p['y']! as num),
          );
        }
      }
    }
    return KletsoChartSeries(json['name'] as String? ?? '', points);
  }

  /// Series label.
  final String name;

  /// Points in order.
  final List<KletsoChartPoint> points;
}

/// Paints bar, line and pie charts from theme colours only.
final class KletsoChartPainter extends CustomPainter {
  /// Creates the painter.
  KletsoChartPainter({
    required this.type,
    required this.series,
    required this.palette,
    required this.theme,
    this.currency,
  });

  /// `bar`, `line` or `pie`.
  final String type;

  /// Data.
  final List<KletsoChartSeries> series;

  /// Series colours.
  final List<Color> palette;

  /// Theme for axes and labels.
  final KletsoTheme theme;

  /// Currency code for value labels.
  final String? currency;

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case 'pie':
        _paintPie(canvas, size);
      case 'line':
        _paintCartesian(canvas, size, line: true);
      default:
        _paintCartesian(canvas, size, line: false);
    }
  }

  TextPainter _text(String s, TextStyle style, {double maxWidth = 200}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return tp;
  }

  void _paintCartesian(Canvas canvas, Size size, {required bool line}) {
    final labelStyle = theme.caption.copyWith(fontSize: 10);
    const left = 40.0;
    const bottom = 20.0;
    final plot = Rect.fromLTRB(left, 6, size.width - 4, size.height - bottom);
    final categories = <String>[];
    for (final s in series) {
      for (final p in s.points) {
        final x = '${p.x}';
        if (!categories.contains(x)) categories.add(x);
      }
    }
    if (categories.isEmpty) return;
    var maxY = 0.0;
    var minY = 0.0;
    for (final s in series) {
      for (final p in s.points) {
        maxY = math.max(maxY, p.y.toDouble());
        minY = math.min(minY, p.y.toDouble());
      }
    }
    if (maxY == minY) maxY = minY + 1;
    final niceMax = _nice(maxY);
    final niceMin = minY < 0 ? -_nice(-minY) : 0.0;
    double yFor(num v) =>
        plot.bottom - (v - niceMin) / (niceMax - niceMin) * plot.height;

    final grid = Paint()
      ..color = theme.line
      ..strokeWidth = 1;
    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final v = niceMin + (niceMax - niceMin) * i / ticks;
      final y = yFor(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = _text(_fmt(v, null), labelStyle, maxWidth: left - 4);
      tp.paint(canvas, Offset(left - 4 - tp.width, y - tp.height / 2));
    }
    final slot = plot.width / categories.length;
    for (var i = 0; i < categories.length; i++) {
      final tp = _text(categories[i], labelStyle, maxWidth: slot - 2);
      tp.paint(
        canvas,
        Offset(plot.left + slot * i + (slot - tp.width) / 2, plot.bottom + 4),
      );
    }
    if (line) {
      for (var si = 0; si < series.length; si++) {
        final color = palette[si % palette.length];
        final path = Path();
        final dots = <Offset>[];
        for (final p in series[si].points) {
          final ci = categories.indexOf('${p.x}');
          final o = Offset(plot.left + slot * ci + slot / 2, yFor(p.y));
          dots.add(o);
          if (dots.length == 1) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        for (final o in dots) {
          canvas.drawCircle(o, 3.5, Paint()..color = theme.surface);
          canvas.drawCircle(
            o,
            3.5,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }
    } else {
      final groups = series.length;
      final groupWidth = slot * 0.7;
      final barWidth = groupWidth / groups;
      for (var si = 0; si < groups; si++) {
        final color = palette[si % palette.length];
        for (final p in series[si].points) {
          final ci = categories.indexOf('${p.x}');
          final x0 =
              plot.left + slot * ci + (slot - groupWidth) / 2 + barWidth * si;
          final top = yFor(math.max(p.y, 0));
          final base = yFor(math.min(p.y, 0));
          final r = RRect.fromRectAndCorners(
            Rect.fromLTRB(x0 + 1, top, x0 + barWidth - 1, base),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          );
          canvas.drawRRect(r, Paint()..color = color);
        }
      }
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final points = series.first.points;
    final total = points.fold<double>(
      0,
      (a, p) => a + math.max(0, p.y.toDouble()),
    );
    if (total <= 0) return;
    final radius = math.min(size.width, size.height) / 2 - 4;
    final center = Offset(size.width / 2, size.height / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < points.length; i++) {
      final sweep = math.max(0, points[i].y.toDouble()) / total * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        Paint()..color = palette[i % palette.length],
      );
      start += sweep;
    }
    canvas.drawCircle(center, radius * 0.55, Paint()..color = theme.surface);
    final tp = _text(_fmt(total, currency), theme.subtitle, maxWidth: radius);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static double _nice(double v) {
    if (v <= 0) return 1;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / exp;
    final nf = f <= 1
        ? 1
        : f <= 2
        ? 2
        : f <= 2.5
        ? 2.5
        : f <= 5
        ? 5
        : 10;
    return nf * exp;
  }

  @override
  bool shouldRepaint(KletsoChartPainter old) =>
      old.type != type ||
      old.series != series ||
      old.theme != theme ||
      old.palette != palette;
}
