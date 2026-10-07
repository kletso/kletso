import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../avatar/client_avatar.dart';
import '../listenable_adapter.dart';
import '../markdown/plain_renderer.dart';
import '../markdown/renderer.dart';
import '../theme/kletso_theme.dart';
import '../voice/voice_button.dart';
import '../voice/voice_sheet.dart';
import 'bubbles.dart';
import 'chrome.dart';
import 'conversation_list.dart';

/// The embeddable chat: header, connection banner, reverse message list with
/// streaming bubbles and rendered surfaces, typing indicator and composer.
///
/// Place it anywhere (a page, a sheet, a side panel). It reads state from
/// [client] and needs nothing else; theming comes from [theme] or the
/// `KletsoTheme` in the ambient `ThemeData`.
final class KletsoChat extends StatefulWidget {
  /// Creates the chat for [client] (defaults to `Kletso.instance`).
  const KletsoChat({
    super.key,
    this.client,
    this.theme,
    this.markdownRenderer = const KletsoPlainMarkdownRenderer(),
    this.showHeader = true,
    this.onClose,
    this.emptyStateText,
    this.composerHint = 'Message…',
    this.showVoiceButton = true,
  });

  /// The client; `null` uses `Kletso.instance`.
  final KletsoClient? client;

  /// Explicit theme; `null` reads `KletsoTheme.of(context)`.
  final KletsoTheme? theme;

  /// Renders assistant text and `markdown` blocks.
  final KletsoMarkdownRenderer markdownRenderer;

  /// Show the header with agent name and menu.
  final bool showHeader;

  /// Close button callback (hidden when `null`).
  final VoidCallback? onClose;

  /// Text shown before the first message arrives.
  final String? emptyStateText;

  /// Composer placeholder.
  final String composerHint;

  /// Show the microphone when the agent offers voice and audio is installed
  /// (`KletsoVoice.install` from `package:kletso_voice`, or a host
  /// `KletsoAudioIo`).
  final bool showVoiceButton;

  @override
  State<KletsoChat> createState() => _KletsoChatState();
}

final class _KletsoChatState extends State<KletsoChat> {
  late KletsoClient _client;
  late KletsoListenable<List<KletsoMessage>> _messages;
  late KletsoListenable<KletsoConnectionState> _connection;
  late KletsoListenable<bool> _typing;
  late KletsoListenable<KletsoConversation?> _active;
  late KletsoListenable<KletsoSessionBootstrap?> _session;
  late KletsoClientAvatar _avatar;
  final ScrollController _scroll = ScrollController();
  bool _showPill = false;
  int _lastCount = 0;
  bool _ensuring = false;
  Timer? _typingThrottle;

  @override
  void initState() {
    super.initState();
    _bind(widget.client ?? Kletso.instance);
    _scroll.addListener(_onScroll);
    unawaited(_ensureConversation());
  }

  void _bind(KletsoClient client) {
    _client = client;
    _messages = client.messages.asFlutter()..addListener(_onMessages);
    _connection = client.connection.asFlutter();
    _typing = client.agentTyping.asFlutter();
    _active = client.activeConversation.asFlutter();
    _session = client.session.asFlutter();
    _avatar = KletsoClientAvatar(client);
    _lastCount = client.messages.value.length;
  }

  void _unbind() {
    _messages
      ..removeListener(_onMessages)
      ..dispose();
    _connection.dispose();
    _typing.dispose();
    _active.dispose();
    _session.dispose();
    _avatar.dispose();
  }

  Future<void> _openVoice(BuildContext context) => showKletsoVoiceSheet(
    context,
    client: _client,
    avatar: _avatar,
    theme: widget.theme,
    markdownRenderer: widget.markdownRenderer,
  );

  @override
  void didUpdateWidget(KletsoChat old) {
    super.didUpdateWidget(old);
    final next = widget.client ?? Kletso.instance;
    if (!identical(next, _client)) {
      _unbind();
      _bind(next);
    }
  }

  @override
  void dispose() {
    _typingThrottle?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _unbind();
    super.dispose();
  }

  Future<void> _ensureConversation() async {
    if (_ensuring ||
        !_client.isAuthenticated ||
        _client.activeConversation.value != null) {
      return;
    }
    _ensuring = true;
    try {
      await _client.ensureConversation();
    } on KletsoException {
      // Reported on the client's event stream; the banner shows the state.
    } finally {
      _ensuring = false;
    }
  }

  bool get _nearBottom => !_scroll.hasClients || _scroll.position.pixels < 80;

  void _onScroll() {
    if (_nearBottom && _showPill) setState(() => _showPill = false);
  }

  void _onMessages() {
    final count = _messages.value.length;
    final grew = count > _lastCount;
    _lastCount = count;
    if (grew &&
        !_nearBottom &&
        !(_messages.value.lastOrNull?.isUser ?? false)) {
      if (!_showPill) setState(() => _showPill = true);
    } else if (_scroll.hasClients &&
        (_nearBottom || (_messages.value.lastOrNull?.isUser ?? false))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  void _scrollToBottom() {
    setState(() => _showPill = false);
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _send(String text) async {
    try {
      await _client.send(KletsoOutbound.text(text));
    } on KletsoException {
      // Surfaces as a failed pending bubble / event.
    }
  }

  void _openConversations(BuildContext context) {
    final t = widget.theme ?? KletsoTheme.of(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusLg)),
        ),
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: 420,
            child: KletsoConversationList(
              client: _client,
              onSelected: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? KletsoTheme.of(context);
    return Theme(
      data: theme.materialTheme(Theme.of(context)),
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _messages,
          _connection,
          _typing,
          _active,
          _session,
        ]),
        builder: (context, _) {
          final t = KletsoTheme.of(context);
          final messages = _messages.value;
          final agent = _session.value?.agent;
          final active = _active.value;
          final handedOff = active?.status == KletsoConversationStatus.handoff;
          final closed = active?.status == KletsoConversationStatus.closed;
          if (_client.isAuthenticated && active == null) {
            unawaited(_ensureConversation());
          }
          return Material(
            color: t.background,
            child: Column(
              children: <Widget>[
                if (widget.showHeader)
                  KletsoChatHeader(
                    title: agent?.name ?? 'Assistant',
                    subtitle: handedOff
                        ? 'With the support team'
                        : switch (_connection.value) {
                            KletsoConnectionState.open =>
                              _typing.value ? 'Typing…' : 'Online',
                            KletsoConnectionState.connecting => 'Connecting…',
                            KletsoConnectionState.reconnecting =>
                              'Reconnecting…',
                            KletsoConnectionState.closed => 'Offline',
                          },
                    onClose: widget.onClose,
                    onConversations: () => _openConversations(context),
                    onNewConversation: () =>
                        unawaited(_client.startConversation()),
                  ),
                KletsoConnectionBanner(state: _connection.value),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      if (messages.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              widget.emptyStateText ??
                                  agent?.greeting ??
                                  'Ask me anything.',
                              style: t.body.copyWith(color: t.textMuted),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              final showTyping =
                                  _typing.value &&
                                      !(messages.lastOrNull?.isAssistant ??
                                          false) ||
                                  (_typing.value &&
                                      messages.last.status ==
                                          KletsoMessageStatus.complete);
                              return showTyping
                                  ? Padding(
                                      padding: const EdgeInsets.only(
                                        left: 32,
                                        top: 8,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: KletsoTypingDots(),
                                      ),
                                    )
                                  : const SizedBox(height: 4);
                            }
                            final m = messages[messages.length - index];
                            final prev = messages.length - index - 1 >= 0
                                ? messages[messages.length - index - 1]
                                : null;
                            final sameAuthorAsPrev =
                                prev != null && prev.role == m.role;
                            return Padding(
                              key: ValueKey<String>(m.id),
                              padding: EdgeInsets.only(
                                top: sameAuthorAsPrev ? 4 : 12,
                              ),
                              child: m.isUser
                                  ? KletsoUserBubble(message: m)
                                  : KletsoBotBubble(
                                      message: m,
                                      client: _client,
                                      markdownRenderer: widget.markdownRenderer,
                                      showAvatar: !sameAuthorAsPrev,
                                      avatarController: _avatar.controller,
                                    ),
                            );
                          },
                        ),
                      if (_showPill)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: KletsoNewMessagesPill(
                              onTap: _scrollToBottom,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                KletsoComposer(
                  onSend: _send,
                  leading:
                      widget.showVoiceButton &&
                          !closed &&
                          !handedOff &&
                          kletsoVoiceAvailable(_client)
                      ? KletsoVoiceButton(
                          enabled:
                              _connection.value == KletsoConnectionState.open,
                          onPressed: () => unawaited(_openVoice(context)),
                        )
                      : null,
                  enabled: _client.isAuthenticated && !closed,
                  hintText: closed
                      ? 'This conversation is closed'
                      : (handedOff
                            ? 'Message the support team…'
                            : widget.composerHint),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
