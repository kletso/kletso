import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

/// Something the user sends: text, a structured value, or an action on a
/// surface. The client assigns the `clientId` and turns it into a frame.
@immutable
sealed class KletsoOutbound {
  const KletsoOutbound();

  /// A plain text message.
  const factory KletsoOutbound.text(String text) = KletsoOutboundText;

  /// A structured value posted as a user turn (quick replies), with an
  /// optional transcript [label].
  const factory KletsoOutbound.value(Object? value, {String? label}) =
      KletsoOutboundValue;

  /// A non-local action on a surface component.
  const factory KletsoOutbound.action({
    required String surfaceId,
    required String componentId,
    required String actionId,
    Object? value,
    String? label,
  }) = KletsoOutboundAction;

  /// A form submission: `submit` action carrying `{formId, values}`.
  factory KletsoOutbound.form({
    required String surfaceId,
    required String componentId,
    required String actionId,
    required String formId,
    required JsonMap values,
  }) => KletsoOutboundAction(
    surfaceId: surfaceId,
    componentId: componentId,
    actionId: actionId,
    value: <String, Object?>{'formId': formId, 'values': values},
    label: 'Form submitted',
  );

  /// An answer to a `confirm` block.
  factory KletsoOutbound.confirm({
    required String surfaceId,
    required String componentId,
    required String actionId,
    required String toolCallId,
    required bool approve,
  }) => KletsoOutboundAction(
    surfaceId: surfaceId,
    componentId: componentId,
    actionId: actionId,
    value: <String, Object?>{'toolCallId': toolCallId, 'approve': approve},
    label: approve ? 'Confirmed' : 'Cancelled',
  );

  /// Text shown in the transcript while the runtime has not echoed the turn.
  String? get echoText;

  /// The wire frame for this outbound with [clientId].
  KletsoClientFrame toFrame(String clientId);
}

/// See [KletsoOutbound.text].
final class KletsoOutboundText extends KletsoOutbound {
  /// Creates a text outbound.
  const KletsoOutboundText(this.text);

  /// The text.
  final String text;

  @override
  String get echoText => text;

  @override
  KletsoClientFrame toFrame(String clientId) =>
      KletsoMessageFrame(clientId: clientId, text: text);
}

/// See [KletsoOutbound.value].
final class KletsoOutboundValue extends KletsoOutbound {
  /// Creates a value outbound.
  const KletsoOutboundValue(this.value, {this.label});

  /// The structured value.
  final Object? value;

  /// Transcript label.
  final String? label;

  @override
  String? get echoText => label;

  @override
  KletsoClientFrame toFrame(String clientId) =>
      KletsoMessageFrame(clientId: clientId, value: value);
}

/// See [KletsoOutbound.action].
final class KletsoOutboundAction extends KletsoOutbound {
  /// Creates an action outbound.
  const KletsoOutboundAction({
    required this.surfaceId,
    required this.componentId,
    required this.actionId,
    this.value,
    this.label,
  });

  /// Surface acted on.
  final String surfaceId;

  /// Component acted on.
  final String componentId;

  /// Action id.
  final String actionId;

  /// Action value.
  final Object? value;

  /// Transcript label.
  final String? label;

  @override
  String? get echoText => label;

  @override
  KletsoClientFrame toFrame(String clientId) => KletsoActionFrame(
    surfaceId: surfaceId,
    componentId: componentId,
    actionId: actionId,
    clientId: clientId,
    value: value,
  );
}
