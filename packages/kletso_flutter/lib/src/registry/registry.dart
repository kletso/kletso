import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kletso_core/kletso_core.dart';

import 'build_context.dart';

/// Builds the widget for one component node.
typedef KletsoComponentBuilder =
    Widget Function(KletsoBuildContext ctx, KletsoNode node);

/// Runs a `local` action on the device.
typedef KletsoActionHandler =
    FutureOr<void> Function(JsonMap args, KletsoActionContext ctx);

/// Host-registered component builders and their specs.
///
/// Lookup precedence when rendering: a builder registered here wins, then the
/// SDK built-ins, then the fallback.
final class KletsoComponentRegistry {
  /// Creates an empty registry.
  KletsoComponentRegistry();

  final Map<String, KletsoComponentBuilder> _builders =
      <String, KletsoComponentBuilder>{};
  final Map<String, KletsoComponentSpec> _specs =
      <String, KletsoComponentSpec>{};

  /// Registers [builder] for [type]; replaces an existing one. Pass [spec]
  /// so the type can be synced to the dashboard.
  void register(
    String type,
    KletsoComponentBuilder builder, {
    KletsoComponentSpec? spec,
  }) {
    _builders[type] = builder;
    if (spec != null) _specs[type] = spec;
  }

  /// Registers a spec'd component.
  void registerSpec(KletsoComponentSpec spec, KletsoComponentBuilder builder) =>
      register(spec.type, builder, spec: spec);

  /// Removes [type].
  void unregister(String type) {
    _builders.remove(type);
    _specs.remove(type);
  }

  /// The builder for [type], if registered.
  KletsoComponentBuilder? builderFor(String type) => _builders[type];

  /// Whether [type] is registered.
  bool contains(String type) => _builders.containsKey(type);

  /// Registered type names.
  Set<String> get types => Set<String>.unmodifiable(_builders.keys);

  /// Registered specs by type.
  Map<String, KletsoComponentSpec> get specs =>
      Map<String, KletsoComponentSpec>.unmodifiable(_specs);
}

/// Host-registered handlers for `local` actions.
final class KletsoActionRegistry {
  /// Creates an empty registry.
  KletsoActionRegistry();

  final Map<String, KletsoActionHandler> _handlers =
      <String, KletsoActionHandler>{};

  /// Registers [handler] for [name]; replaces an existing one.
  void register(String name, KletsoActionHandler handler) =>
      _handlers[name] = handler;

  /// Removes [name].
  void unregister(String name) => _handlers.remove(name);

  /// The handler for [name], if registered.
  KletsoActionHandler? handlerFor(String name) => _handlers[name];

  /// Registered action names.
  Set<String> get names => Set<String>.unmodifiable(_handlers.keys);
}
