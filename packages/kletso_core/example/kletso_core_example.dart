// Talk to a Kletso agent without a backend: the fake backend answers like the
// Acme demo. Run with `dart run example/kletso_core_example.dart`.
import 'dart:io';

import 'package:kletso_core/fake.dart';
import 'package:kletso_core/kletso_core.dart';

Future<void> main() async {
  final backend = KletsoFakeBackend(scenario: const KletsoFakeScenario.demo());
  final client = await Kletso.init(
    KletsoConfig(publishableKey: 'kl_pub_dev_example', agentId: 'agt_demo'),
    api: backend,
    transport: backend,
  );

  await client.identifyAnonymous();
  client.messages.addListener(() {
    stdout.writeln(
      '${client.messages.value.length} messages in the conversation',
    );
  });

  await client.send(const KletsoOutbound.text('products under 2000'));
  // Give the fake backend a moment to stream its answer (text + a rendered surface).
  await Future<void>.delayed(const Duration(seconds: 2));

  await client.dispose();
}
