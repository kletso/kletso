import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../avatar/avatar_controller.dart';
import '../avatar/avatar_face.dart';
import '../avatar/kletso_avatar.dart';
import '../listenable_adapter.dart';
import '../registry/ui_bindings.dart';
import '../theme/kletso_theme.dart';
import 'presentation.dart';

/// How long an unread message flashes a [KletsoAvatarMood.wink] on the
/// mascot launcher icon.
const Duration _unreadWinkTtl = Duration(milliseconds: 1500);

/// Floating chat bubble. Drop it in a `Stack` or use it as a
/// `floatingActionButton`; tapping opens the chat with [presentation]. Shows
/// an unread dot when an assistant message arrives while the chat is closed.
/// When `KletsoTheme.launcherIcon` is [KletsoLauncherIcon.mascot], the
/// animated Kletso face replaces the Material [icon] and reacts to unread
/// messages (wink) and `client.agentTyping` (thinking).
final class KletsoLauncher extends StatefulWidget {
  /// Creates the launcher.
  const KletsoLauncher({
    super.key,
    this.client,
    this.presentation = KletsoPresentation.sheet,
    this.icon,
    this.tooltip = 'Chat with us',
    this.onPressed,
  });

  /// The client; `null` uses `Kletso.instance`.
  final KletsoClient? client;

  /// How the chat opens.
  final KletsoPresentation presentation;

  /// Explicit icon override; `null` follows `KletsoTheme.launcherIcon`.
  final IconData? icon;

  /// Tooltip / semantics label.
  final String tooltip;

  /// Override the tap behaviour (e.g. route to your own screen).
  final VoidCallback? onPressed;

  @override
  State<KletsoLauncher> createState() => _KletsoLauncherState();
}

final class _KletsoLauncherState extends State<KletsoLauncher> {
  late final KletsoClient _client = widget.client ?? Kletso.instance;
  late final KletsoListenable<List<KletsoMessage>> _messages = _client.messages
      .asFlutter();
  late final KletsoListenable<bool> _typing = _client.agentTyping.asFlutter();
  final KletsoAvatarController _avatar = KletsoAvatarController();
  StreamSubscription<KletsoEvent>? _sub;
  bool _unread = false;

  @override
  void initState() {
    super.initState();
    _sub = _client.events.listen((e) {
      if (e is KletsoServerEvent &&
          e.type == KletsoEventTypes.messageCompleted &&
          !_client.ui.isOpen &&
          mounted) {
        setState(() => _unread = true);
        _avatar.setMood(KletsoAvatarMood.wink, ttl: _unreadWinkTtl);
      }
    });
    _typing.addListener(_onTypingChanged);
  }

  void _onTypingChanged() {
    if (_typing.value) {
      _avatar.setMood(KletsoAvatarMood.thinking);
    } else if (_avatar.mood == KletsoAvatarMood.thinking) {
      _avatar.setMood(_avatar.defaultMood);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _typing
      ..removeListener(_onTypingChanged)
      ..dispose();
    _messages.dispose();
    _avatar.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _unread = false);
    if (widget.onPressed != null) {
      widget.onPressed!();
      return;
    }
    await _client.open(context, presentation: widget.presentation);
  }

  Widget _buildIcon(KletsoTheme t) {
    if (widget.icon != null) {
      return Icon(widget.icon, color: t.onPrimary, size: t.launcherSize * 0.45);
    }
    return switch (t.launcherIcon) {
      KletsoLauncherIcon.mascot => KletsoAvatar(
        controller: _avatar,
        size: t.launcherSize * 0.8,
      ),
      KletsoLauncherIcon.sparkle => Icon(
        Icons.auto_awesome,
        color: t.onPrimary,
        size: t.launcherSize * 0.45,
      ),
      KletsoLauncherIcon.chat => Icon(
        Icons.chat_bubble_rounded,
        color: t.onPrimary,
        size: t.launcherSize * 0.45,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Material(
              color: t.primary,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: t.primary.withValues(alpha: 0.4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => unawaited(_open()),
                child: SizedBox(
                  width: t.launcherSize,
                  height: t.launcherSize,
                  child: Center(child: _buildIcon(t)),
                ),
              ),
            ),
            if (_unread)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: t.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
