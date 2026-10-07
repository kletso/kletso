/// Protocol package for Kletso.
///
/// Hand-written Dart models for the `kletso.ui/v1` surface protocol, the
/// `kletso.events/v1` event envelope and the realtime WebSocket frames, plus
/// the JSON Schemas and conformance fixtures that every Kletso implementation
/// (Flutter SDK, runtime, web widget) is tested against.
///
/// This package has no Flutter dependency.
library;

export 'src/errors.dart' show KletsoSchemaException;
export 'src/events/entities.dart' show KletsoConversationInfo;
export 'src/events/enums.dart'
    show
        KletsoConversationStatus,
        KletsoFinishReason,
        KletsoMessageModality,
        KletsoMoodSource,
        KletsoNotificationChannel,
        KletsoRole,
        KletsoTriggerKind,
        KletsoVoiceEndReason,
        KletsoVoiceState,
        KletsoWorkflowStatus;
export 'src/events/envelope.dart' show KletsoEventEnvelope;
export 'src/events/payload.dart'
    show
        KletsoAgentTyping,
        KletsoAppCommand,
        KletsoAppNotification,
        KletsoAvatarMoodEvent,
        KletsoConversationEvent,
        KletsoErrorEvent,
        KletsoEventPayload,
        KletsoEventTypes,
        KletsoHandoffEvent,
        KletsoMessageCompleted,
        KletsoMessageCreated,
        KletsoMessageDelta,
        KletsoToolConfirmationRequired,
        KletsoToolFinished,
        KletsoToolStarted,
        KletsoTriggerFired,
        KletsoUiActionEvent,
        KletsoUiPatch,
        KletsoUiRender,
        KletsoUnknownEvent,
        KletsoVoiceEnded,
        KletsoVoiceInterrupted,
        KletsoVoiceStarted,
        KletsoVoiceStateEvent,
        KletsoVoiceTranscript,
        KletsoWorkflowEvent;
export 'src/fixtures/generators.dart' show KletsoFixtureGenerators;
export 'src/fixtures/script.dart' show KletsoConversationScript;
export 'src/generated/embedded.g.dart' show KletsoFixtures, KletsoSchemas;
export 'src/json_utils.dart' show JsonMap, jsonEquals;
export 'src/realtime/binary.dart' show KletsoAudioFrame;
export 'src/realtime/frames.dart'
    show
        KletsoActionFrame,
        KletsoAuthFrame,
        KletsoClientFrame,
        KletsoCloseCodes,
        KletsoContextFrame,
        KletsoErrorFrame,
        KletsoEventFrame,
        KletsoMessageFrame,
        KletsoPingFrame,
        KletsoPongFrame,
        KletsoReadyFrame,
        KletsoScreenFrame,
        KletsoServerFrame,
        KletsoSwitchFrame,
        KletsoTrackFrame,
        KletsoTypingFrame,
        KletsoUnknownServerFrame,
        KletsoVoiceCommitFrame,
        KletsoVoiceMode,
        KletsoVoicePlayedFrame,
        KletsoVoiceStartFrame,
        KletsoVoiceStopFrame,
        KletsoVoiceStopReason,
        KletsoVoiceTextFrame;
export 'src/ui/action.dart'
    show
        KletsoAction,
        KletsoAgentAction,
        KletsoConfirmAction,
        KletsoLocalAction,
        KletsoSubmitAction,
        KletsoUnknownAction,
        KletsoUrlAction,
        KletsoWorkflowAction;
export 'src/ui/binding.dart' show KletsoBinding;
export 'src/ui/catalog.dart' show KletsoBuiltinTypes;
export 'src/ui/issue.dart' show KletsoUiIssue, KletsoUiIssueCode;
export 'src/ui/limits.dart' show KletsoUiLimits;
export 'src/ui/node.dart' show KletsoNode;
export 'src/ui/surface.dart'
    show
        KletsoBindingResolver,
        KletsoSurface,
        KletsoSurfaceOk,
        KletsoSurfaceRejected,
        KletsoSurfaceResult;
