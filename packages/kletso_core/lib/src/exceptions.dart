import 'package:meta/meta.dart';

/// Base of every error the SDK surfaces. Public futures throw these; every
/// one is also emitted on the event stream as `KletsoClientError`.
@immutable
sealed class KletsoException implements Exception {
  const KletsoException(this.message, {this.cause});

  /// Human-readable description.
  final String message;

  /// The underlying error, when there is one.
  final Object? cause;

  /// Whether retrying the same operation later may succeed.
  bool get retryable;

  @override
  String toString() => '$runtimeType: $message';
}

/// The network was unreachable or the connection dropped.
final class KletsoNetworkException extends KletsoException {
  /// Creates a network exception.
  const KletsoNetworkException(super.message, {super.cause});

  @override
  bool get retryable => true;
}

/// A connection attempt or request did not complete in time.
final class KletsoTimeoutException extends KletsoException {
  /// Creates a timeout exception.
  const KletsoTimeoutException(super.message, {super.cause});

  @override
  bool get retryable => true;
}

/// The key, user token or session token was rejected.
final class KletsoAuthException extends KletsoException {
  /// Creates an auth exception. [expired] is `true` for an expired session
  /// token (close code 4403); the SDK refreshes and reconnects on its own.
  const KletsoAuthException(super.message, {this.expired = false, super.cause});

  /// Whether the failure was an expired token rather than a rejection.
  final bool expired;

  @override
  bool get retryable => expired;
}

/// The runtime asked the client to slow down.
final class KletsoRateLimitException extends KletsoException {
  /// Creates a rate-limit exception.
  const KletsoRateLimitException(super.message, {this.retryAfter, super.cause});

  /// Suggested wait, when the server sent one.
  final Duration? retryAfter;

  @override
  bool get retryable => true;
}

/// A frame or response did not match the protocol.
final class KletsoProtocolException extends KletsoException {
  /// Creates a protocol exception.
  const KletsoProtocolException(super.message, {super.cause});

  @override
  bool get retryable => false;
}

/// The runtime returned an error envelope.
final class KletsoServerException extends KletsoException {
  /// Creates a server exception.
  const KletsoServerException(
    super.message, {
    required this.code,
    this.requestId,
    this.statusCode,
    this.retryable = false,
    super.cause,
  });

  /// Error code from the API vocabulary (`invalid_request`, `internal`…).
  final String code;

  /// `Kletso-Request-Id` for support.
  final String? requestId;

  /// HTTP status, when the error came over HTTP.
  final int? statusCode;

  @override
  final bool retryable;
}

/// A tool call failed during a turn (`tool.failed`).
final class KletsoToolException extends KletsoException {
  /// Creates a tool exception.
  const KletsoToolException(super.message, {required this.toolName, this.code});

  /// The failing tool.
  final String toolName;

  /// Tool error code.
  final String? code;

  @override
  bool get retryable => false;
}

/// A workflow run failed (`workflow.failed`).
final class KletsoWorkflowException extends KletsoException {
  /// Creates a workflow exception.
  const KletsoWorkflowException(super.message, {required this.runId});

  /// The failing run.
  final String runId;

  @override
  bool get retryable => false;
}

/// The SDK was used before `init`/`authenticate`, or after `dispose`.
final class KletsoStateException extends KletsoException {
  /// Creates a state exception.
  const KletsoStateException(super.message);

  @override
  bool get retryable => false;
}

/// The outbound queue was full and the oldest frame was dropped.
final class KletsoQueueOverflowException extends KletsoException {
  /// Creates a queue-overflow exception.
  const KletsoQueueOverflowException(
    super.message, {
    required this.droppedClientId,
  });

  /// `clientId` of the dropped frame.
  final String droppedClientId;

  @override
  bool get retryable => true;
}
