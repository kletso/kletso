/// Embeddable Kletso AI chat for Flutter.
///
/// ```dart
/// await Kletso.init(KletsoConfig(publishableKey: 'kl_pub_…', agentId: 'agt_…'));
/// await Kletso.instance.authenticate(token: jwt);
/// Kletso.instance.registerComponent('acme.productCard', (ctx, node) => …);
/// Kletso.instance.open(context);
/// ```
///
/// Re-exports `kletso_core` (and through it `kletso_ui_schema`) so one import
/// is enough.
library;

export 'package:kletso_core/kletso_core.dart';

export 'src/avatar/avatar_controller.dart' show KletsoAvatarController;
export 'src/avatar/avatar_face.dart'
    show KletsoAvatarEyeShape, KletsoAvatarFaceParams, KletsoAvatarMood;
export 'src/avatar/avatar_painter.dart'
    show KletsoAvatarColors, KletsoAvatarPainter;
export 'src/avatar/client_avatar.dart' show KletsoClientAvatar;
export 'src/avatar/kletso_avatar.dart' show KletsoAvatar, KletsoAvatarStyle;
export 'src/avatar/kletso_avatar_face.g.dart' show KletsoAvatarFaceData;
export 'src/blocks/chart_block.dart'
    show KletsoChartPainter, KletsoChartPoint, KletsoChartSeries;
export 'src/blocks/media_blocks.dart'
    show KletsoFormat, KletsoMapMarker, KletsoWaveformPainter;
export 'src/blocks/structure_blocks.dart' show KletsoCountdown;
export 'src/blocks/support.dart' show KletsoButton;
export 'src/chat/bubbles.dart'
    show
        KletsoBotBubble,
        KletsoToolCallChip,
        KletsoTypingDots,
        KletsoUserBubble;
export 'src/chat/chrome.dart'
    show
        KletsoChatHeader,
        KletsoComposer,
        KletsoConnectionBanner,
        KletsoNewMessagesPill;
export 'src/chat/conversation_list.dart' show KletsoConversationList;
export 'src/chat/kletso_chat.dart' show KletsoChat;
export 'src/launcher/kletso_launcher.dart' show KletsoLauncher;
export 'src/launcher/presentation.dart'
    show KletsoClientPresentation, KletsoPresentation;
export 'src/listenable_adapter.dart'
    show KletsoListenable, KletsoValueListenableFlutter;
export 'src/markdown/plain_renderer.dart' show KletsoPlainMarkdownRenderer;
export 'src/markdown/renderer.dart'
    show KletsoMarkdownRenderer, KletsoMarkdownRequest;
export 'src/notifications/notification_host.dart'
    show
        KletsoNotificationBanner,
        KletsoNotificationHost,
        KletsoNotificationToast,
        KletsoSystemNotifier;
export 'src/registry/build_context.dart'
    show KletsoActionContext, KletsoActionOrigin, KletsoBuildContext;
export 'src/registry/dispatcher.dart'
    show KletsoActionDispatcher, KletsoActionObserver, KletsoOpenUrl;
export 'src/registry/registry.dart'
    show
        KletsoActionHandler,
        KletsoActionRegistry,
        KletsoComponentBuilder,
        KletsoComponentRegistry;
export 'src/registry/ui_bindings.dart'
    show
        KletsoClientUi,
        KletsoCommandOutcome,
        KletsoCommandResult,
        KletsoNotificationOutcome,
        KletsoNotificationResult,
        KletsoUi;
export 'src/registry/url_policy.dart' show KletsoUrlPolicy;
export 'src/surface/fallback.dart' show KletsoFallback;
export 'src/surface/surface_view.dart' show KletsoSurfaceView;
export 'src/theme/kletso_theme.dart'
    show KletsoLauncherIcon, KletsoLauncherPosition, KletsoTheme;
export 'src/theme/kletso_tokens.g.dart' show KletsoTokens;
export 'src/voice/voice_button.dart'
    show KletsoVoiceButton, kletsoVoiceAvailable;
export 'src/voice/voice_sheet.dart' show KletsoVoiceSheet, showKletsoVoiceSheet;
