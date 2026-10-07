import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import 'avatar_controller.dart';
import 'avatar_face.dart';
import 'avatar_painter.dart';
import 'kletso_avatar.dart';

/// The agent's avatar as configured in the dashboard, bound to a client:
/// builds a [KletsoAvatarController] from the session bootstrap's `avatar`
/// block (style, colours, default and allowed moods, rules), applies the
/// rules to protocol events (`agent.typing`, `tool.started`, `voice.state`,
/// …), honours `avatar.mood` events from the agent or the runtime, and feeds
/// the voice output level into the lip-sync envelope (D81/D83).
///
/// `KletsoChat` owns one; hosts that draw the avatar elsewhere create their
/// own and dispose it with the widget.
///
/// It is a [Listenable]: a new session bootstrap (the dashboard changed the
/// style, pictures or moods) reconfigures it and notifies, and the widget
/// returned by [build] rebuilds itself with the new pictures without a
/// restart.
final class KletsoClientAvatar extends ChangeNotifier {
  /// Binds to [client].
  KletsoClientAvatar(this.client) {
    _configure(client.session.value?.avatar ?? const <String, Object?>{});
    client.session.addListener(_onSession);
    _sub = client.events.listen(_onEvent);
    client.voice.outputLevel.addListener(_onLevel);
    client.voice.status.addListener(_onVoiceStatus);
  }

  /// The client.
  final KletsoClient client;

  late KletsoAvatarController _controller;
  late StreamSubscription<KletsoEvent> _sub;
  KletsoAvatarStyle _style = KletsoAvatarStyle.kletso;
  KletsoAvatarColors? _colors;
  Uri? _imageUrl;
  Map<KletsoAvatarMood, Uri> _images = const <KletsoAvatarMood, Uri>{};
  bool _disposed = false;

  /// Drives the face.
  KletsoAvatarController get controller => _controller;

  /// Mascot, customer image or none.
  KletsoAvatarStyle get style => _style;

  /// Colour overrides, if the customer set any.
  KletsoAvatarColors? get colors => _colors;

  /// The customer's single picture for [KletsoAvatarStyle.image]; the
  /// fallback for moods without an entry in [images].
  Uri? get imageUrl => _imageUrl;

  /// The customer's per-mood pictures (`avatar.images` in the bootstrap).
  Map<KletsoAvatarMood, Uri> get images => _images;

  /// The picture shown for [mood]: its own entry, else [imageUrl], else
  /// `null` (the procedural mascot is drawn).
  Uri? imageFor(KletsoAvatarMood mood) => _images[mood] ?? _imageUrl;

  /// Parses an `avatar.images` block (mood id → URL). Only `https://` URLs
  /// for known moods are kept; everything else is ignored.
  static Map<KletsoAvatarMood, Uri> parseImages(Object? images) {
    if (images is! Map) return const <KletsoAvatarMood, Uri>{};
    final out = <KletsoAvatarMood, Uri>{};
    for (final entry in images.entries) {
      final mood = KletsoAvatarMood.parse(entry.key as String?);
      final url = entry.value;
      if (mood == KletsoAvatarMood.unknown || url is! String) continue;
      final uri = _httpsUri(url);
      if (uri != null) out[mood] = uri;
    }
    return Map<KletsoAvatarMood, Uri>.unmodifiable(out);
  }

  static Uri? _httpsUri(String value) {
    if (!value.startsWith('https://')) return null;
    final uri = Uri.tryParse(value);
    return uri != null && uri.host.isNotEmpty ? uri : null;
  }

  /// A ready-to-place face widget that follows this binding's configuration,
  /// including later changes delivered through a new session bootstrap.
  Widget build({double size = 64, bool animate = true}) => ListenableBuilder(
    listenable: this,
    builder: (_, _) => KletsoAvatar(
      controller: _controller,
      size: size,
      style: _style,
      colors: _colors,
      imageProvider: _imageUrl == null
          ? null
          : NetworkImage(_imageUrl.toString()),
      moodImages: _images.isEmpty
          ? null
          : <KletsoAvatarMood, ImageProvider>{
              for (final e in _images.entries)
                e.key: NetworkImage(e.value.toString()),
            },
      animate: animate,
    ),
  );

  void _onSession() {
    final avatar = client.session.value?.avatar;
    if (avatar == null || avatar.isEmpty || _disposed) return;
    _configure(avatar);
    notifyListeners();
  }

  void _configure(JsonMap avatar) {
    final mood = KletsoAvatarMood.parse(avatar['defaultMood'] as String?);
    final moods = (avatar['moods'] as List?)
        ?.whereType<String>()
        .map(KletsoAvatarMood.parse)
        .where((m) => m != KletsoAvatarMood.unknown)
        .toSet();
    final rules = (avatar['rules'] as List?)
        ?.whereType<Map<Object?, Object?>>()
        .map(
          (r) => (
            r['on'] as String? ?? '',
            KletsoAvatarMood.parse(r['mood'] as String?),
            r['ttlMs'] is num ? (r['ttlMs']! as num).toInt() : 0,
          ),
        )
        .where((r) => r.$1.isNotEmpty)
        .toList(growable: false);
    final previous = _controllerOrNull;
    _controllerOrNull = _controller = KletsoAvatarController(
      defaultMood: mood == KletsoAvatarMood.unknown
          ? KletsoAvatarMood.neutral
          : mood,
      allowedMoods: moods == null || moods.isEmpty ? null : moods,
      rules: rules == null || rules.isEmpty ? null : rules,
    );
    previous?.dispose();
    _style = switch (avatar['style']) {
      'image' => KletsoAvatarStyle.image,
      'none' => KletsoAvatarStyle.none,
      _ => KletsoAvatarStyle.kletso,
    };
    final c = avatar['colors'];
    _colors = c is Map
        ? KletsoAvatarColors(
            body: _color(c['body']),
            eye: _color(c['eye']),
            mouth: _color(c['mouth']),
            tongue: _color(c['tongue']),
          )
        : null;
    final img = avatar['imageUrl'];
    _imageUrl = img is String ? _httpsUri(img) : null;
    _images = parseImages(avatar['images']);
  }

  KletsoAvatarController? _controllerOrNull;

  static Color? _color(Object? v) {
    if (v is! String) return null;
    final hex = v.replaceFirst('#', '');
    final full = hex.length == 6 ? 'FF$hex' : hex;
    final n = int.tryParse(full, radix: 16);
    return full.length == 8 && n != null ? Color(n) : null;
  }

  void _onEvent(KletsoEvent e) {
    if (_disposed || e is! KletsoServerEvent) return;
    switch (e.payload) {
      case KletsoAvatarMoodEvent(:final mood, :final ttl, :final source):
        _controller.setMood(
          KletsoAvatarMood.parse(mood),
          ttl: ttl,
          source: source.wire,
        );
      case KletsoAgentTyping():
        _controller.applyRule(KletsoEventTypes.agentTyping);
      case KletsoToolStarted():
        _controller.applyRule(KletsoEventTypes.toolStarted);
      case KletsoToolFinished(:final failed):
        if (failed) _controller.applyRule(KletsoEventTypes.toolFailed);
      case KletsoErrorEvent():
        _controller.applyRule(KletsoEventTypes.error);
      case KletsoMessageCompleted():
        if (client.voice.isActive) return; // voice.state drives the face
        _controller.applyRule(KletsoEventTypes.messageCompleted);
      case KletsoHandoffEvent(:final completed):
        if (!completed) _controller.applyRule(KletsoEventTypes.handoffStarted);
      case KletsoVoiceEnded():
        _controller.applyRule('voice.idle');
      default:
        break;
    }
  }

  void _onVoiceStatus() {
    if (_disposed) return;
    switch (client.voice.status.value) {
      case KletsoVoiceStatus.listening:
        _controller.applyRule('voice.listening');
      case KletsoVoiceStatus.thinking:
        _controller.applyRule('voice.thinking');
      case KletsoVoiceStatus.speaking:
        _controller.applyRule('voice.speaking');
      case KletsoVoiceStatus.idle || KletsoVoiceStatus.ended:
        _controller.applyRule('voice.idle');
      case KletsoVoiceStatus.connecting:
        break;
    }
  }

  void _onLevel() {
    if (!_disposed) _controller.setLevel(client.voice.outputLevel.value);
  }

  /// Releases listeners and the controller.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    client.session.removeListener(_onSession);
    unawaited(_sub.cancel());
    client.voice.outputLevel.removeListener(_onLevel);
    client.voice.status.removeListener(_onVoiceStatus);
    _controller.dispose();
    super.dispose();
  }
}
