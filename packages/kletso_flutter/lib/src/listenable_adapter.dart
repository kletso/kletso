import 'package:flutter/foundation.dart';
import 'package:kletso_core/kletso_core.dart';

/// Exposes a [KletsoValueListenable] as a Flutter [ValueListenable] so it
/// works with `ValueListenableBuilder`, `ListenableBuilder` and Riverpod/Bloc
/// bridges. Listeners are forwarded one-to-one; call [dispose] when done.
final class KletsoListenable<T> extends ChangeNotifier
    implements ValueListenable<T> {
  /// Wraps [source].
  KletsoListenable(this._source) {
    _source.addListener(notifyListeners);
  }

  final KletsoValueListenable<T> _source;

  @override
  T get value => _source.value;

  @override
  void dispose() {
    _source.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Convenience for wrapping core observables in Flutter code.
extension KletsoValueListenableFlutter<T> on KletsoValueListenable<T> {
  /// A Flutter [ValueListenable] view of this observable. Dispose it.
  KletsoListenable<T> asFlutter() => KletsoListenable<T>(this);
}
