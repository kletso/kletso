import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../blocks/support.dart';
import '../launcher/presentation.dart';
import '../registry/ui_bindings.dart';
import '../surface/surface_view.dart';
import '../theme/kletso_theme.dart';

/// Shows an `app.notify` notification in the OS tray. Return `true` when it
/// was shown; `false` (or `null` notifier) makes the SDK fall back to an
/// in-app banner. Hosts wire `flutter_local_notifications`, the browser
/// `Notification` API or their push plugin here; the SDK bundles none.
typedef KletsoSystemNotifier = Future<bool> Function(KletsoNotification n);

/// Renders proactive notifications from `client.notifications` on top of the
/// app: banner (top), toast (bottom), alert (dialog) and the fallback for
/// `system` when the host has no [KletsoUi.systemNotifier]. Tapping runs the
/// notification's action and/or opens the chat on its conversation.
///
/// Mount it once, above the navigator, through `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) =>
///       KletsoNotificationHost(client: Kletso.instance, child: child!),
/// )
/// ```
final class KletsoNotificationHost extends StatefulWidget {
  /// Creates the host.
  const KletsoNotificationHost({
    required this.client,
    required this.child,
    super.key,
    this.theme,
    this.presentation = KletsoPresentation.sheet,
    this.bannerDuration = const Duration(seconds: 8),
    this.toastDuration = const Duration(seconds: 4),
    this.maxVisible = 2,
    this.onTap,
  });

  /// The client whose notifications to render.
  final KletsoClient client;

  /// The app.
  final Widget child;

  /// Theme override; defaults to the ambient [KletsoTheme].
  final KletsoTheme? theme;

  /// How `openChat` presents the chat.
  final KletsoPresentation presentation;

  /// Default banner lifetime when the payload has no `ttlSeconds`.
  final Duration bannerDuration;

  /// Default toast lifetime when the payload has no `ttlSeconds`.
  final Duration toastDuration;

  /// Banners shown at once; older ones are dropped.
  final int maxVisible;

  /// Called after a tap was handled (analytics, deep links).
  final void Function(KletsoNotification n)? onTap;

  @override
  State<KletsoNotificationHost> createState() => _KletsoNotificationHostState();
}

final class _KletsoNotificationHostState extends State<KletsoNotificationHost> {
  StreamSubscription<KletsoNotification>? _sub;
  final List<_Shown> _banners = <_Shown>[];
  final List<_Shown> _toasts = <_Shown>[];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(KletsoNotificationHost old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) _listen();
  }

  void _listen() {
    unawaited(_sub?.cancel());
    _sub = widget.client.notifications.listen(_onNotification);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    for (final s in <_Shown>[..._banners, ..._toasts]) {
      s.timer?.cancel();
    }
    super.dispose();
  }

  KletsoUi get _ui => KletsoUi.of(widget.client);

  Future<void> _onNotification(KletsoNotification n) async {
    if (!mounted) return;
    switch (n.channel) {
      case KletsoNotificationChannel.banner:
        _show(_banners, n, n.payload.ttl ?? widget.bannerDuration);
        _ui.reportNotification(n, KletsoNotificationOutcome.shown);
      case KletsoNotificationChannel.toast:
        _show(_toasts, n, n.payload.ttl ?? widget.toastDuration);
        _ui.reportNotification(n, KletsoNotificationOutcome.shown);
      case KletsoNotificationChannel.alert:
        await _alert(n);
      case KletsoNotificationChannel.system:
        final shown = await _ui.systemNotifier?.call(n) ?? false;
        _ui.reportNotification(
          n,
          shown
              ? KletsoNotificationOutcome.system
              : KletsoNotificationOutcome.bannerFallback,
        );
        if (!shown && mounted) {
          _show(_banners, n, n.payload.ttl ?? widget.bannerDuration);
        }
      case KletsoNotificationChannel.silent:
        _ui.reportNotification(n, KletsoNotificationOutcome.silent);
        await _act(n);
    }
  }

  void _show(List<_Shown> list, KletsoNotification n, Duration ttl) {
    if (list.any((s) => s.n.id == n.id)) return;
    final shown = _Shown(n);
    shown.timer = Timer(ttl, () => _dismiss(list, shown));
    setState(() {
      list.add(shown);
      while (list.length > widget.maxVisible) {
        list.removeAt(0).timer?.cancel();
      }
    });
  }

  void _dismiss(List<_Shown> list, _Shown s) {
    s.timer?.cancel();
    if (!mounted) return;
    setState(() => list.remove(s));
  }

  Future<void> _alert(KletsoNotification n) async {
    final context = _ui.contextProvider?.call() ?? this.context;
    if (!context.mounted) return;
    _ui.reportNotification(n, KletsoNotificationOutcome.shown);
    final t = widget.theme ?? KletsoTheme.of(context);
    final surface = _surfaceOf(n);
    final act = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusLg),
        ),
        title: Text(n.title, style: t.title.copyWith(color: t.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (n.payload.body != null)
              Text(n.payload.body!, style: t.body.copyWith(color: t.text)),
            if (surface != null) ...<Widget>[
              const SizedBox(height: 12),
              KletsoSurfaceView(surface: surface, client: widget.client),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Dismiss', style: TextStyle(color: t.textMuted)),
          ),
          if (_hasTapTarget(n))
            KletsoButton(
              label: n.payload.action?.label ?? 'Open chat',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
        ],
      ),
    );
    if (act ?? false) await _act(n);
  }

  static bool _hasTapTarget(KletsoNotification n) =>
      n.payload.openChat || n.payload.action != null;

  KletsoSurface? _surfaceOf(KletsoNotification n) {
    final r = n.payload.parseSurface(knownTypes: _ui.knownTypes);
    return r is KletsoSurfaceOk ? r.surface : null;
  }

  /// Runs the tap target through [KletsoUi.openNotification].
  Future<void> _act(KletsoNotification n) async {
    await _ui.openNotification(
      n,
      fallbackContext: context,
      presentation: widget.presentation,
      theme: widget.theme,
    );
    widget.onTap?.call(n);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme ?? KletsoTheme.of(context);
    return Stack(
      children: <Widget>[
        widget.child,
        if (_banners.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final s in _banners)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: KletsoNotificationBanner(
                            key: ValueKey<String>('banner-${s.n.id}'),
                            notification: s.n,
                            theme: t,
                            client: widget.client,
                            surface: _surfaceOf(s.n),
                            onTap: _hasTapTarget(s.n)
                                ? () {
                                    _dismiss(_banners, s);
                                    unawaited(_act(s.n));
                                  }
                                : null,
                            onDismiss: () => _dismiss(_banners, s),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_toasts.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final s in _toasts)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: KletsoNotificationToast(
                        key: ValueKey<String>('toast-${s.n.id}'),
                        notification: s.n,
                        theme: t,
                        onTap: _hasTapTarget(s.n)
                            ? () {
                                _dismiss(_toasts, s);
                                unawaited(_act(s.n));
                              }
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final class _Shown {
  _Shown(this.n);
  final KletsoNotification n;
  Timer? timer;
}

/// The in-app banner card (also used for the `system` fallback).
final class KletsoNotificationBanner extends StatelessWidget {
  /// Creates a banner.
  const KletsoNotificationBanner({
    required this.notification,
    required this.theme,
    required this.onDismiss,
    super.key,
    this.client,
    this.surface,
    this.onTap,
  });

  /// The notification.
  final KletsoNotification notification;

  /// Theme.
  final KletsoTheme theme;

  /// Client for the inline surface's actions.
  final KletsoClient? client;

  /// Inline surface, if the payload carried a valid one.
  final KletsoSurface? surface;

  /// Tap target; `null` when the notification has none.
  final VoidCallback? onTap;

  /// Close.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final n = notification;
    return Semantics(
      liveRegion: true,
      label: 'Notification: ${n.title}',
      child: Dismissible(
        key: ValueKey<String>('dismiss-${n.id}'),
        direction: DismissDirection.up,
        onDismissed: (_) => onDismiss(),
        child: Material(
          color: t.surface,
          elevation: 6,
          shadowColor: t.text.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(t.radiusLg),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radiusLg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: t.primarySoft,
                          borderRadius: BorderRadius.circular(t.radiusMd),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.notifications_active_outlined,
                          color: t.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              n.title,
                              style: t.subtitle.copyWith(color: t.text),
                            ),
                            if (n.payload.body != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  n.payload.body!,
                                  style: t.caption.copyWith(color: t.textMuted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // no tooltip: the host sits above the navigator, so
                      // there is no Overlay for one
                      Semantics(
                        button: true,
                        label: 'Dismiss',
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: onDismiss,
                          icon: Icon(Icons.close, size: 18, color: t.textMuted),
                        ),
                      ),
                    ],
                  ),
                  if (surface != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, right: 6),
                      child: KletsoSurfaceView(
                        surface: surface!,
                        client: client,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom toast pill.
final class KletsoNotificationToast extends StatelessWidget {
  /// Creates a toast.
  const KletsoNotificationToast({
    required this.notification,
    required this.theme,
    super.key,
    this.onTap,
  });

  /// The notification.
  final KletsoNotification notification;

  /// Theme.
  final KletsoTheme theme;

  /// Tap target.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final n = notification;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Notification: ${n.title}',
        child: Material(
          color: t.text,
          elevation: 4,
          borderRadius: BorderRadius.circular(t.radiusPill),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radiusPill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      n.payload.body == null
                          ? n.title
                          : '${n.title} · ${n.payload.body}',
                      style: t.body.copyWith(color: t.surface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTap != null) ...<Widget>[
                    const SizedBox(width: 10),
                    Text(
                      n.payload.action?.label ?? 'Open',
                      style: t.subtitle.copyWith(color: t.primary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
