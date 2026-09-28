import 'dart:math';

import 'package:clock/clock.dart';

/// Generates ULID-style ids: 10 chars of millisecond time + 16 random chars
/// in Crockford base32, so ids sort by creation time and never collide in
/// practice. Time comes from `package:clock` so tests can control it.
final class KletsoIdGenerator {
  /// Creates a generator; pass a seeded [random] in tests.
  KletsoIdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// A new ULID (26 chars).
  String ulid() {
    var ms = clock.now().toUtc().millisecondsSinceEpoch;
    final time = List<String>.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      time[i] = _alphabet[ms & 31];
      ms >>= 5;
    }
    final rand = StringBuffer();
    for (var i = 0; i < 16; i++) {
      rand.write(_alphabet[_random.nextInt(32)]);
    }
    return '${time.join()}$rand';
  }

  /// `c_` + ULID, for `clientId` fields.
  String clientId() => 'c_${ulid()}';

  /// `anon_` + ULID, for anonymous visitor ids.
  String anonymousId() => 'anon_${ulid()}';
}
