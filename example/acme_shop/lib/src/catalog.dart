import 'package:flutter/material.dart';

/// Acme's local product catalogue (what a real shop would load from its API).
final class Product {
  const Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.rating,
    required this.inStock,
    required this.color,
    required this.icon,
  });
  final String sku;
  final String name;
  final int price;
  final double rating;
  final bool inStock;
  final Color color;
  final IconData icon;
}

const List<Product> catalog = <Product>[
  Product(
    sku: 'SKU-1001',
    name: 'Trail Runner 2',
    price: 1899,
    rating: 4.5,
    inStock: true,
    color: Color(0xFFB8F0DC),
    icon: Icons.directions_run,
  ),
  Product(
    sku: 'SKU-1002',
    name: 'Everyday Tote',
    price: 1299,
    rating: 4.2,
    inStock: true,
    color: Color(0xFFFFE08A),
    icon: Icons.shopping_bag_outlined,
  ),
  Product(
    sku: 'SKU-1003',
    name: 'Steel Bottle 750',
    price: 999,
    rating: 4.8,
    inStock: false,
    color: Color(0xFFDBEAFE),
    icon: Icons.water_drop_outlined,
  ),
  Product(
    sku: 'SKU-1004',
    name: 'Merino Beanie',
    price: 799,
    rating: 4.1,
    inStock: true,
    color: Color(0xFFFFE4D5),
    icon: Icons.ac_unit,
  ),
  Product(
    sku: 'SKU-1005',
    name: 'Trail Socks ×3',
    price: 599,
    rating: 4.6,
    inStock: true,
    color: Color(0xFFDCE1EC),
    icon: Icons.checkroom,
  ),
  Product(
    sku: 'SKU-1006',
    name: 'Compact Rain Shell',
    price: 3499,
    rating: 4.7,
    inStock: true,
    color: Color(0xFFB8F0DC),
    icon: Icons.umbrella_outlined,
  ),
];

/// The shop's cart, shared by the grid and the Kletso component builders so an
/// action inside the chat changes the app's own state.
final ValueNotifier<List<Product>> cart = ValueNotifier<List<Product>>(
  <Product>[],
);

void addToCart(Product p) => cart.value = <Product>[...cart.value, p];

Product? productBySku(String sku) {
  for (final p in catalog) {
    if (p.sku == sku) return p;
  }
  return null;
}

String rupees(num v) {
  final s = v.toInt().toString();
  if (s.length <= 3) return '₹$s';
  final head = s.substring(0, s.length - 3);
  final tail = s.substring(s.length - 3);
  final buf = StringBuffer();
  for (var i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i) % 2 == 0) buf.write(',');
    buf.write(head[i]);
  }
  return '₹$buf,$tail';
}
