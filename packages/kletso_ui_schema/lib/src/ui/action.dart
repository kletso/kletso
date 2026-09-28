import 'package:meta/meta.dart';

import '../errors.dart';
import '../json_utils.dart';

/// An action attached to a component. The `kind` decides where it goes:
/// `local` stays on the device, every other kind is sent to the runtime as an
/// `action` frame.
///
/// Unknown kinds parse into [KletsoUnknownAction] so a surface written for a
/// newer protocol still renders; renderers ignore such actions.
@immutable
sealed class KletsoAction {
  const KletsoAction({required this.id, this.label});

  /// Parses an action from its wire form. Throws [KletsoSchemaException] when
  /// `id` or `kind` are missing or a kind-specific required field is absent.
  factory KletsoAction.fromJson(Object? json, {String path = r'$'}) {
    final map = requireMap(json, path);
    final id = requireString(map, 'id', path);
    final kind = requireString(map, 'kind', path);
    final label = optionalString(map, 'label');
    switch (kind) {
      case 'local':
        return KletsoLocalAction(
          id: id,
          label: label,
          name: requireString(map, 'name', path),
          args: freezeMap(optionalMap(map, 'args')),
        );
      case 'agent':
        if (!map.containsKey('value')) {
          throw KletsoSchemaException('missing "value"', path: '$path/value');
        }
        return KletsoAgentAction(
          id: id,
          label: label,
          value: freezeJson(map['value']),
        );
      case 'workflow':
        return KletsoWorkflowAction(
          id: id,
          label: label,
          workflowId: requireString(map, 'workflowId', path),
          input: freezeMap(optionalMap(map, 'input')),
        );
      case 'url':
        return KletsoUrlAction(
          id: id,
          label: label,
          url: requireString(map, 'url', path),
        );
      case 'submit':
        return KletsoSubmitAction(
          id: id,
          label: label,
          formId: requireString(map, 'formId', path),
        );
      case 'confirm':
        final approve = map['approve'];
        if (approve is! bool) {
          throw KletsoSchemaException(
            'missing or non-boolean "approve"',
            path: '$path/approve',
          );
        }
        return KletsoConfirmAction(
          id: id,
          label: label,
          toolCallId: requireString(map, 'toolCallId', path),
          approve: approve,
        );
      default:
        return KletsoUnknownAction(
          id: id,
          label: label,
          kind: kind,
          raw: freezeMap(map),
        );
    }
  }

  /// Unique within the component.
  final String id;

  /// Optional label the runtime echoes into the transcript for `agent`
  /// actions (e.g. the button text that was pressed).
  final String? label;

  /// The wire discriminator.
  String get kind;

  /// `true` for kinds that never leave the device.
  bool get isLocal => this is KletsoLocalAction;

  /// Wire form, including `id`, `kind` and `label` when present.
  JsonMap toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    if (label != null) 'label': label,
  };

  @override
  bool operator ==(Object other) =>
      other is KletsoAction &&
      other.runtimeType == runtimeType &&
      jsonEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(runtimeType, id, kind);

  @override
  String toString() => '$runtimeType(${toJson()})';
}

/// Runs a host-registered callback by [name]; never leaves the device.
final class KletsoLocalAction extends KletsoAction {
  /// Creates a local action.
  const KletsoLocalAction({
    required super.id,
    required this.name,
    this.args = const <String, Object?>{},
    super.label,
  });

  /// Name of the callback registered with `registerAction`.
  final String name;

  /// Arguments handed to the callback.
  final JsonMap args;

  @override
  String get kind => 'local';

  @override
  JsonMap toJson() => <String, Object?>{
    ...super.toJson(),
    'name': name,
    if (args.isNotEmpty) 'args': args,
  };
}

/// Posts [value] back to the agent as a structured user turn.
final class KletsoAgentAction extends KletsoAction {
  /// Creates an agent action.
  const KletsoAgentAction({
    required super.id,
    required this.value,
    super.label,
  });

  /// Structured value the runtime treats as the next user input.
  final Object? value;

  @override
  String get kind => 'agent';

  @override
  JsonMap toJson() => <String, Object?>{...super.toJson(), 'value': value};
}

/// Starts a workflow run tied to the conversation.
final class KletsoWorkflowAction extends KletsoAction {
  /// Creates a workflow action.
  const KletsoWorkflowAction({
    required super.id,
    required this.workflowId,
    this.input = const <String, Object?>{},
    super.label,
  });

  /// The workflow to run.
  final String workflowId;

  /// Workflow input.
  final JsonMap input;

  @override
  String get kind => 'workflow';

  @override
  JsonMap toJson() => <String, Object?>{
    ...super.toJson(),
    'workflowId': workflowId,
    if (input.isNotEmpty) 'input': input,
  };
}

/// Opens [url]; the host allowlist is checked client- and server-side.
final class KletsoUrlAction extends KletsoAction {
  /// Creates a url action.
  const KletsoUrlAction({required super.id, required this.url, super.label});

  /// Absolute URL. Only `https` is ever opened by the SDK.
  final String url;

  /// Parsed [url], or `null` when it is not a valid URI.
  Uri? get uri => Uri.tryParse(url);

  @override
  String get kind => 'url';

  @override
  JsonMap toJson() => <String, Object?>{...super.toJson(), 'url': url};
}

/// Submits the values of the form with [formId] as a structured user turn.
final class KletsoSubmitAction extends KletsoAction {
  /// Creates a submit action.
  const KletsoSubmitAction({
    required super.id,
    required this.formId,
    super.label,
  });

  /// The `form` component's `props.id`.
  final String formId;

  @override
  String get kind => 'submit';

  @override
  JsonMap toJson() => <String, Object?>{...super.toJson(), 'formId': formId};
}

/// Answers a `confirm` block for a tool call that requires confirmation.
final class KletsoConfirmAction extends KletsoAction {
  /// Creates a confirm action.
  const KletsoConfirmAction({
    required super.id,
    required this.toolCallId,
    required this.approve,
    super.label,
  });

  /// The paused tool call.
  final String toolCallId;

  /// `true` approves the call, `false` cancels it.
  final bool approve;

  @override
  String get kind => 'confirm';

  @override
  JsonMap toJson() => <String, Object?>{
    ...super.toJson(),
    'toolCallId': toolCallId,
    'approve': approve,
  };
}

/// An action whose kind this client does not know. Preserved verbatim so the
/// surface round-trips; renderers ignore it.
final class KletsoUnknownAction extends KletsoAction {
  /// Creates an unknown action wrapping [raw].
  const KletsoUnknownAction({
    required super.id,
    required this.kind,
    required this.raw,
    super.label,
  });

  @override
  final String kind;

  /// The original wire object.
  final JsonMap raw;

  @override
  JsonMap toJson() => raw;
}
