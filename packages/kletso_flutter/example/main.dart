// Minimal embed: initialise Kletso against the fake backend and show the chat.
// The full Acme Shop example app lives in the Kletso monorepo (apps/example_flutter).
import 'package:flutter/material.dart';
import 'package:kletso_core/fake.dart';
import 'package:kletso_flutter/kletso_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
  await Kletso.init(
    KletsoConfig(publishableKey: 'kl_pub_dev_example', agentId: 'agt_demo'),
    api: backend,
    transport: backend,
  );
  await Kletso.instance.identifyAnonymous();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        extensions: <ThemeExtension<dynamic>>[KletsoTheme.light()],
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Kletso chat')),
        body: const KletsoChat(),
      ),
    );
  }
}
