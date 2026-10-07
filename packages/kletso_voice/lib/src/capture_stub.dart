import 'dart:typed_data';

import 'capture.dart';

/// Placeholder for platforms without an implementation (never selected on
/// Flutter targets; keeps the conditional import total).
final class PlatformCapture implements KletsoCapture {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<Stream<Uint8List>> start(KletsoCaptureConfig config) async =>
      throw UnsupportedError('no microphone on this platform');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
