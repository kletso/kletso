import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

import 'connection/connection_state.dart';
import 'exceptions.dart';

/// Everything the SDK reports on `KletsoClient.events`: protocol events from
/// the runtime plus client-side happenings (connection changes, errors,
/// unknown components).
@immutable
sealed class KletsoEvent {
  const KletsoEvent();
}

/// A `kletso.events/v1` envelope received from the runtime, after dedupe.
final class KletsoServerEvent extends KletsoEvent {
  /// Creates the event.
  const KletsoServerEvent(this.envelope);

  /// The envelope.
  final KletsoEventEnvelope envelope;

  /// Typed payload shortcut.
  KletsoEventPayload get payload => envelope.payload;

  /// Event type shortcut.
  String get type => envelope.type;
}

/// The realtime connection changed state.
final class KletsoConnectionChanged extends KletsoEvent {
  /// Creates the event.
  const KletsoConnectionChanged(this.state, {this.reason});

  /// New state.
  final KletsoConnectionState state;

  /// Why, when known (close reason, error message).
  final String? reason;
}

/// An error the SDK handled or surfaced. Also thrown from the public future
/// that caused it, when there was one.
final class KletsoClientError extends KletsoEvent {
  /// Creates the event.
  const KletsoClientError(this.exception);

  /// The error.
  final KletsoException exception;
}

/// A surface referenced a component type nobody can render; the fallback
/// text was shown instead.
final class KletsoUnknownComponent extends KletsoEvent {
  /// Creates the event.
  const KletsoUnknownComponent({required this.type, required this.surfaceId});

  /// The unknown type.
  final String type;

  /// The surface it appeared in.
  final String surfaceId;
}

/// A `local` action ran on the device (reported for analytics).
final class KletsoLocalActionRan extends KletsoEvent {
  /// Creates the event.
  const KletsoLocalActionRan({
    required this.name,
    required this.args,
    required this.surfaceId,
    required this.componentId,
    required this.handled,
  });

  /// Action name.
  final String name;

  /// Action args.
  final JsonMap args;

  /// Surface it came from.
  final String surfaceId;

  /// Component it came from.
  final String componentId;

  /// `false` when no handler was registered.
  final bool handled;
}
