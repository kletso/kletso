import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'renderer.dart';

/// Dependency-free markdown renderer covering what agents actually emit:
/// paragraphs, `**bold**`, `*italic*`, `` `code` ``, fenced code blocks,
/// `#` headings, `-`/`1.` lists, `> quotes`, `---` rules and `[links](url)`.
/// Inline HTML is shown as text, never interpreted. Images render as their
/// alt text unless [KletsoMarkdownRequest.allowImage] permits the URL.
///
/// Wasm-clean and tiny; hosts wanting tables or LaTeX can plug in another
/// [KletsoMarkdownRenderer].
final class KletsoPlainMarkdownRenderer implements KletsoMarkdownRenderer {
  /// Creates the renderer.
  const KletsoPlainMarkdownRenderer();

  @override
  Widget build(BuildContext context, KletsoMarkdownRequest request) {
    final blocks = _parseBlocks(request.markdown);
    final widgets = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (i > 0) widgets.add(const SizedBox(height: 8));
      widgets.add(_buildBlock(block, request));
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    if (widgets.length == 1) return widgets.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildBlock(_Block block, KletsoMarkdownRequest r) {
    final t = r.theme;
    switch (block.kind) {
      case _BlockKind.heading:
        final size = switch (block.level) {
          1 => 20.0,
          2 => 18.0,
          _ => 16.0,
        };
        return Text.rich(
          _inline(block.text, r, t.title.copyWith(fontSize: size)),
          style: t.title.copyWith(fontSize: size),
        );
      case _BlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: BorderRadius.circular(t.radiusSm),
            border: Border.all(color: t.line),
          ),
          child: SelectableText(block.text, style: t.code),
        );
      case _BlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.line, width: 3)),
          ),
          child: Text.rich(
            _inline(block.text, r, t.body.copyWith(color: t.textMuted)),
            style: t.body.copyWith(color: t.textMuted),
          ),
        );
      case _BlockKind.rule:
        return Container(height: 1, color: t.line);
      case _BlockKind.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < block.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 24,
                      child: Text(
                        block.ordered ? '${i + 1}.' : '•',
                        style: t.body,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        _inline(block.items[i], r, t.body),
                        style: t.body,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case _BlockKind.paragraph:
        return Text.rich(_inline(block.text, r, t.body), style: t.body);
    }
  }

  // ---- inline ---------------------------------------------------------------

  static final RegExp _inlinePattern = RegExp(
    r'(`[^`]+`)|(\*\*[^*]+\*\*)|(__[^_]+__)|(\*[^*\s][^*]*\*)|(_[^_\s][^_]*_)|(!\[[^\]]*\]\([^)\s]+\))|(\[[^\]]+\]\([^)\s]+\))',
  );

  TextSpan _inline(String text, KletsoMarkdownRequest r, TextStyle base) {
    final t = r.theme;
    final spans = <InlineSpan>[];
    var index = 0;
    for (final m in _inlinePattern.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start)));
      }
      final s = m.group(0)!;
      if (s.startsWith('`')) {
        spans.add(
          TextSpan(
            text: s.substring(1, s.length - 1),
            style: t.code.copyWith(backgroundColor: t.background),
          ),
        );
      } else if (s.startsWith('**') || s.startsWith('__')) {
        spans.add(
          TextSpan(
            text: s.substring(2, s.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (s.startsWith('![')) {
        final alt = s.substring(2, s.indexOf(']'));
        final url = s.substring(s.indexOf('(') + 1, s.length - 1);
        if (r.allowImage?.call(url) ?? false) {
          spans.add(
            WidgetSpan(
              child: Image.network(
                url,
                semanticLabel: alt,
                errorBuilder: (_, _, _) => Text(alt, style: base),
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: alt));
        }
      } else if (s.startsWith('[')) {
        final label = s.substring(1, s.indexOf(']'));
        final url = s.substring(s.indexOf('(') + 1, s.length - 1);
        spans.add(
          TextSpan(
            text: label,
            style: TextStyle(
              color: t.primary,
              decoration: TextDecoration.underline,
              decorationColor: t.primary,
            ),
            recognizer: TapGestureRecognizer()..onTap = () => r.onLinkTap(url),
            semanticsLabel: '$label, link',
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: s.substring(1, s.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      index = m.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return TextSpan(style: base, children: spans);
  }

  // ---- blocks ---------------------------------------------------------------

  static List<_Block> _parseBlocks(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];
    final para = <String>[];
    void flushPara() {
      if (para.isEmpty) return;
      blocks.add(_Block.paragraph(para.join(' ').trim()));
      para.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushPara();
        i++;
        continue;
      }
      if (trimmed.startsWith('```')) {
        flushPara();
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        i++; // closing fence (or end of input while streaming)
        blocks.add(_Block.code(buf.join('\n')));
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushPara();
        blocks.add(_Block.heading(heading.group(1)!.length, heading.group(2)!));
        i++;
        continue;
      }
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        flushPara();
        blocks.add(const _Block.rule());
        i++;
        continue;
      }
      if (trimmed.startsWith('>')) {
        flushPara();
        final buf = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          buf.add(lines[i].trim().substring(1).trim());
          i++;
        }
        blocks.add(_Block.quote(buf.join(' ')));
        continue;
      }
      final bullet = RegExp(r'^([-*+]|\d+[.)])\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flushPara();
        final ordered = RegExp(r'^\d').hasMatch(bullet.group(1)!);
        final items = <String>[];
        while (i < lines.length) {
          final m = RegExp(
            r'^([-*+]|\d+[.)])\s+(.*)$',
          ).firstMatch(lines[i].trim());
          if (m == null) break;
          items.add(m.group(2)!);
          i++;
        }
        blocks.add(_Block.list(items, ordered: ordered));
        continue;
      }
      para.add(trimmed);
      i++;
    }
    flushPara();
    return blocks;
  }
}

enum _BlockKind { paragraph, heading, code, quote, rule, list }

final class _Block {
  const _Block._(
    this.kind, {
    this.text = '',
    this.level = 0,
    this.items = const <String>[],
    this.ordered = false,
  });
  const _Block.paragraph(String text)
    : this._(_BlockKind.paragraph, text: text);
  const _Block.heading(int level, String text)
    : this._(_BlockKind.heading, text: text, level: level);
  const _Block.code(String text) : this._(_BlockKind.code, text: text);
  const _Block.quote(String text) : this._(_BlockKind.quote, text: text);
  const _Block.rule() : this._(_BlockKind.rule);
  const _Block.list(List<String> items, {required bool ordered})
    : this._(_BlockKind.list, items: items, ordered: ordered);
  final _BlockKind kind;
  final String text;
  final int level;
  final List<String> items;
  final bool ordered;
}
