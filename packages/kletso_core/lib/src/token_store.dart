/// Persists the anonymous visitor id (and nothing else by default) so a
/// returning visitor keeps their conversations. Hosts that want secure
/// storage implement this; the default keeps values in memory.
abstract interface class KletsoTokenStore {
  /// Reads the value under [key], or `null`.
  Future<String?> read(String key);

  /// Writes [value] under [key].
  Future<void> write(String key, String value);

  /// Deletes [key].
  Future<void> delete(String key);
}

/// [KletsoTokenStore] that forgets everything when the process ends.
final class KletsoMemoryTokenStore implements KletsoTokenStore {
  /// Creates an empty store.
  KletsoMemoryTokenStore();

  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
