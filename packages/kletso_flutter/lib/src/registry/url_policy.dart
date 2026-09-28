import 'package:meta/meta.dart';

/// Decides which URLs the SDK will open or load. Bot output is untrusted:
/// only `https` and, when the session provides an allowlist, only those
/// hosts (and their subdomains). `javascript:`, `data:`, `file:` and friends
/// are always blocked.
@immutable
final class KletsoUrlPolicy {
  /// Creates a policy. An empty [allowedHosts] allows any `https` host
  /// (previews and tests); the session bootstrap normally supplies a list.
  const KletsoUrlPolicy({this.allowedHosts = const <String>[]});

  /// Allows any https host.
  static const KletsoUrlPolicy permissive = KletsoUrlPolicy();

  /// Exact hosts; subdomains of each are allowed too.
  final List<String> allowedHosts;

  /// Whether [uri] may be opened or loaded.
  bool allows(Uri? uri) {
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (allowedHosts.isEmpty) return true;
    for (final allowed in allowedHosts) {
      final a = allowed.toLowerCase();
      if (host == a || host.endsWith('.$a')) return true;
    }
    return false;
  }

  /// Parses and checks [url]; returns the [Uri] when allowed, else `null`.
  Uri? check(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    return allows(uri) ? uri : null;
  }
}
