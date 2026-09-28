import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

/// One server-sent event.
@immutable
final class KletsoSseEvent {
  /// Creates an event.
  const KletsoSseEvent({this.event = 'message', required this.data, this.id});

  /// `event:` field, `message` when absent.
  final String event;

  /// Concatenated `data:` lines joined with `\n`.
  final String data;

  /// Last `id:` seen in this event (replay cursor).
  final String? id;

  @override
  String toString() => 'KletsoSseEvent($event, id: $id, ${data.length} chars)';
}

/// Parses a `text/event-stream` body per the WHATWG spec: events end at a
/// blank line, `data:` lines accumulate, `id:` and `retry:` are tracked,
/// comment lines (`:`) are ignored, and events split across chunks are
/// reassembled. Bytes go in, events come out.
final class KletsoSseParser {
  /// Creates a parser.
  KletsoSseParser();

  Duration? _retry;
  String? _lastEventId;

  /// Server-suggested reconnect delay from the latest `retry:` line.
  Duration? get retry => _retry;

  /// The last `id:` seen on any event (the replay cursor).
  String? get lastEventId => _lastEventId;

  /// Transforms a byte stream into events.
  Stream<KletsoSseEvent> bind(Stream<List<int>> bytes) {
    final controller = StreamController<KletsoSseEvent>();
    final buffer = _EventBuffer();
    late final StreamSubscription<String> sub;
    sub = bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final event = _feed(line, buffer);
            if (event != null) controller.add(event);
          },
          onError: controller.addError,
          onDone: () {
            final event = buffer.flush(this);
            if (event != null) controller.add(event);
            unawaited(controller.close());
          },
          cancelOnError: false,
        );
    controller.onCancel = sub.cancel;
    return controller.stream;
  }

  /// Feeds one line; returns a completed event when [line] is blank and the
  /// buffer holds data.
  KletsoSseEvent? _feed(String line, _EventBuffer buffer) {
    if (line.isEmpty) return buffer.flush(this);
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final String field;
    var value = '';
    if (colon == -1) {
      field = line;
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    switch (field) {
      case 'event':
        buffer.event = value;
      case 'data':
        buffer.data.add(value);
      case 'id':
        if (!value.contains('\u0000')) buffer.id = value;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null) _retry = Duration(milliseconds: ms);
      default:
        break; // unknown fields are ignored per spec
    }
    return null;
  }
}

final class _EventBuffer {
  String? event;
  final List<String> data = <String>[];
  String? id;

  KletsoSseEvent? flush(KletsoSseParser parser) {
    if (id != null) parser._lastEventId = id;
    if (data.isEmpty) {
      event = null;
      id = null;
      return null;
    }
    final out = KletsoSseEvent(
      event: (event == null || event!.isEmpty) ? 'message' : event!,
      data: data.join('\n'),
      id: id ?? parser.lastEventId,
    );
    event = null;
    data.clear();
    id = null;
    return out;
  }
}
