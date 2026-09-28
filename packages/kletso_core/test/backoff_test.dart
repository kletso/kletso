import 'dart:math';

import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

void main() {
  test('ceilings double from base and stop at the cap', () {
    final b = KletsoBackoff(
      base: const Duration(milliseconds: 500),
      cap: const Duration(seconds: 30),
      random: Random(1),
    );
    final ceilings = <int>[];
    for (var i = 0; i < 10; i++) {
      ceilings.add(b.nextCeiling.inMilliseconds);
      final d = b.next();
      expect(d.inMilliseconds, inInclusiveRange(0, ceilings.last));
    }
    expect(ceilings, [
      500,
      1000,
      2000,
      4000,
      8000,
      16000,
      30000,
      30000,
      30000,
      30000,
    ]);
    expect(b.attempt, 10);
    b.reset();
    expect(b.attempt, 0);
    expect(b.nextCeiling, const Duration(milliseconds: 500));
  });

  test('full jitter is uniform over the whole range', () {
    final b = KletsoBackoff(
      base: const Duration(milliseconds: 1000),
      cap: const Duration(milliseconds: 1000),
      random: Random(42),
    );
    final samples = List<int>.generate(500, (_) => b.next().inMilliseconds);
    expect(samples.reduce(min), lessThan(100));
    expect(samples.reduce(max), greaterThan(900));
  });

  test('a zero base never waits', () {
    final b = KletsoBackoff(base: Duration.zero, cap: Duration.zero);
    expect(b.next(), Duration.zero);
  });
}
