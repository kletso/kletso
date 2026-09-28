import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../registry/build_context.dart';
import 'support.dart';

/// `card`: padded surface with optional title/subtitle and children.
Widget buildCardBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final title = node.stringOrNull('title');
  final subtitle = node.stringOrNull('subtitle');
  final children = ctx.children();
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: t.borderRadiusLg,
      border: Border.all(color: t.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (title != null || subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null) Text(title, style: t.title),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.caption),
                ],
              ],
            ),
          ),
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              i == 0 && title == null && subtitle == null ? 16 : 12,
              16,
              i == children.length - 1 ? 16 : 0,
            ),
            child: children[i],
          ),
      ],
    ),
  );
}

CrossAxisAlignment _cross(String align) => switch (align) {
  'center' => CrossAxisAlignment.center,
  'end' => CrossAxisAlignment.end,
  'stretch' => CrossAxisAlignment.stretch,
  _ => CrossAxisAlignment.start,
};

MainAxisAlignment _main(String align) => switch (align) {
  'center' => MainAxisAlignment.center,
  'end' => MainAxisAlignment.end,
  'spaceBetween' => MainAxisAlignment.spaceBetween,
  _ => MainAxisAlignment.start,
};

/// `row`: horizontal layout; `wrap: true` flows onto new lines.
Widget buildRowBlock(KletsoBuildContext ctx, KletsoNode node) {
  final gap = kletsoGap(node.string('gap', fallback: 'md'));
  final align = node.string('align', fallback: 'start');
  final children = ctx.children();
  if (node.boolean('wrap')) {
    return Wrap(spacing: gap, runSpacing: gap, children: children);
  }
  final spaced = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) spaced.add(SizedBox(width: gap));
    spaced.add(Flexible(child: children[i]));
  }
  return Row(
    mainAxisAlignment: _main(align),
    crossAxisAlignment: align == 'center'
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start,
    children: spaced,
  );
}

/// `column`: vertical layout.
Widget buildColumnBlock(KletsoBuildContext ctx, KletsoNode node) {
  final gap = kletsoGap(node.string('gap', fallback: 'md'));
  final children = ctx.children();
  final spaced = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) spaced.add(SizedBox(height: gap));
    spaced.add(children[i]);
  }
  return Column(
    crossAxisAlignment: _cross(node.string('align', fallback: 'stretch')),
    mainAxisSize: MainAxisSize.min,
    children: spaced,
  );
}

/// `divider`.
Widget buildDividerBlock(KletsoBuildContext ctx, KletsoNode node) =>
    Container(height: 1, color: ctx.theme.line);

/// `carousel`: horizontal scroller of children.
Widget buildCarouselBlock(KletsoBuildContext ctx, KletsoNode node) {
  final children = ctx.children();
  return SizedBox(
    height: 270,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, i) => SizedBox(width: 240, child: children[i]),
    ),
  );
}
