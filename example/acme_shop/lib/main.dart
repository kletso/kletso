import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_flutter/kletso_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'kletso_components.dart';
import 'src/catalog.dart';
import 'src/notifier.dart';
import 'src/product_card.dart';
import 'src/rich_blocks.dart';
import 'src/settings.dart';
import 'src/shop_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance
      .apply(); // creates the Kletso client with the chosen scenario
  runApp(const AcmeShopApp());
}

/// Wires the Kletso client to Acme's widgets: component, actions, url opener.
void registerKletsoIntegration(
  KletsoClient client,
  GlobalKey<NavigatorState> navigator,
) {
  client.ui.contextProvider = () => navigator.currentContext;
  client
    ..registerComponent(productCardSpec.type, (ctx, node) {
      final sku = node.string('sku');
      final local = productBySku(sku);
      return ProductCard(
        sku: sku,
        name: node.string('name', fallback: local?.name ?? sku),
        price: node.number('price', fallback: local?.price ?? 0),
        rating: node.number('rating', fallback: local?.rating ?? 0).toDouble(),
        inStock: node.boolean('inStock', fallback: local?.inStock ?? true),
        compact: true,
        onView: () => ctx.executeAction('view'),
        // "Both" pattern: change the app's own state AND tell the agent.
        onAdd: () {
          if (local != null) addToCart(local);
          unawaited(ctx.executeAction('add'));
        },
      );
    }, spec: productCardSpec)
    ..registerAction('open_product', (args, ctx) async {
      final sku = args['sku'] as String? ?? '';
      final product = productBySku(sku);
      if (product == null) return;
      client.close(); // works for taps and for server commands
      await navigator.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => ProductPage(product: product)),
      );
    })
    ..registerComponent('map', acmeMap)
    ..registerComponent('video', acmePlayer)
    ..registerComponent('audio', acmePlayer)
    ..registerAction('open_checkout', (args, ctx) async {
      Navigator.of(ctx.context).pop();
      ScaffoldMessenger.of(navigator.currentContext!).showSnackBar(
        const SnackBar(
          content: Text('Local action open_checkout → your checkout route'),
        ),
      );
    })
    ..registerAction('open_hotel', (args, ctx) async {
      ScaffoldMessenger.of(navigator.currentContext!).showSnackBar(
        SnackBar(content: Text('Local action open_hotel ${args['id']}')),
      );
    })
    // `system` notifications go to the OS tray through the app's own plugin;
    // off → the SDK shows its in-app banner instead.
    ..onSystemNotification = AppSettings.instance.systemTray
        ? AcmeNotifier.instance.show
        : null
    ..onOpenUrl = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}

final class AcmeShopApp extends StatefulWidget {
  const AcmeShopApp({super.key});

  @override
  State<AcmeShopApp> createState() => _AcmeShopAppState();
}

final class _AcmeShopAppState extends State<AcmeShopApp> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettings);
    _onSettings();
  }

  void _onSettings() {
    _lifecycle?.dispose();
    registerKletsoIntegration(Kletso.instance, _navigator);
    _lifecycle = Kletso.instance.bindAppLifecycle();
    setState(() {});
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final kletsoTheme = settings.brandedTheme
        ? KletsoTheme.fromServer(acmeBranding)
        : KletsoTheme.forBrightness(
            settings.darkMode ? Brightness.dark : Brightness.light,
          );
    return MaterialApp(
      title: 'Acme Shop',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      // Proactive notifications (banner/toast/alert) render above every route.
      builder: (context, child) => KletsoNotificationHost(
        client: Kletso.instance,
        presentation: settings.presentation,
        child: child ?? const SizedBox.shrink(),
      ),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E2A44),
          primary: const Color(0xFF1E2A44),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kletsoTheme],
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6A2B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF141C2F),
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kletsoTheme],
      ),
      home: const ShopHome(),
    );
  }
}

/// What a customer would configure in the dashboard's Branding page.
const Map<String, Object?> acmeBranding = <String, Object?>{
  'primary': '#1E2A44',
  'onPrimary': '#FFFFFF',
  'background': '#F7F7F9',
  'radius': 12,
  'launcher': <String, Object?>{'position': 'bottomRight'},
};
