import '../exceptions.dart';
import 'transport.dart';

/// Tries the primary transport (WebSocket) and, after [failuresBeforeFallback]
/// consecutive handshake failures that are not auth errors, uses the fallback
/// (SSE) for the rest of this instance's life. A fresh `KletsoClient`
/// (cold start) tries WebSocket again.
final class KletsoAutoTransport implements KletsoTransport {
  /// Creates an auto-selecting transport.
  KletsoAutoTransport({
    required KletsoTransport primary,
    required KletsoTransport fallback,
    this.failuresBeforeFallback = 2,
  }) : _primary = primary,
       _fallback = fallback;

  final KletsoTransport _primary;
  final KletsoTransport _fallback;

  /// How many consecutive primary failures switch to the fallback.
  final int failuresBeforeFallback;

  int _failures = 0;
  bool _useFallback = false;

  /// Whether the fallback is active.
  bool get usingFallback => _useFallback;

  @override
  String get name => _useFallback ? _fallback.name : _primary.name;

  @override
  Future<KletsoSocket> open(KletsoTransportRequest request) async {
    if (_useFallback) return _fallback.open(request);
    try {
      final socket = await _primary.open(request);
      _failures = 0;
      return socket;
    } on KletsoAuthException {
      rethrow; // a bad token is not a transport problem
    } on KletsoException {
      _failures++;
      if (_failures >= failuresBeforeFallback) _useFallback = true;
      rethrow;
    }
  }
}
