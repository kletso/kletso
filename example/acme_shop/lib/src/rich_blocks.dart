// Host overrides for the SDK's plugin-free defaults: a live tile map and a
// real video/audio player. This is what "any UI" means in practice: the
// agent emits `map`/`video`/`audio` nodes, Acme decides how they look.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kletso_flutter/kletso_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:video_player/video_player.dart';

/// `map` → flutter_map with OpenStreetMap tiles, markers and the route.
Widget acmeMap(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final markers = node
      .mapList('markers')
      .map(KletsoMapMarker.fromJson)
      .toList();
  final route = node
      .mapList('route')
      .map(
        (p) =>
            LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
      )
      .toList();
  final center = node.map('center');
  final centerLatLng = center.isEmpty
      ? (markers.isEmpty
            ? const LatLng(0, 0)
            : LatLng(markers.first.lat, markers.first.lng))
      : LatLng(
          (center['lat'] as num).toDouble(),
          (center['lng'] as num).toDouble(),
        );
  final open = node.actions.where((a) => a is! KletsoUnknownAction).firstOrNull;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (node.stringOrNull('title') != null) ...<Widget>[
        Text(node.string('title'), style: t.subtitle),
        const SizedBox(height: 8),
      ],
      ClipRRect(
        borderRadius: t.borderRadiusMd,
        child: SizedBox(
          height: 220,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: centerLatLng,
              initialZoom: node.number('zoom', fallback: 12).toDouble(),
            ),
            children: <Widget>[
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ai.kletso.acme_shop',
              ),
              if (route.length > 1)
                PolylineLayer(
                  polylines: <Polyline<Object>>[
                    Polyline<Object>(
                      points: route,
                      color: t.primary,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: <Marker>[
                  for (final m in markers)
                    Marker(
                      point: LatLng(m.lat, m.lng),
                      width: 120,
                      height: 56,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: m.action == null
                            ? null
                            : () => ctx.execute(m.action!),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.place,
                              size: 32,
                              color: m.tone == 'success'
                                  ? t.success
                                  : (m.tone == 'info' ? t.info : t.primary),
                            ),
                            if (m.label != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: t.surface,
                                  borderRadius: t.borderRadiusSm,
                                  border: Border.all(color: t.line),
                                ),
                                child: Text(m.label!, style: t.caption),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (open != null) ...<Widget>[
        const SizedBox(height: 8),
        KletsoButton(
          label: open.label ?? 'Open in Maps',
          variant: 'secondary',
          icon: 'location',
          onPressed: () => ctx.execute(open),
        ),
      ],
    ],
  );
}

/// `video` and `audio` → an inline video_player with play/pause and a seek bar.
Widget acmePlayer(KletsoBuildContext ctx, KletsoNode node) => _AcmePlayer(
  ctx: ctx,
  node: node,
  key: ValueKey<String>('player_${node.id}'),
);

final class _AcmePlayer extends StatefulWidget {
  const _AcmePlayer({required this.ctx, required this.node, super.key});
  final KletsoBuildContext ctx;
  final KletsoNode node;
  @override
  State<_AcmePlayer> createState() => _AcmePlayerState();
}

final class _AcmePlayerState extends State<_AcmePlayer> {
  VideoPlayerController? _controller;
  String? _error;

  bool get _isAudio => widget.node.type == 'audio';

  @override
  void initState() {
    super.initState();
    final src = widget.node.string('src');
    final uri = widget.ctx.urlPolicy.check(src);
    if (uri == null) {
      _error = 'Source not allowed';
      return;
    }
    final c = VideoPlayerController.networkUrl(uri);
    _controller = c;
    unawaited(
      c
          .initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object e) {
            if (mounted) setState(() => _error = 'Could not load media');
          }),
    );
    c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ctx.theme;
    final node = widget.node;
    final c = _controller;
    final title = node.stringOrNull('title');
    final ready = c != null && c.value.isInitialized;
    final pos = ready ? c.value.position : Duration.zero;
    final dur = ready
        ? c.value.duration
        : Duration(seconds: node.number('durationSeconds').toInt());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: t.borderRadiusMd,
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!_isAudio)
            ClipRRect(
              borderRadius: t.borderRadiusSm,
              child: AspectRatio(
                aspectRatio: ready && c.value.aspectRatio > 0
                    ? c.value.aspectRatio
                    : 16 / 9,
                child: ready
                    ? VideoPlayer(c)
                    : _error != null
                    ? _OpenExternally(
                        ctx: widget.ctx,
                        src: widget.node.string('src'),
                        poster: widget.node.stringOrNull('poster'),
                        message: _error!,
                      )
                    : Container(
                        color: t.text,
                        alignment: Alignment.center,
                        child: _error == null
                            ? CircularProgressIndicator(color: t.primary)
                            : Text(
                                _error!,
                                style: t.caption.copyWith(color: t.surface),
                              ),
                      ),
              ),
            ),
          if (!_isAudio) const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Material(
                color: ready ? t.primary : t.line,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: ready
                      ? () => c.value.isPlaying ? c.pause() : c.play()
                      : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      ready && c.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: t.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (title != null)
                      Text(
                        title,
                        style: t.subtitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (node.stringOrNull('subtitle') != null)
                      Text(node.string('subtitle'), style: t.caption),
                    if (_error != null && _isAudio)
                      Text(_error!, style: t.caption.copyWith(color: t.error)),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        activeTrackColor: t.primary,
                        inactiveTrackColor: t.line,
                        thumbColor: t.primary,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: dur.inMilliseconds == 0
                            ? 0
                            : (pos.inMilliseconds / dur.inMilliseconds).clamp(
                                0.0,
                                1.0,
                              ),
                        onChanged: ready
                            ? (v) => unawaited(c.seekTo(dur * v))
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${KletsoFormat.duration(pos.inSeconds)} / ${KletsoFormat.duration(dur.inSeconds)}',
                style: t.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the inline player cannot load the media (codec, CORS, offline):
/// falls back to the SDK behaviour of opening the URL through the host.
final class _OpenExternally extends StatelessWidget {
  const _OpenExternally({
    required this.ctx,
    required this.src,
    required this.poster,
    required this.message,
  });
  final KletsoBuildContext ctx;
  final String src;
  final String? poster;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ctx.theme;
    return Container(
      color: t.text,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, style: t.caption.copyWith(color: t.surface)),
          const SizedBox(height: 8),
          KletsoButton(
            label: 'Open video',
            variant: 'secondary',
            icon: 'link',
            onPressed: () => ctx.openUrl(src),
          ),
        ],
      ),
    );
  }
}
