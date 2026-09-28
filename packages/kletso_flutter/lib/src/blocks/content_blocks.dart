import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../markdown/renderer.dart';
import '../registry/build_context.dart';
import '../surface/surface_view.dart';
import 'support.dart';

/// `text`: plain text with a style role and colour role.
Widget buildTextBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  var style = switch (node.string('style', fallback: 'body')) {
    'title' => t.title,
    'caption' => t.caption,
    'code' => t.code,
    _ => t.body,
  };
  style = switch (node.string('color', fallback: 'default')) {
    'muted' => style.copyWith(color: t.textMuted),
    'success' => style.copyWith(color: t.success),
    'error' => style.copyWith(color: t.error),
    _ => style,
  };
  return Text(node.string('text'), style: style);
}

/// `markdown`: through the renderer; links go through the URL policy.
Widget buildMarkdownBlock(KletsoBuildContext ctx, KletsoNode node) =>
    ctx.markdownRenderer.build(
      ctx.context,
      KletsoMarkdownRequest(
        markdown: node.string('markdown'),
        theme: ctx.theme,
        onLinkTap: (url) => ctx.openUrl(url),
        streaming: ctx.isStreaming,
        allowImage: (url) => ctx.urlPolicy.check(url) != null,
      ),
    );

/// `image`: allowlisted network image with aspect ratio.
Widget buildImageBlock(KletsoBuildContext ctx, KletsoNode node) => ClipRRect(
  borderRadius: ctx.theme.borderRadiusMd,
  child: AspectRatio(
    aspectRatio: kletsoAspect(node.string('aspect', fallback: '16:9')),
    child: kletsoImage(
      ctx,
      node.string('src'),
      node.string('alt', fallback: 'image'),
      fit: node.string('fit', fallback: 'cover') == 'contain'
          ? BoxFit.contain
          : BoxFit.cover,
    ),
  ),
);

/// `avatar`: image or initials in a circle.
Widget buildAvatarBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final size = switch (node.string('size', fallback: 'md')) {
    'sm' => 28.0,
    'lg' => 56.0,
    _ => 40.0,
  };
  final src = node.stringOrNull('src');
  final initials = node.string('initials');
  return ClipOval(
    child: Container(
      width: size,
      height: size,
      color: t.primarySoft,
      alignment: Alignment.center,
      child: src != null && ctx.urlPolicy.check(src) != null
          ? kletsoImage(
              ctx,
              src,
              initials.isEmpty ? 'avatar' : initials,
              width: size,
              height: size,
            )
          : Text(
              initials,
              style: t.subtitle.copyWith(
                color: t.primary,
                fontSize: size * 0.4,
              ),
            ),
    ),
  );
}

/// `button`: fires the node's first action.
Widget buildButtonBlock(KletsoBuildContext ctx, KletsoNode node) {
  final action = node.actions
      .where((a) => a is! KletsoUnknownAction)
      .firstOrNull;
  final disabled = node.boolean('disabled') || action == null;
  return KletsoButton(
    label: node.string('label', fallback: 'Button'),
    variant: node.string('variant', fallback: 'primary'),
    icon: node.stringOrNull('icon'),
    onPressed: disabled ? null : () => ctx.execute(action),
  );
}

/// `badge`: small tinted label.
Widget buildBadgeBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final (bg, fg) = kletsoTone(t, node.string('tone', fallback: 'neutral'));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(t.radiusPill),
    ),
    child: Text(
      node.string('label'),
      style: t.caption.copyWith(
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );
}

/// `link`: tappable text to an allowlisted URL.
Widget buildLinkBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final url = node.string('url');
  final allowed = ctx.urlPolicy.check(url) != null;
  return Semantics(
    link: allowed,
    label: node.string('label'),
    child: InkWell(
      onTap: allowed ? () => ctx.openUrl(url) : null,
      child: Text(
        node.string('label', fallback: url),
        style: t.body.copyWith(
          color: allowed ? t.primary : t.textMuted,
          decoration: allowed
              ? TextDecoration.underline
              : TextDecoration.lineThrough,
          decorationColor: t.primary,
        ),
      ),
    ),
  );
}

/// `list`: items with optional leading image/icon, trailing text/badge and
/// per-item actions (tap fires the first).
Widget buildListBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final items = node.mapList('items');
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (var i = 0; i < items.length; i++) ...<Widget>[
        if (i > 0) Container(height: 1, color: t.line),
        _ListItem(ctx: ctx, item: items[i]),
      ],
    ],
  );
}

final class _ListItem extends StatelessWidget {
  const _ListItem({required this.ctx, required this.item});
  final KletsoBuildContext ctx;
  final JsonMap item;

  @override
  Widget build(BuildContext context) {
    final t = ctx.theme;
    final title = item['title'] as String? ?? '';
    final subtitle = item['subtitle'] as String?;
    final leading = item['leading'] is Map
        ? (item['leading']! as Map).cast<String, Object?>()
        : null;
    final trailing = item['trailing'] is Map
        ? (item['trailing']! as Map).cast<String, Object?>()
        : null;
    final rawActions = item['actions'];
    KletsoAction? action;
    if (rawActions is List && rawActions.isNotEmpty) {
      try {
        action = KletsoAction.fromJson(rawActions.first);
        if (action is KletsoUnknownAction) action = null;
      } on KletsoSchemaException {
        action = null;
      }
    }
    Widget? lead;
    if (leading != null) {
      final img = leading['image'] as String?;
      final icon = kletsoIcon(leading['icon'] as String?);
      if (img != null) {
        lead = ClipRRect(
          borderRadius: t.borderRadiusSm,
          child: kletsoImage(ctx, img, title, width: 44, height: 44),
        );
      } else if (icon != null) {
        lead = Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.primarySoft,
            borderRadius: t.borderRadiusSm,
          ),
          child: Icon(icon, color: t.primary, size: 22),
        );
      }
    }
    Widget? trail;
    if (trailing != null) {
      final badge = trailing['badge'] as String?;
      final text = trailing['text'] as String?;
      if (badge != null) {
        final (bg, fg) = kletsoTone(
          t,
          trailing['tone'] as String? ?? 'neutral',
        );
        trail = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(t.radiusPill),
          ),
          child: Text(
            badge,
            style: t.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
          ),
        );
      } else if (text != null) {
        trail = Text(text, style: t.subtitle);
      }
    }
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          if (lead != null) ...<Widget>[lead, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: t.subtitle),
                if (subtitle != null) Text(subtitle, style: t.caption),
              ],
            ),
          ),
          if (trail != null) ...<Widget>[const SizedBox(width: 12), trail],
          if (action != null) ...<Widget>[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: t.textMuted),
          ],
        ],
      ),
    );
    final act = action;
    return MergeSemantics(
      child: act == null
          ? row
          : InkWell(
              onTap: () => ctx.execute(act),
              borderRadius: t.borderRadiusSm,
              child: row,
            ),
    );
  }
}

/// `table`: columns and up to 50 rows.
Widget buildTableBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final columns = node.mapList('columns');
  final rows = node.mapList('rows').take(50).toList(growable: false);
  final caption = node.stringOrNull('caption');
  TextAlign align(JsonMap c) => switch (c['align']) {
    'end' => TextAlign.end,
    'center' => TextAlign.center,
    _ => TextAlign.start,
  };
  Widget cell(String text, TextStyle style, TextAlign a) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Text(text, style: style, textAlign: a),
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(caption, style: t.subtitle),
        ),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
          borderRadius: t.borderRadiusSm,
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(horizontalInside: BorderSide(color: t.line)),
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(color: t.background),
                children: <Widget>[
                  for (final c in columns)
                    cell(
                      c['label'] as String? ?? '',
                      t.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                      align(c),
                    ),
                ],
              ),
              for (final r in rows)
                TableRow(
                  children: <Widget>[
                    for (final c in columns)
                      cell('${r[c['key']] ?? ''}', t.body, align(c)),
                  ],
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// `loading`: spinner with optional label.
Widget buildLoadingBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: t.primary),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          node.string('label', fallback: 'Working…'),
          style: t.caption,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// `error`: message with an optional retry (the node's first action).
Widget buildErrorBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final action = node.actions
      .where((a) => a is! KletsoUnknownAction)
      .firstOrNull;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: t.errorSoft,
      borderRadius: t.borderRadiusMd,
    ),
    child: Row(
      children: <Widget>[
        Icon(Icons.error_outline, color: t.error, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            node.string('message', fallback: 'Something went wrong'),
            style: t.body.copyWith(color: t.error),
          ),
        ),
        if (node.boolean('retryable') && action != null)
          KletsoButton(
            label: 'Retry',
            variant: 'ghost',
            onPressed: () => ctx.execute(action),
          ),
      ],
    ),
  );
}
