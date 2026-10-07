import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../avatar/client_avatar.dart';
import '../listenable_adapter.dart';
import '../markdown/plain_renderer.dart';
import '../markdown/renderer.dart';
import '../surface/surface_view.dart';
import '../theme/kletso_theme.dart';

/// Shows the voice sheet and starts a voice session on the active
/// conversation. Returns when the sheet is dismissed (the session is ended).
Future<void> showKletsoVoiceSheet(
  BuildContext context, {
  required KletsoClient client,
  KletsoClientAvatar? avatar,
  KletsoTheme? theme,
  KletsoMarkdownRenderer markdownRenderer = const KletsoPlainMarkdownRenderer(),
}) {
  final t = theme ?? KletsoTheme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: t.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusLg)),
    ),
    builder: (sheetContext) => Theme(
      data: t.materialTheme(Theme.of(sheetContext)),
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.92,
        child: KletsoVoiceSheet(
          client: client,
          avatar: avatar,
          markdownRenderer: markdownRenderer,
          onClose: () => Navigator.of(sheetContext).maybePop(),
        ),
      ),
    ),
  );
}

/// Voice mode UI: the avatar, what is being said, surfaces the assistant
/// renders while talking, mute, keyboard and End. Starts the session on
/// mount and ends it when closed.
final class KletsoVoiceSheet extends StatefulWidget {
  /// Creates the sheet.
  const KletsoVoiceSheet({
    required this.client,
    super.key,
    this.avatar,
    this.onClose,
    this.markdownRenderer = const KletsoPlainMarkdownRenderer(),
    this.autoStart = true,
  });

  /// The client.
  final KletsoClient client;

  /// Avatar binding; one is created (and disposed) when `null`.
  final KletsoClientAvatar? avatar;

  /// Dismisses the sheet.
  final VoidCallback? onClose;

  /// Renders text in surfaces.
  final KletsoMarkdownRenderer markdownRenderer;

  /// Start the voice session when mounted.
  final bool autoStart;

  @override
  State<KletsoVoiceSheet> createState() => _KletsoVoiceSheetState();
}

final class _KletsoVoiceSheetState extends State<KletsoVoiceSheet> {
  late final KletsoVoiceController _voice = widget.client.voice;
  late final KletsoClientAvatar _avatar =
      widget.avatar ?? KletsoClientAvatar(widget.client);
  late final KletsoListenable<KletsoVoiceStatus> _status = _voice.status
      .asFlutter();
  late final KletsoListenable<String> _transcript = _voice.userTranscript
      .asFlutter();
  late final KletsoListenable<String> _caption = _voice.caption.asFlutter();
  late final KletsoListenable<bool> _muted = _voice.muted.asFlutter();
  late final KletsoListenable<double> _inputLevel = _voice.inputLevel
      .asFlutter();
  final List<KletsoSurface> _surfaces = <KletsoSurface>[];
  StreamSubscription<KletsoEvent>? _sub;
  String? _error;
  bool _typing = false;
  bool _ended = false;
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sub = widget.client.events.listen(_onEvent);
    _status.addListener(_onStatus);
    if (widget.autoStart) unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _voice.start();
    } on KletsoException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendly(e));
    }
  }

  String _friendly(KletsoException e) => switch (e) {
    KletsoServerException(:final code) when code == 'not_configured' =>
      'Voice is not set up yet: this assistant has no OpenAI key.',
    KletsoServerException(:final code) when code == 'permission_denied' =>
      'Microphone access was denied. Allow it in your settings to talk.',
    KletsoServerException(:final code) when code == 'voice_unavailable' =>
      'Voice is not available right now.',
    KletsoServerException(:final code) when code == 'voice_rate_limited' =>
      'Too many voice sessions at the moment, try again shortly.',
    _ => 'Could not start voice: ${e.message}',
  };

  void _onEvent(KletsoEvent e) {
    if (!mounted || e is! KletsoServerEvent) return;
    final p = e.payload;
    if (p is KletsoUiRender) {
      // Same parse as the conversation state: unknown custom types render
      // through the host registry or the fallback text.
      final r = p.parse();
      if (r is KletsoSurfaceOk) setState(() => _surfaces.add(r.surface));
    } else if (p is KletsoVoiceEnded) {
      if (_error == null && p.reason != KletsoVoiceEndReason.user) {
        setState(() {
          _ended = true;
          _error = switch (p.reason) {
            KletsoVoiceEndReason.idle => 'Voice ended after a quiet moment.',
            KletsoVoiceEndReason.limit =>
              'This voice session reached its limit.',
            KletsoVoiceEndReason.notConfigured =>
              'Voice is not set up yet: this assistant has no OpenAI key.',
            _ => _voice.endMessage ?? 'Voice ended.',
          };
        });
      }
    }
  }

  void _onStatus() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _end() async {
    await _voice.stop();
    widget.onClose?.call();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _status
      ..removeListener(_onStatus)
      ..dispose();
    _transcript.dispose();
    _caption.dispose();
    _muted.dispose();
    _inputLevel.dispose();
    _text.dispose();
    if (widget.avatar == null) _avatar.dispose();
    if (_voice.isActive ||
        _voice.status.value == KletsoVoiceStatus.connecting) {
      unawaited(_voice.stop());
    }
    super.dispose();
  }

  String get _label => switch (_status.value) {
    KletsoVoiceStatus.idle => _ended ? 'Ended' : 'Starting…',
    KletsoVoiceStatus.connecting => 'Connecting…',
    KletsoVoiceStatus.listening =>
      _voice.pushToTalk ? 'Hold the button and talk' : 'Listening…',
    KletsoVoiceStatus.thinking => 'Thinking…',
    KletsoVoiceStatus.speaking => 'Speaking',
    KletsoVoiceStatus.ended => 'Ended',
  };

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final agent = widget.client.session.value?.agent;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _status,
        _transcript,
        _caption,
        _muted,
        _inputLevel,
      ]),
      builder: (context, _) {
        final active = _voice.isActive;
        return Material(
          color: t.background,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(agent?.name ?? 'Assistant', style: t.title),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => unawaited(_end()),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Assistant avatar, $_label',
                child: _avatar.build(size: 160),
              ),
              const SizedBox(height: 12),
              Text(
                _label,
                style: t.subtitle.copyWith(color: t.textMuted),
                key: const ValueKey<String>('kletso-voice-status'),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error!,
                    style: t.body.copyWith(color: t.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: <Widget>[
                    if (_transcript.value.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: t.bubbleUser,
                            borderRadius: BorderRadius.circular(t.radiusLg),
                          ),
                          child: Text(_transcript.value, style: t.body),
                        ),
                      ),
                    if (_caption.value.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_caption.value, style: t.body),
                      ),
                    for (final s in _surfaces)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: KletsoSurfaceView(
                          surface: s,
                          client: widget.client,
                          markdownRenderer: widget.markdownRenderer,
                        ),
                      ),
                  ],
                ),
              ),
              if (_typing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) {
                      _voice.sendText(v);
                      _text.clear();
                      setState(() => _typing = false);
                    },
                    decoration: InputDecoration(
                      hintText: 'Type instead…',
                      filled: true,
                      fillColor: t.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(t.radiusPill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    _RoundButton(
                      icon: _muted.value ? Icons.mic_off : Icons.mic,
                      label: _muted.value ? 'Unmute' : 'Mute',
                      enabled: active && !_voice.pushToTalk,
                      onTap: () => _voice.setMuted(!_muted.value),
                    ),
                    if (_voice.pushToTalk)
                      _TalkButton(voice: _voice, enabled: active)
                    else
                      _LevelRing(level: _inputLevel.value, color: t.primary),
                    _RoundButton(
                      icon: Icons.keyboard_alt_outlined,
                      label: 'Type',
                      enabled: active,
                      onTap: () => setState(() => _typing = !_typing),
                    ),
                    _RoundButton(
                      icon: Icons.call_end,
                      label: 'End',
                      color: t.error,
                      onTap: () => unawaited(_end()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final bg = color ?? t.surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: enabled ? bg : t.line,
          shape: const CircleBorder(),
          elevation: color == null ? 0 : 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                icon,
                color: color == null
                    ? (enabled ? t.text : t.textMuted)
                    : t.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Text(label, style: t.caption),
        ),
      ],
    );
  }
}

/// Microphone level ring shown while listening.
final class _LevelRing extends StatelessWidget {
  const _LevelRing({required this.level, required this.color});
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final double size = 56 + 28 * level.clamp(0.0, 1.0);
    return SizedBox(
      width: 84,
      height: 84,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12 + 0.3 * level.clamp(0.0, 1.0)),
            border: Border.all(color: t.primary.withValues(alpha: 0.5)),
          ),
          child: Icon(Icons.graphic_eq, color: t.primary),
        ),
      ),
    );
  }
}

/// Hold-to-talk button for push-to-talk agents.
final class _TalkButton extends StatelessWidget {
  const _TalkButton({required this.voice, required this.enabled});
  final KletsoVoiceController voice;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    return Semantics(
      button: true,
      label: 'Hold to talk',
      child: GestureDetector(
        onTapDown: enabled ? (_) => voice.setMuted(false) : null,
        onTapUp: enabled
            ? (_) {
                voice.setMuted(true);
                voice.commit();
              }
            : null,
        onTapCancel: enabled ? () => voice.setMuted(true) : null,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? t.primary : t.line,
          ),
          child: Icon(Icons.mic, color: t.onPrimary, size: 36),
        ),
      ),
    );
  }
}
