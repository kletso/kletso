import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../chat/kletso_chat.dart';
import '../registry/ui_bindings.dart';
import '../theme/kletso_theme.dart';

/// How `open()` shows the chat.
enum KletsoPresentation {
  /// Modal bottom sheet (90 % height on phones, centred dialog-like on wide
  /// screens).
  sheet,

  /// Full-screen route.
  fullscreen,
}

/// Open/close the chat from anywhere, plus app-lifecycle wiring.
extension KletsoClientPresentation on KletsoClient {
  /// Shows the chat. Returns when it is dismissed. Starts a conversation if
  /// the user has none.
  Future<void> open(
    BuildContext context, {
    KletsoPresentation presentation = KletsoPresentation.sheet,
    KletsoTheme? theme,
  }) async {
    if (ui.isOpen) return;
    ui.isOpen = true;
    // Make sure the conversation exists before announcing the open, so rules of
    // kind "opens the chat" (manual) answer in the same conversation the chat
    // is about to show (for example with an AI-generated opening turn).
    String? conversationId = activeConversation.value?.id;
    if (conversationId == null && isAuthenticated) {
      try {
        conversationId = (await ensureConversation()).id;
      } on Object {
        conversationId = null; // offline: the chat shows its own error state
      }
      if (!context.mounted) {
        ui.isOpen = false;
        return;
      }
    }
    track(KletsoEvents.chatOpened, <String, Object?>{
      'conversationId': conversationId,
      'userMessages': messages.value.where((m) => m.isUser).length,
      'messages': messages.value.length,
      'presentation': presentation.name,
    });
    final t = theme ?? KletsoTheme.of(context);
    try {
      switch (presentation) {
        case KletsoPresentation.sheet:
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) {
              ui.closeHandler = () {
                if (Navigator.of(sheetContext).canPop()) {
                  Navigator.of(sheetContext).pop();
                }
              };
              final width = MediaQuery.sizeOf(sheetContext).width;
              final wide = width > 720;
              return Align(
                alignment: wide
                    ? Alignment.bottomRight
                    : Alignment.bottomCenter,
                child: Padding(
                  padding: wide ? const EdgeInsets.all(24) : EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: wide
                        ? BorderRadius.circular(t.radiusLg)
                        : BorderRadius.vertical(
                            top: Radius.circular(t.radiusLg),
                          ),
                    child: SizedBox(
                      width: wide ? 420 : double.infinity,
                      height: wide
                          ? 640
                          : MediaQuery.sizeOf(sheetContext).height * 0.9,
                      child: KletsoChat(
                        client: this,
                        theme: t,
                        onClose: () => Navigator.of(sheetContext).pop(),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        case KletsoPresentation.fullscreen:
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (routeContext) {
                ui.closeHandler = () {
                  if (Navigator.of(routeContext).canPop()) {
                    Navigator.of(routeContext).pop();
                  }
                };
                return Scaffold(
                  body: SafeArea(
                    child: KletsoChat(
                      client: this,
                      theme: t,
                      onClose: () => Navigator.of(routeContext).pop(),
                    ),
                  ),
                );
              },
            ),
          );
      }
    } finally {
      ui.isOpen = false;
      ui.closeHandler = null;
    }
  }

  /// Pauses the socket when the app is backgrounded and resumes on return.
  /// Call once after `init`; returns the listener so you can dispose it.
  AppLifecycleListener bindAppLifecycle() => AppLifecycleListener(
    onPause: () => unawaited(pause()),
    onResume: () => unawaited(resume()),
  );
}
