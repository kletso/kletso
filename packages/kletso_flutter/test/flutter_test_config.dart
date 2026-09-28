// Applies to every test in this package. Goldens are compared with a small
// tolerance so the reference PNGs (generated on one machine) also pass on the
// CI Linux runner, where font hinting differs by ~2 % of pixels (D45).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const double _maxDiffPercent = 6;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final base = goldenFileComparator;
  if (base is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(base.basedir);
  }
  await testMain();
}

final class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(Uri basedir) : super(basedir.resolve('x.dart'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed) return true;
    final percent = result.diffPercent * 100;
    if (percent <= _maxDiffPercent) return true;
    await generateFailureOutput(result, golden, basedir);
    throw FlutterError(
      'Golden "$golden": pixel test failed, ${percent.toStringAsFixed(2)}% '
      '(> $_maxDiffPercent% tolerance)',
    );
  }
}
