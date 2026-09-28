import 'package:flutter/material.dart';

import 'catalog.dart';

/// Acme's own product tile. Used on the shop grid AND registered with Kletso
/// as `acme.productCard`, so the agent renders the shop's real design.
final class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.sku,
    required this.name,
    required this.price,
    required this.rating,
    required this.inStock,
    required this.onView,
    this.onAdd,
    this.compact = false,
  });

  final String sku;
  final String name;
  final num price;
  final double rating;
  final bool inStock;
  final VoidCallback onView;
  final VoidCallback? onAdd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final local = productBySku(sku);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: compact ? 96 : 120,
              color: local?.color ?? const Color(0xFFF1E8DC),
              alignment: Alignment.center,
              child: Icon(
                local?.icon ?? Icons.inventory_2_outlined,
                size: compact ? 40 : 52,
                color: const Color(0xFF1E2A44),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E2A44),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        rupees(price),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF6A2B),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.star,
                        size: 14,
                        color: Color(0xFFF5A623),
                      ),
                      Text(
                        ' $rating',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: FilledButton.tonal(
                      onPressed: inStock ? onAdd : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: inStock
                            ? scheme.primary.withValues(alpha: 0.12)
                            : null,
                        foregroundColor: scheme.primary,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      child: Text(inStock ? 'Add to cart' : 'Out of stock'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
