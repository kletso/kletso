import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../listenable_adapter.dart';
import '../registry/ui_bindings.dart';
import '../theme/kletso_theme.dart';
import 'presentation.dart';

/// Floating chat bubble. Drop it in a `Stack` or use it as a
/// `floatingActionButton`; tapping opens the chat with [presentation]. Shows
/// an unread dot when an assistant message arrives while the chat is closed.
final class KletsoLauncher extends StatefulWidget {
  /// Creates the launcher.
  const KletsoLauncher({
    super.key,
    this.client,
    this.presentation = KletsoPresentation.sheet,
    this.icon = Icons.chat_bubble_rounded,
    this.tooltip = 'Chat with us',
    this.onPressed,
  });

  /// The client; `null` uses `Kletso.instance`.
  final KletsoClient? client;

  /// How the chat opens.
  final KletsoPresentation presentation;

  /// Icon.
  final IconData icon;

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
      }
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _messages.dispose();
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
                  child: Icon(
                    widget.icon,
                    color: t.onPrimary,
                    size: t.launcherSize * 0.45,
                  ),
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
