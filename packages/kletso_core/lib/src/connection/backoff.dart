import 'dart:math';

/// Exponential backoff with full jitter: each delay is uniform in
/// `[0, min(cap, base * 2^attempt)]`.
final class KletsoBackoff {
  /// Creates a policy; pass a seeded [random] in tests.
  KletsoBackoff({required this.base, required this.cap, Random? random})
    : _random = random ?? Random();

  /// Delay ceiling for attempt 0.
  final Duration base;

  /// Never wait longer than this.
  final Duration cap;

  final Random _random;
  int _attempt = 0;

  /// Attempts since the last [reset].
  int get attempt => _attempt;

  /// Upper bound of the next delay without consuming an attempt.
  Duration get nextCeiling {
    final shift = _attempt.clamp(0, 30);
    final ms = base.inMilliseconds * (1 << shift);
    return Duration(milliseconds: min(ms, cap.inMilliseconds));
  }

  /// Returns the next delay and advances the attempt counter.
  Duration next() {
    final ceiling = nextCeiling.inMilliseconds;
    _attempt++;
    return Duration(
      milliseconds: ceiling == 0 ? 0 : _random.nextInt(ceiling + 1),
    );
  }

  /// Starts over after a successful connection.
  void reset() => _attempt = 0;
}
