// Component declarations synced to the Kletso dashboard with
// `dart run kletso_flutter:sync`. Keep them next to the widgets that render
// them so the model's tool schema and the Flutter builder never drift.
import 'package:kletso_core/kletso_core.dart'; // pure Dart so `kletso_flutter:sync` can run it

/// Every custom component Acme Shop registers.
const List<KletsoComponentSpec> kletsoComponents = <KletsoComponentSpec>[
  productCardSpec,
];

/// A product tile with image, price, rating and stock state.
const KletsoComponentSpec productCardSpec = KletsoComponentSpec(
  type: 'acme.productCard',
  description:
      'A product tile from the Acme catalogue: image, name, price with currency, star rating and stock state. Use it whenever you recommend or list specific products.',
  props: <String, Object?>{
    'type': 'object',
    'required': <String>['sku', 'name', 'price', 'currency'],
    'properties': <String, Object?>{
      'sku': <String, Object?>{'type': 'string'},
      'name': <String, Object?>{'type': 'string'},
      'price': <String, Object?>{'type': 'number'},
      'currency': <String, Object?>{
        'type': 'string',
        'enum': <String>['INR', 'USD', 'EUR'],
      },
      'image': <String, Object?>{'type': 'string'},
      'rating': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 5},
      'inStock': <String, Object?>{'type': 'boolean'},
    },
  },
  example: <String, Object?>{
    'sku': 'SKU-1001',
    'name': 'Trail Runner 2',
    'price': 1899,
    'currency': 'INR',
    'image': 'https://cdn.acme.com/p/1001.jpg',
    'rating': 4.5,
    'inStock': true,
  },
  actions: <String>['view', 'add'],
);
