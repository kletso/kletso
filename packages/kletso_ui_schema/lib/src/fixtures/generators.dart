import '../json_utils.dart';

/// Deterministic builders for surfaces that break one protocol limit each.
///
/// They exist as code rather than as checked-in JSON because the files would
/// be large (the oversize case alone is over 256 KB); `tool/gen_fixtures.dart`
/// writes them to `fixtures/ui/invalid/` for the non-Dart consumers.
abstract final class KletsoFixtureGenerators {
  static JsonMap _surface(
    String id,
    String root,
    Map<String, Object?> components,
    String fallback,
  ) => <String, Object?>{
    'schema': 'kletso.ui/v1',
    'surfaceId': id,
    'root': root,
    'components': components,
    'fallbackText': fallback,
  };

  /// A chain of [depth] nested columns (default 17, one past the limit).
  static JsonMap depthOverflow({int depth = 17}) {
    final components = <String, Object?>{};
    for (var i = 0; i < depth; i++) {
      final isLeaf = i == depth - 1;
      components['n$i'] = isLeaf
          ? <String, Object?>{
              'type': 'text',
              'props': <String, Object?>{'text': 'leaf at depth $depth'},
            }
          : <String, Object?>{
              'type': 'column',
              'props': <String, Object?>{
                'children': <String>['n${i + 1}'],
              },
            };
    }
    return _surface(
      'sfc_01J8DEPTH00001',
      'n0',
      components,
      'A surface nested $depth levels deep.',
    );
  }

  /// A surface with exactly [count] components (default 501, one past the
  /// limit), laid out as root → groups → texts so that no `children` array
  /// exceeds 200 items and the only broken rule is the component count.
  static JsonMap tooManyComponents({int count = 501}) {
    final groups = ((count - 1) / 201).ceil();
    var leaves = count - 1 - groups;
    final components = <String, Object?>{
      'root': <String, Object?>{
        'type': 'column',
        'props': <String, Object?>{
          'children': <String>[for (var g = 0; g < groups; g++) 'g$g'],
        },
      },
    };
    var next = 1;
    for (var g = 0; g < groups; g++) {
      final take = leaves < 200 ? leaves : 200;
      leaves -= take;
      final ids = <String>[for (var i = 0; i < take; i++) 't${next + i}'];
      components['g$g'] = <String, Object?>{
        'type': 'column',
        'props': <String, Object?>{'children': ids},
      };
      for (final id in ids) {
        components[id] = <String, Object?>{
          'type': 'text',
          'props': <String, Object?>{'text': 'line $id'},
        };
      }
      next += take;
    }
    return _surface(
      'sfc_01J8COUNT00001',
      'root',
      components,
      'A surface with $count components.',
    );
  }

  /// A surface within every other limit whose serialized size exceeds
  /// [targetBytes] (default 300 KB, past the 256 KB limit).
  static JsonMap oversize({int targetBytes = 300 * 1024}) {
    const perString = 4000; // under the 8 KB string limit
    final filler = List<String>.filled(perString ~/ 10, 'lorem ipsu').join();
    final count = (targetBytes / perString).ceil() + 1; // stays under 500
    final components = <String, Object?>{
      'root': <String, Object?>{
        'type': 'column',
        'props': <String, Object?>{
          'children': <String>[for (var i = 1; i <= count; i++) 't$i'],
        },
      },
    };
    for (var i = 1; i <= count; i++) {
      components['t$i'] = <String, Object?>{
        'type': 'text',
        'props': <String, Object?>{'text': '$i $filler'},
      };
    }
    return _surface(
      'sfc_01J8OVERSIZE01',
      'root',
      components,
      'A surface over 256 KB.',
    );
  }

  /// A single text node whose string has [length] chars (default 8193).
  static JsonMap stringTooLong({int length = 8 * 1024 + 1}) =>
      _surface('sfc_01J8LONGSTR001', 't', <String, Object?>{
        't': <String, Object?>{
          'type': 'text',
          'props': <String, Object?>{'text': 'x' * length},
        },
      }, 'A surface with a string over 8 KB.');

  /// A list with [length] items (default 201).
  static JsonMap arrayTooLong({int length = 201}) =>
      _surface('sfc_01J8LONGARR001', 'l', <String, Object?>{
        'l': <String, Object?>{
          'type': 'list',
          'props': <String, Object?>{
            'items': <Object?>[
              for (var i = 0; i < length; i++)
                <String, Object?>{'id': 'i$i', 'title': 'Item $i'},
            ],
          },
        },
      }, 'A surface with an array over 200 items.');

  /// Every generated invalid case by file name.
  static Map<String, JsonMap> all() => <String, JsonMap>{
    'depth_overflow.json': depthOverflow(),
    'too_many_components.json': tooManyComponents(),
    'oversize.json': oversize(),
    'string_too_long.json': stringTooLong(),
    'array_too_long.json': arrayTooLong(),
  };
}
