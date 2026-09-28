import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../markdown/renderer.dart';
import '../registry/build_context.dart';
import '../surface/surface_view.dart';
import '../theme/kletso_theme.dart';
import 'support.dart';

/// `rating`: stars; when `interactive`, tapping a star fires the node's
/// first action with `{rating: n}` merged into the value.
Widget buildRatingBlock(KletsoBuildContext ctx, KletsoNode node) =>
    _RatingBlock(ctx: ctx, node: node);

final class _RatingBlock extends StatefulWidget {
  const _RatingBlock({required this.ctx, required this.node});
  final KletsoBuildContext ctx;
  final KletsoNode node;
  @override
  State<_RatingBlock> createState() => _RatingBlockState();
}

final class _RatingBlockState extends State<_RatingBlock> {
  double? _chosen;

  @override
  Widget build(BuildContext context) {
    final t = widget.ctx.theme;
    final node = widget.node;
    final max = node.number('max', fallback: 5).toInt().clamp(1, 10);
    final value = _chosen ?? node.number('value').toDouble();
    final count = node.numberOrNull('count');
    final label = node.stringOrNull('label');
    final interactive = node.boolean('interactive');
    final action = node.actions
        .where((a) => a is! KletsoUnknownAction)
        .firstOrNull;
    return Semantics(
      label:
          '${label ?? 'Rating'}: $value of $max${count == null ? '' : ', $count ratings'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Text(label, style: t.caption),
            const SizedBox(height: 2),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 1; i <= max; i++)
                GestureDetector(
                  onTap: interactive
                      ? () {
                          setState(() => _chosen = i.toDouble());
                          if (action != null) {
                            unawaited(
                              widget.ctx.execute(
                                action,
                                args: <String, Object?>{'rating': i},
                              ),
                            );
                          }
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      value >= i
                          ? Icons.star_rounded
                          : (value >= i - 0.5
                                ? Icons.star_half_rounded
                                : Icons.star_outline_rounded),
                      size: interactive ? 30 : 20,
                      color: value >= i - 0.5 ? t.warning : t.line,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              if (!interactive)
                Text(value.toStringAsFixed(1), style: t.subtitle),
              if (count != null) Text(' ($count)', style: t.caption),
            ],
          ),
        ],
      ),
    );
  }
}

/// `steps`: a timeline with done / current / upcoming / failed states.
Widget buildStepsBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final items = node.mapList('items');
  final title = node.stringOrNull('title');
  final horizontal =
      node.string('orientation', fallback: 'vertical') == 'horizontal';
  (Color, IconData) look(String status) => switch (status) {
    'done' => (t.success, Icons.check_circle_rounded),
    'current' => (t.primary, Icons.radio_button_checked),
    'failed' => (t.error, Icons.cancel_rounded),
    _ => (t.line, Icons.radio_button_unchecked),
  };
  if (horizontal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Text(title, style: t.subtitle),
          const SizedBox(height: 8),
        ],
        Row(
          children: <Widget>[
            for (var i = 0; i < items.length; i++) ...<Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Icon(
                      look(items[i]['status'] as String? ?? 'upcoming').$2,
                      color: look(
                        items[i]['status'] as String? ?? 'upcoming',
                      ).$1,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i]['title'] as String? ?? '',
                      style: t.caption,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (i < items.length - 1)
                Container(
                  width: 16,
                  height: 2,
                  color: (items[i]['status'] == 'done') ? t.success : t.line,
                ),
            ],
          ],
        ),
      ],
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (title != null) ...<Widget>[
        Text(title, style: t.subtitle),
        const SizedBox(height: 8),
      ],
      for (var i = 0; i < items.length; i++)
        _Step(
          theme: t,
          item: items[i],
          look: look(items[i]['status'] as String? ?? 'upcoming'),
          last: i == items.length - 1,
          lineColor: (items[i]['status'] == 'done') ? t.success : t.line,
        ),
    ],
  );
}

final class _Step extends StatelessWidget {
  const _Step({
    required this.theme,
    required this.item,
    required this.look,
    required this.last,
    required this.lineColor,
  });
  final KletsoTheme theme;
  final JsonMap item;
  final (Color, IconData) look;
  final bool last;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final current = item['status'] == 'current';
    return MergeSemantics(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Column(
              children: <Widget>[
                Icon(look.$2, color: look.$1, size: 22),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: lineColor,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item['title'] as String? ?? '',
                            style: current
                                ? t.subtitle
                                : t.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (item['timestamp'] is String)
                          Text(item['timestamp'] as String, style: t.caption),
                      ],
                    ),
                    if (item['subtitle'] is String)
                      Text(item['subtitle'] as String, style: t.caption),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `accordion`: expandable sections with markdown or child components.
Widget buildAccordionBlock(KletsoBuildContext ctx, KletsoNode node) =>
    _Accordion(ctx: ctx, node: node);

final class _Accordion extends StatefulWidget {
  const _Accordion({required this.ctx, required this.node});
  final KletsoBuildContext ctx;
  final KletsoNode node;
  @override
  State<_Accordion> createState() => _AccordionState();
}

final class _AccordionState extends State<_Accordion> {
  late final Set<String> _open = <String>{
    for (final i in widget.node.mapList('items'))
      if (i['expanded'] == true) i['id'] as String? ?? '',
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.ctx.theme;
    final items = widget.node.mapList('items');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: t.borderRadiusMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) Container(height: 1, color: t.line),
            _section(items[i], t),
          ],
        ],
      ),
    );
  }

  Widget _section(JsonMap item, KletsoTheme t) {
    final id = item['id'] as String? ?? '';
    final open = _open.contains(id);
    final children =
        (item['children'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final md = item['markdown'] as String?;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: open,
          label: item['title'] as String? ?? '',
          child: InkWell(
            onTap: () =>
                setState(() => open ? _open.remove(id) : _open.add(id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item['title'] as String? ?? '',
                      style: t.subtitle,
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more, color: t.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (md != null)
                  widget.ctx.markdownRenderer.build(
                    context,
                    KletsoMarkdownRequest(
                      markdown: md,
                      theme: t,
                      onLinkTap: (url) => widget.ctx.openUrl(url),
                      allowImage: (url) =>
                          widget.ctx.urlPolicy.check(url) != null,
                    ),
                  ),
                for (final c in children)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: widget.ctx.child(c),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// `tabs`: tab strip over per-tab children.
Widget buildTabsBlock(KletsoBuildContext ctx, KletsoNode node) =>
    _Tabs(ctx: ctx, node: node);

final class _Tabs extends StatefulWidget {
  const _Tabs({required this.ctx, required this.node});
  final KletsoBuildContext ctx;
  final KletsoNode node;
  @override
  State<_Tabs> createState() => _TabsState();
}

final class _TabsState extends State<_Tabs> {
  late String _selected =
      widget.node.stringOrNull('initial') ??
      (widget.node.mapList('items').firstOrNull?['id'] as String? ?? '');

  @override
  Widget build(BuildContext context) {
    final t = widget.ctx.theme;
    final items = widget.node.mapList('items');
    final current =
        items.where((i) => i['id'] == _selected).firstOrNull ??
        items.firstOrNull;
    final children =
        (current?['children'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(i['label'] as String? ?? ''),
                    avatar: kletsoIcon(i['icon'] as String?) == null
                        ? null
                        : Icon(
                            kletsoIcon(i['icon'] as String?),
                            size: 16,
                            color: i['id'] == _selected
                                ? t.primary
                                : t.textMuted,
                          ),
                    selected: i['id'] == _selected,
                    onSelected: (_) =>
                        setState(() => _selected = i['id'] as String? ?? ''),
                    selectedColor: t.primarySoft,
                    backgroundColor: t.surface,
                    labelStyle: t.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: i['id'] == _selected ? t.primary : t.text,
                    ),
                    side: BorderSide(
                      color: i['id'] == _selected ? t.primary : t.line,
                    ),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.radiusPill),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var k = 0; k < children.length; k++)
          Padding(
            padding: EdgeInsets.only(top: k == 0 ? 0 : 10),
            child: widget.ctx.child(children[k]),
          ),
      ],
    );
  }
}

/// `countdown`: ticks once a second until `endsAt`; the timer is disposed
/// with the widget and paused when reduced motion is requested.
Widget buildCountdownBlock(KletsoBuildContext ctx, KletsoNode node) =>
    KletsoCountdown(
      endsAt: DateTime.tryParse(node.string('endsAt'))?.toUtc(),
      label: node.stringOrNull('label'),
      expiredLabel: node.string('expiredLabel', fallback: 'Time is up'),
      tone: node.string('tone', fallback: 'neutral'),
    );

/// Live countdown widget (also usable by hosts).
final class KletsoCountdown extends StatefulWidget {
  /// Creates a countdown to [endsAt].
  const KletsoCountdown({
    required this.endsAt,
    super.key,
    this.label,
    this.expiredLabel = 'Time is up',
    this.tone = 'neutral',
    this.now,
  });

  /// Target instant (UTC); `null` renders the expired label.
  final DateTime? endsAt;

  /// Text above the digits.
  final String? label;

  /// Text once the target has passed.
  final String expiredLabel;

  /// Colour tone.
  final String tone;

  /// Clock override for tests.
  final DateTime Function()? now;

  @override
  State<KletsoCountdown> createState() => _KletsoCountdownState();
}

final class _KletsoCountdownState extends State<KletsoCountdown> {
  Timer? _timer;
  late Duration _left = _remaining();

  Duration _remaining() {
    final end = widget.endsAt;
    if (end == null) return Duration.zero;
    final d = end.difference((widget.now ?? DateTime.now)().toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _remaining();
      if (next != _left && mounted) setState(() => _left = next);
      if (next == Duration.zero) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final (bg, fg) = kletsoTone(t, widget.tone);
    final expired = _left == Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final d = _left.inDays;
    final parts = <(String, String)>[
      if (d > 0) ('$d', d == 1 ? 'day' : 'days'),
      (two(_left.inHours % 24), 'hrs'),
      (two(_left.inMinutes % 60), 'min'),
      (two(_left.inSeconds % 60), 'sec'),
    ];
    return Semantics(
      liveRegion: true,
      label: expired
          ? widget.expiredLabel
          : '${widget.label ?? 'Time left'}: ${parts.map((p) => '${p.$1} ${p.$2}').join(' ')}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: t.borderRadiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.label != null && !expired)
              Text(widget.label!, style: t.caption.copyWith(color: fg)),
            if (expired)
              Text(widget.expiredLabel, style: t.subtitle.copyWith(color: fg))
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var i = 0; i < parts.length; i++) ...<Widget>[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(':', style: t.title.copyWith(color: fg)),
                      ),
                    Column(
                      children: <Widget>[
                        Text(
                          parts[i].$1,
                          style: t.title.copyWith(
                            color: fg,
                            fontSize: 22,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        Text(
                          parts[i].$2,
                          style: t.caption.copyWith(color: fg, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// `progress`: determinate bar with label and detail.
Widget buildProgressBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final value = node.number('value').toDouble().clamp(0.0, 1.0);
  final (_, fg) = kletsoTone(t, node.string('tone', fallback: 'neutral'));
  final color = fg == t.text ? t.primary : fg;
  final label = node.stringOrNull('label');
  final detail = node.stringOrNull('detail');
  return Semantics(
    label:
        '${label ?? 'Progress'} ${(value * 100).round()} percent${detail == null ? '' : ', $detail'}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null || detail != null)
          Row(
            children: <Widget>[
              if (label != null) Expanded(child: Text(label, style: t.caption)),
              if (detail != null) Text(detail, style: t.caption),
            ],
          ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(t.radiusPill),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: t.line,
            color: color,
          ),
        ),
      ],
    ),
  );
}
