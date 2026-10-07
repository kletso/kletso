import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'avatar_face.dart';
import 'kletso_avatar_face.g.dart';

/// Drives [KletsoAvatarMood] and the lip-sync [level] for a [KletsoAvatar].
///
/// Hosts rarely need more than one per chat surface: share it between the
/// launcher bubble, the bot bubbles and (later) the voice sheet so the
/// mascot shows one consistent mood. Pure Dart besides [ChangeNotifier].
final class KletsoAvatarController extends ChangeNotifier {
  /// Creates a controller. [defaultMood] is shown once no rule/[setMood] ttl
  /// is active (defaults to [KletsoAvatarMood.neutral]). [allowedMoods]
  /// restricts which moods this controller will show (default: all); a
  /// disallowed mood clamps to [defaultMood]. [rules] overrides the protocol
  /// default rule set used by [applyRule]. [clock] is injectable so tests can
  /// control the lip-sync envelope's timing; defaults to [DateTime.now].
  /// [createTimer] is injectable so tests can fake the ttl timer instead of
  /// waiting on the real clock; defaults to the real [Timer.new].
  KletsoAvatarController({
    this.defaultMood = KletsoAvatarMood.neutral,
    Set<KletsoAvatarMood>? allowedMoods,
    List<(String on, KletsoAvatarMood mood, int ttlMs)>? rules,
    DateTime Function()? clock,
    Timer Function(Duration duration, void Function() callback)? createTimer,
  }) : allowedMoods = allowedMoods ?? Set<KletsoAvatarMood>.of(_allMoods),
       _rules = rules ?? _defaultRules,
       _clock = clock ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new {
    _mood = this.allowedMoods.contains(defaultMood)
        ? defaultMood
        : KletsoAvatarMood.neutral;
  }

  static const Iterable<KletsoAvatarMood> _allMoods = KletsoAvatarMood.values;

  static final List<(String on, KletsoAvatarMood mood, int ttlMs)>
  _defaultRules = KletsoAvatarFaceData.defaultRules
      .map((r) => (r.$1, KletsoAvatarMood.parse(r.$2), r.$3))
      .toList(growable: false);

  /// Mood shown once no [setMood] ttl or rule is active.
  final KletsoAvatarMood defaultMood;

  /// Moods this controller may show; others clamp to [defaultMood].
  final Set<KletsoAvatarMood> allowedMoods;

  final List<(String on, KletsoAvatarMood mood, int ttlMs)> _rules;
  final DateTime Function() _clock;
  final Timer Function(Duration duration, void Function() callback)
  _createTimer;

  Timer? _ttlTimer;
  late KletsoAvatarMood _mood;
  double _level = 0;
  DateTime? _lastLevelAt;

  /// The current mood.
  KletsoAvatarMood get mood => _mood;

  /// The lip-sync level after the attack/release envelope (`0`..`1`); only
  /// meaningful while [mood] is [KletsoAvatarMood.speaking].
  double get level => _level;

  /// Sets [mood] for [ttl] (`null`/[Duration.zero] = until the next change).
  /// A [mood] outside [allowedMoods] clamps to [defaultMood]. [source] is
  /// informational only, mirroring the server `avatar.mood` event's
  /// `source` field (`'rule' | 'agent' | 'heuristic'`); it does not change
  /// behaviour here.
  void setMood(KletsoAvatarMood mood, {Duration? ttl, String source = 'rule'}) {
    _ttlTimer?.cancel();
    _ttlTimer = null;
    _mood = allowedMoods.contains(mood) ? mood : defaultMood;
    notifyListeners();
    if (ttl != null && ttl > Duration.zero) {
      _ttlTimer = _createTimer(ttl, () {
        _ttlTimer = null;
        _mood = defaultMood;
        notifyListeners();
      });
    }
  }

  /// Looks up [on] in the custom `rules` passed to the constructor (or the
  /// protocol default set, `packages/design/avatar.json` `rules.default`)
  /// and applies its mood/ttl via [setMood]. A no-op if nothing matches.
  void applyRule(String on) {
    for (final rule in _rules) {
      if (rule.$1 == on) {
        final ttlMs = rule.$3;
        setMood(
          rule.$2,
          ttl: ttlMs > 0 ? Duration(milliseconds: ttlMs) : null,
          source: 'rule',
        );
        return;
      }
    }
  }

  /// Feeds a new playback RMS sample (`0`..`1`) through the attack/release
  /// envelope from `packages/design/avatar.json` `lipsync`, updating [level].
  /// Values outside `0..1` are clamped.
  void setLevel(double raw) {
    final clamped = raw < 0 ? 0.0 : (raw > 1 ? 1.0 : raw);
    final target = (clamped * KletsoAvatarFaceData.gain)
        .clamp(0.0, 1.0)
        .toDouble();
    final now = _clock();
    final rising = target >= _level;
    final tauMs = rising
        ? KletsoAvatarFaceData.attackMs
        : KletsoAvatarFaceData.releaseMs;
    final double alpha;
    if (_lastLevelAt == null || tauMs <= 0) {
      alpha = 1;
    } else {
      final dtMs = now.difference(_lastLevelAt!).inMicroseconds / 1000.0;
      alpha = (dtMs / tauMs).clamp(0.0, 1.0).toDouble();
    }
    _lastLevelAt = now;
    final next = _level + (target - _level) * alpha;
    _level = next.abs() < 0.001 ? 0.0 : next;
    notifyListeners();
  }

  @override
  void dispose() {
    _ttlTimer?.cancel();
    _ttlTimer = null;
    super.dispose();
  }
}
