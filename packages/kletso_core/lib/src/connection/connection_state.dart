/// Observable state of the realtime connection.
enum KletsoConnectionState {
  /// Not connected and not trying (initial, after `disconnect`, after a fatal
  /// auth failure, or while paused).
  closed,

  /// First attempt in progress.
  connecting,

  /// Authenticated and receiving.
  open,

  /// Lost the socket; retrying with backoff. Outbound frames are queued.
  reconnecting,
}
