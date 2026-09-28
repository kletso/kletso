import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

import 'catalog.dart';
import 'notifier.dart';
import 'product_card.dart';
import 'settings.dart';

final class ShopHome extends StatefulWidget {
  const ShopHome({super.key});

  @override
  State<ShopHome> createState() => _ShopHomeState();
}

final class _ShopHomeState extends State<ShopHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    cart.addListener(_onCart);
  }

  @override
  void dispose() {
    cart.removeListener(_onCart);
    super.dispose();
  }

  void _onCart() {
    setState(() {});
    final total = cart.value.fold<int>(0, (a, b) => a + b.price);
    // App state the agent's surfaces may bind to (/host/cart/...); never sent anywhere.
    Kletso.instance.setHostData(<String, Object?>{
      'cart': <String, Object?>{
        'progress': (total / 3500).clamp(0.0, 1.0),
        'label': total >= 3500
            ? 'Free shipping unlocked'
            : '₹${3500 - total} away from free shipping',
        'items': cart.value.length,
      },
    });
    Kletso.instance.updateContext(<String, Object?>{
      'cartValue': cart.value.fold<int>(0, (a, b) => a + b.price),
      'cartItems': cart.value.length,
    });
  }

  void _addToCart(Product p) {
    addToCart(p);
    Kletso.instance.track('add_to_cart', <String, Object?>{
      'sku': p.sku,
      'price': p.price,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${p.name} added to cart'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _Catalog(
        onView: (p) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ProductPage(product: p)),
        ),
        onAdd: _addToCart,
      ),
      _CartPage(cart: cart.value),
      const _InlineChatPage(),
      const SettingsPage(),
    ];
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.storefront, color: Color(0xFFFF6A2B)),
            SizedBox(width: 8),
            Text('Acme Shop'),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E2A44),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _ConnectionDot()),
          ),
        ],
      ),
      body: Row(
        children: <Widget>[
          if (wide)
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  icon: Icon(Icons.grid_view),
                  label: Text('Shop'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.shopping_cart_outlined),
                  label: Text('Cart'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: Text('Chat'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune),
                  label: Text('Demo'),
                ),
              ],
            ),
          Expanded(child: pages[_tab]),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                Kletso.instance.screen(
                  const <String>['shop', 'cart', 'chat', 'demo'][i],
                );
              },
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.grid_view),
                  label: 'Shop',
                ),
                NavigationDestination(
                  icon: Icon(Icons.shopping_cart_outlined),
                  label: 'Cart',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: 'Chat',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Demo'),
              ],
            ),
      floatingActionButton: _tab == 2
          ? null
          : KletsoLauncher(presentation: AppSettings.instance.presentation),
    );
  }
}

final class _ConnectionDot extends StatelessWidget {
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<KletsoConnectionState>(
    valueListenable: Kletso.instance.connection.asFlutter(),
    builder: (context, state, _) {
      final color = switch (state) {
        KletsoConnectionState.open => const Color(0xFF22C55E),
        KletsoConnectionState.connecting ||
        KletsoConnectionState.reconnecting => const Color(0xFFF5A623),
        KletsoConnectionState.closed => const Color(0xFFEF4444),
      };
      return Tooltip(
        message: 'Kletso: ${state.name}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              state.name,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    },
  );
}

final class _Catalog extends StatelessWidget {
  const _Catalog({required this.onView, required this.onAdd});
  final void Function(Product) onView;
  final void Function(Product) onAdd;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1100
        ? 4
        : width > 700
        ? 3
        : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: catalog.length,
      itemBuilder: (context, i) {
        final p = catalog[i];
        return ProductCard(
          sku: p.sku,
          name: p.name,
          price: p.price,
          rating: p.rating,
          inStock: p.inStock,
          onView: () => onView(p),
          onAdd: () => onAdd(p),
        );
      },
    );
  }
}

final class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.product});
  final Product product;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

final class _ProductPageState extends State<ProductPage> {
  @override
  void initState() {
    super.initState();
    Kletso.instance
      ..updateContext(<String, Object?>{'viewingSku': widget.product.sku})
      ..screen('product');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E2A44),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: p.color,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(p.icon, size: 96, color: const Color(0xFF1E2A44)),
          ),
          const SizedBox(height: 16),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E2A44),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rupees(p.price),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF6A2B),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Opened from the chat via the local action `open_product`, or from the grid. The agent knows you are viewing ${p.sku} through the runtime context.',
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => unawaited(Kletso.instance.open(context)),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Ask about this product'),
          ),
        ],
      ),
    );
  }
}

final class _CartPage extends StatelessWidget {
  const _CartPage({required this.cart});
  final List<Product> cart;

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your cart is empty',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                Kletso.instance.track('cart_abandoned', <String, Object?>{
                  'value': 0,
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('track(cart_abandoned) sent')),
                );
              },
              child: const Text('Fire cart_abandoned trigger'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final p in cart)
          ListTile(
            leading: Icon(p.icon),
            title: Text(p.name),
            trailing: Text(rupees(p.price)),
          ),
        const Divider(),
        ListTile(
          title: const Text(
            'Total',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: Text(
            rupees(cart.fold<int>(0, (a, b) => a + b.price)),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

final class _InlineChatPage extends StatelessWidget {
  const _InlineChatPage();

  @override
  Widget build(BuildContext context) => const KletsoChat(showHeader: true);
}

final class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

final class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  Future<void> _apply() async {
    setState(() => _busy = true);
    await AppSettings.instance.apply();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        ListTile(
          title: const Text(
            'Kletso demo controls',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            s.liveApi
                ? 'Backend: live runtime · ${s.status}'
                : 'Backend: in-process fake · ${s.status}',
          ),
        ),
        SwitchListTile(
          title: const Text(
            'Live Kletso runtime (api.kletso.ai / wrangler dev)',
          ),
          subtitle: Text(
            s.liveApi ? s.apiBase : 'off = in-process fake backend',
          ),
          value: s.liveApi,
          onChanged: (v) => s.update(() => s.liveApi = v),
        ),
        if (s.liveApi)
          ListTile(
            title: TextFormField(
              initialValue: s.apiBase,
              decoration: const InputDecoration(labelText: 'API base URL'),
              onChanged: (v) => s.apiBase = v,
            ),
          ),
        SwitchListTile(
          title: const Text('Signed in (host JWT)'),
          subtitle: const Text('off = anonymous visitor'),
          value: s.signedIn,
          onChanged: (v) => s.update(() => s.signedIn = v),
        ),
        SwitchListTile(
          title: const Text('Branded theme (KletsoTheme.fromServer)'),
          value: s.brandedTheme,
          onChanged: (v) => s.update(() => s.brandedTheme = v),
        ),
        SwitchListTile(
          title: const Text('Dark mode (KletsoTheme.dark)'),
          value: s.darkMode,
          onChanged: (v) => s.update(() => s.darkMode = v),
        ),
        SwitchListTile(
          title: const Text('Seed the 20-message history'),
          value: s.seedHistory,
          onChanged: (v) => s.update(() => s.seedHistory = v),
        ),
        SwitchListTile(
          title: const Text('Drop the socket every 6 events'),
          subtitle: const Text('exercise reconnect + seq replay'),
          value: s.dropSockets,
          onChanged: (v) => s.update(() => s.dropSockets = v),
        ),
        SwitchListTile(
          title: const Text('Expire the token once (4403)'),
          value: s.expireToken,
          onChanged: (v) => s.update(() => s.expireToken = v),
        ),
        SwitchListTile(
          title: const Text('Duplicate every 3rd frame'),
          value: s.duplicates,
          onChanged: (v) => s.update(() => s.duplicates = v),
        ),
        SwitchListTile(
          title: const Text('Play real sample media'),
          subtitle: const Text('video/audio blocks use public sample files'),
          value: s.sampleMedia,
          onChanged: (v) => s.update(() => s.sampleMedia = v),
        ),
        SwitchListTile(
          title: const Text('OS tray for `system` notifications'),
          subtitle: const Text(
            'off = SDK banner fallback · applies immediately',
          ),
          value: s.systemTray,
          onChanged: (v) {
            s.update(() => s.systemTray = v);
            Kletso.instance.onSystemNotification = v
                ? AcmeNotifier.instance.show
                : null;
          },
        ),
        const ListTile(
          title: Text(
            'Proactive notifications',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'Silent app events → workflow rules on the server → app.notify. '
            'Nothing is posted in the chat unless the rule says so.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Enter store geofence'),
                onPressed: () => Kletso.instance.track(
                  'geofence_entered',
                  <String, Object?>{'store': 'Shibuya'},
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.credit_card_off_outlined),
                label: const Text('Payment failed'),
                onPressed: () => Kletso.instance.track(
                  'payment_failed',
                  <String, Object?>{'method': 'Visa •••• 4242'},
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Order shipped'),
                onPressed: () => Kletso.instance.track(
                  'order_shipped',
                  <String, Object?>{'orderId': 'ORD-2201'},
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.notifications_paused_outlined),
                label: const Text('Simulate push (backgrounded)'),
                onPressed: () {
                  // What firebase_messaging's onMessage handler would do
                  // with the data map the runtime sent while the app was
                  // in the background.
                  final backend = AppSettings.instance.backend;
                  if (backend == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Push simulation needs the fake backend; with the live runtime use POST /v1/notifications with a secret key.',
                        ),
                      ),
                    );
                    return;
                  }
                  final user = Kletso.instance.session.value!.endUser.id;
                  final payload = backend.sendPush(
                    user,
                    const KletsoAppNotification(
                      notificationId: 'ntf_flash_sale',
                      title: 'Flash sale: 20% off trail gear',
                      body:
                          'Ends in one hour. Tap to browse with the assistant.',
                      channel: KletsoNotificationChannel.toast,
                      openChat: true,
                    ),
                  );
                  final fresh = Kletso.instance.handlePushPayload(payload);
                  if (!fresh) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Push already handled (deduped on notificationId)',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Presentation'),
          trailing: SegmentedButton<KletsoPresentation>(
            segments: const <ButtonSegment<KletsoPresentation>>[
              ButtonSegment(
                value: KletsoPresentation.sheet,
                label: Text('Sheet'),
              ),
              ButtonSegment(
                value: KletsoPresentation.fullscreen,
                label: Text('Full'),
              ),
            ],
            selected: <KletsoPresentation>{s.presentation},
            onSelectionChanged: (v) => s.update(() => s.presentation = v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : _apply,
            child: Text(
              _busy ? 'Re-creating client…' : 'Apply (re-init Kletso)',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => s.backend?.dropAllSockets(),
                child: const Text('Drop sockets now'),
              ),
              OutlinedButton(
                onPressed: () => s.backend?.expireTokens(),
                child: const Text('Expire token now'),
              ),
              OutlinedButton(
                onPressed: () =>
                    unawaited(Kletso.instance.logout().then((_) => _apply())),
                child: const Text('Logout + re-init'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Server → app: say "open trail runner" and the agent navigates the app (app.command, opt-in). Chat → app: tap "Add to cart" on a product card in the chat and check the Cart tab. Try in chat: "flight", "hotel", "products under 2000", "sales", "cancel my order", "callback", "order", "long", "error", "talk to a human".',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}
