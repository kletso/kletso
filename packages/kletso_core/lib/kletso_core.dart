/// Pure-Dart Kletso client: sessions, realtime connection with reconnect and
/// replay, conversation state and typed events.
///
/// Hosts on Flutter use `package:kletso_flutter`, which builds on this. Use
/// this package directly for Dart servers, CLIs and tests. The fake backend
/// for demos and tests lives in `package:kletso_core/fake.dart`.
library;

export 'package:kletso_ui_schema/kletso_ui_schema.dart';

export 'src/api/api.dart' show KletsoApi;
export 'src/api/http_api.dart' show KletsoHttpApi;
export 'src/client.dart'
    show KletsoClient, KletsoEvents, KletsoUserTokenRefresher;
export 'src/component_spec.dart' show KletsoComponentSpec;
export 'src/config.dart'
    show KletsoConfig, KletsoEnvironment, KletsoLogLevel, KletsoTransportMode;
export 'src/connection/backoff.dart' show KletsoBackoff;
export 'src/connection/connection.dart'
    show KletsoConnection, KletsoTokenRefresher;
export 'src/connection/connection_state.dart' show KletsoConnectionState;
export 'src/conversation_state.dart' show KletsoConversationState;
export 'src/events.dart'
    show
        KletsoClientError,
        KletsoConnectionChanged,
        KletsoEvent,
        KletsoLocalActionRan,
        KletsoServerEvent,
        KletsoUnknownComponent;
export 'src/exceptions.dart'
    show
        KletsoAuthException,
        KletsoException,
        KletsoNetworkException,
        KletsoProtocolException,
        KletsoQueueOverflowException,
        KletsoRateLimitException,
        KletsoServerException,
        KletsoStateException,
        KletsoTimeoutException,
        KletsoToolException,
        KletsoWorkflowException;
export 'src/ids.dart' show KletsoIdGenerator;
export 'src/kletso.dart' show Kletso;
export 'src/log.dart' show KletsoLog, KletsoLogger;
export 'src/model/conversation.dart' show KletsoConversation;
export 'src/model/message.dart'
    show
        KletsoMessage,
        KletsoMessageStatus,
        KletsoToolCall,
        KletsoToolCallStatus;
export 'src/model/notification.dart'
    show
        KletsoNotification,
        KletsoNotificationSource,
        KletsoPushPlatform,
        KletsoPushToken;
export 'src/outbound.dart'
    show
        KletsoOutbound,
        KletsoOutboundAction,
        KletsoOutboundText,
        KletsoOutboundValue;
export 'src/session.dart'
    show
        KletsoAgentInfo,
        KletsoDevice,
        KletsoEndUser,
        KletsoSession,
        KletsoSessionBootstrap,
        KletsoVoiceInfo;
export 'src/token_store.dart' show KletsoMemoryTokenStore, KletsoTokenStore;
export 'src/transport/auto_transport.dart' show KletsoAutoTransport;
export 'src/transport/sse_parser.dart' show KletsoSseEvent, KletsoSseParser;
export 'src/transport/sse_transport.dart' show KletsoSseTransport;
export 'src/transport/transport.dart'
    show KletsoCloseInfo, KletsoSocket, KletsoTransport, KletsoTransportRequest;
export 'src/transport/web_socket_transport.dart'
    show KletsoWebSocketConnector, KletsoWebSocketTransport;
export 'src/value_listenable.dart'
    show KletsoValueListenable, KletsoValueNotifier;
export 'src/voice/audio_io.dart' show KletsoAudioIo;
export 'src/voice/voice_controller.dart'
    show KletsoVoiceController, KletsoVoiceStatus;
