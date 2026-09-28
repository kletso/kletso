import 'package:meta/meta.dart';

/// A value that notifies listeners when it changes.
///
/// Mirrors Flutter's `ValueListenable` member-for-member so `kletso_flutter`
/// can adapt it in one line, while keeping `kletso_core` free of Flutter.
abstract interface class KletsoValueListenable<T> {
  /// The current value.
  T get value;

  /// Registers [listener] to be called whenever [value] changes.
  void addListener(void Function() listener);

  /// Unregisters [listener].
  void removeListener(void Function() listener);
}

/// A mutable [KletsoValueListenable]. Notifies only when the new value is not
/// `==` to the old one.
final class KletsoValueNotifier<T> implements KletsoValueListenable<T> {
  /// Creates a notifier holding [value].
  KletsoValueNotifier(this._value);

  T _value;
  final List<void Function()> _listeners = <void Function()>[];
  bool _disposed = false;

  @override
  T get value => _value;

  /// Sets the value and notifies listeners when it changed.
  set value(T next) {
    if (_disposed || next == _value) return;
    _value = next;
    notify();
  }

  /// Calls every listener; use after mutating [value] in place.
  @protected
  void notify() {
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  @override
  void addListener(void Function() listener) {
    if (!_disposed) _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Whether [addListener] has any registrations.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Drops all listeners; further sets are ignored.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}
