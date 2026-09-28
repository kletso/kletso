import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../theme/kletso_theme.dart';

/// Thin banner shown while the connection is not open.
final class KletsoConnectionBanner extends StatelessWidget {
  /// Creates the banner for [state].
  const KletsoConnectionBanner({required this.state, super.key});

  /// Connection state.
  final KletsoConnectionState state;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final (String? text, Color bg) = switch (state) {
      KletsoConnectionState.open => (null, t.surface),
      KletsoConnectionState.connecting => ('Connecting…', t.infoSoft),
      KletsoConnectionState.reconnecting => ('Reconnecting…', t.warningSoft),
      KletsoConnectionState.closed => ('Offline', t.errorSoft),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity, height: 0)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: bg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (state != KletsoConnectionState.closed)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: t.text,
                        ),
                      ),
                    if (state != KletsoConnectionState.closed)
                      const SizedBox(width: 8),
                    Text(text, style: t.caption.copyWith(color: t.text)),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The message input row.
final class KletsoComposer extends StatefulWidget {
  /// Creates the composer.
  const KletsoComposer({
    required this.onSend,
    super.key,
    this.enabled = true,
    this.hintText = 'Message…',
    this.onTyping,
  });

  /// Called with the trimmed text.
  final ValueChanged<String> onSend;

  /// Disable while offline or handed off.
  final bool enabled;

  /// Placeholder.
  final String hintText;

  /// Called when the user types (typing indicator).
  final VoidCallback? onTyping;

  @override
  State<KletsoComposer> createState() => _KletsoComposerState();
}

final class _KletsoComposerState extends State<KletsoComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      if (has) widget.onTyping?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              style: t.body,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: t.body.copyWith(color: t.textMuted),
                filled: true,
                fillColor: t.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(t.radiusPill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Send',
            child: Material(
              color: _hasText && widget.enabled ? t.primary : t.line,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _hasText && widget.enabled ? _send : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.arrow_upward,
                    color: _hasText && widget.enabled
                        ? t.onPrimary
                        : t.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "New messages" pill shown when the user scrolled away from the bottom.
final class KletsoNewMessagesPill extends StatelessWidget {
  /// Creates the pill.
  const KletsoNewMessagesPill({required this.onTap, super.key});

  /// Scroll to bottom.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Material(
      color: t.text,
      shape: StadiumBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('New messages', style: t.caption.copyWith(color: t.surface)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_downward, size: 14, color: t.surface),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header of the chat sheet: agent name, status, conversation menu, close.
final class KletsoChatHeader extends StatelessWidget {
  /// Creates the header.
  const KletsoChatHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.onClose,
    this.onConversations,
    this.onNewConversation,
  });

  /// Agent name.
  final String title;

  /// Status line.
  final String? subtitle;

  /// Close the sheet.
  final VoidCallback? onClose;

  /// Open the conversation list.
  final VoidCallback? onConversations;

  /// Start a new conversation.
  final VoidCallback? onNewConversation;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.chat_bubble, size: 18, color: t.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: t.subtitle, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: t.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (onNewConversation != null)
            IconButton(
              tooltip: 'New conversation',
              onPressed: onNewConversation,
              icon: Icon(Icons.edit_square, color: t.text, size: 20),
            ),
          if (onConversations != null)
            IconButton(
              tooltip: 'Conversations',
              onPressed: onConversations,
              icon: Icon(Icons.history, color: t.text),
            ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: Icon(Icons.close, color: t.text),
            ),
        ],
      ),
    );
  }
}
