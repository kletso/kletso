import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../theme/kletso_theme.dart';

/// Microphone button for the composer. Shown by `KletsoChat` only when
/// `client.voice.available` is true; hosts can place it elsewhere.
final class KletsoVoiceButton extends StatelessWidget {
  /// Creates the button.
  const KletsoVoiceButton({
    required this.onPressed,
    super.key,
    this.enabled = true,
    this.tooltip = 'Talk to the assistant',
  });

  /// Opens the voice sheet.
  final VoidCallback onPressed;

  /// Greyed out while offline.
  final bool enabled;

  /// Tooltip and semantics label.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: t.primarySoft,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.mic_rounded,
                color: enabled ? t.primary : t.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the chat should show a microphone for [client].
bool kletsoVoiceAvailable(KletsoClient client) =>
    client.isAuthenticated && client.voice.available;
