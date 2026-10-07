import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../avatar/avatar_controller.dart';
import '../avatar/kletso_avatar.dart';
import '../markdown/renderer.dart';
import '../registry/ui_bindings.dart';
import '../surface/surface_view.dart';
import '../theme/kletso_theme.dart';

/// A user message bubble (right-aligned, tinted).
final class KletsoUserBubble extends StatelessWidget {
  /// Creates the bubble.
  const KletsoUserBubble({required this.message, super.key});

  /// The message.
  final KletsoMessage message;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final pending = message.status == KletsoMessageStatus.pending;
    final failed = message.status == KletsoMessageStatus.failed;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Opacity(
              opacity: pending ? 0.7 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: failed ? t.errorSoft : t.bubbleUser,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(t.radiusLg),
                    topRight: Radius.circular(t.radiusLg),
                    bottomLeft: Radius.circular(t.radiusLg),
                    bottomRight: Radius.circular(t.radiusSm),
                  ),
                ),
                child: Text(
                  message.text.isEmpty ? '…' : message.text,
                  style: t.body.copyWith(color: failed ? t.error : t.text),
                ),
              ),
            ),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  'Not delivered',
                  style: t.caption.copyWith(color: t.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An assistant message: streamed markdown text, tool-call chips and the
/// surfaces rendered under it, inside one bot bubble.
final class KletsoBotBubble extends StatelessWidget {
  /// Creates the bubble.
  const KletsoBotBubble({
    required this.message,
    required this.markdownRenderer,
    super.key,
    this.client,
    this.showAvatar = true,
    this.avatarController,
  });

  /// The message.
  final KletsoMessage message;

  /// Renders the text.
  final KletsoMarkdownRenderer markdownRenderer;

  /// The live client for surface actions; `null` in previews.
  final KletsoClient? client;

  /// Whether to draw the avatar dot.
  final bool showAvatar;

  /// Drives the small avatar's mood; `null` shows a static neutral face.
  final KletsoAvatarController? avatarController;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final streaming = message.status == KletsoMessageStatus.streaming;
    final hasText = message.text.isNotEmpty;
    final children = <Widget>[];
    if (message.toolCalls.isNotEmpty) {
      children.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: message.toolCalls
              .map((c) => KletsoToolCallChip(call: c))
              .toList(),
        ),
      );
    }
    if (hasText) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        markdownRenderer.build(
          context,
          KletsoMarkdownRequest(
            markdown: message.text,
            theme: t,
            streaming: streaming,
            onLinkTap: (url) => client?.ui.dispatcher.openUrl(url),
            allowImage: (url) => client?.ui.urlPolicy.check(url) != null,
          ),
        ),
      );
    } else if (streaming &&
        message.toolCalls.isEmpty &&
        message.surfaces.isEmpty) {
      children.add(const KletsoTypingDots());
    }
    if (message.error != null && message.status == KletsoMessageStatus.failed) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 16, color: t.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message.error!.message,
                style: t.caption.copyWith(color: t.error),
              ),
            ),
          ],
        ),
      );
    }
    for (final surface in message.surfaces) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        KletsoSurfaceView(
          key: ValueKey<String>(surface.surfaceId),
          surface: surface,
          client: client,
          markdownRenderer: markdownRenderer,
          streaming: streaming,
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (showAvatar) ...<Widget>[
            KletsoAvatar(
              controller: avatarController,
              size: 24,
              animate: false,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: t.bubbleBot,
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(t.radiusLg),
                    topRight: Radius.circular(t.radiusLg),
                    bottomRight: Radius.circular(t.radiusLg),
                    bottomLeft: Radius.circular(t.radiusSm),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tool call status chip ("Searching flights…", "Done").
final class KletsoToolCallChip extends StatelessWidget {
  /// Creates the chip.
  const KletsoToolCallChip({required this.call, super.key});

  /// The tool call.
  final KletsoToolCall call;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final name = call.name.replaceAll('_', ' ');
    final (Widget icon, String text, Color bg) = switch (call.status) {
      KletsoToolCallStatus.running => (
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: t.primary),
        ),
        '$name…',
        t.background,
      ),
      KletsoToolCallStatus.awaitingConfirmation => (
        Icon(Icons.pause_circle_outline, size: 14, color: t.text),
        '$name · waiting for you',
        t.warningSoft,
      ),
      KletsoToolCallStatus.completed => (
        Icon(Icons.check_circle_outline, size: 14, color: t.success),
        name,
        t.successSoft,
      ),
      KletsoToolCallStatus.failed => (
        Icon(Icons.error_outline, size: 14, color: t.error),
        '$name failed',
        t.errorSoft,
      ),
    };
    return Semantics(
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(t.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(width: 6),
            Text(text, style: t.caption),
          ],
        ),
      ),
    );
  }
}

/// Three bouncing dots; stops animating when reduced motion is requested.
final class KletsoTypingDots extends StatefulWidget {
  /// Creates the indicator.
  const KletsoTypingDots({super.key});

  @override
  State<KletsoTypingDots> createState() => _KletsoTypingDotsState();
}

final class _KletsoTypingDotsState extends State<KletsoTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce && _c.isAnimating) _c.stop();
    return Semantics(
      label: 'Assistant is typing',
      child: SizedBox(
        height: 20,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      reduce ? 0 : -4 * _bounce((_c.value + i * 0.2) % 1),
                    ),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: t.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static double _bounce(double v) => v < 0.5 ? (v * 2) : (2 - v * 2);
}
