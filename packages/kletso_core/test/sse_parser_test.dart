import 'dart:async';
import 'dart:convert';

import 'package:kletso_core/kletso_core.dart';
import 'package:test/test.dart';

Future<List<KletsoSseEvent>> parse(List<String> chunks, [KletsoSseParser? p]) {
  final parser = p ?? KletsoSseParser();
  final controller = StreamController<List<int>>();
  final out = parser.bind(controller.stream).toList();
  for (final c in chunks) {
    controller.add(utf8.encode(c));
  }
  unawaited(controller.close());
  return out;
}

void main() {
  test('one event per blank line, multiple per chunk', () async {
    final events = await parse([
      'event: ready\ndata: {"seq":41}\n\nevent: event\ndata: {"a":1}\n\n',
    ]);
    expect(events, hasLength(2));
    expect(events[0].event, 'ready');
    expect(events[0].data, '{"seq":41}');
    expect(events[1].event, 'event');
  });

  test('events split across chunks, even mid-line and mid-UTF-8', () async {
    final text = 'id: 7\ndata: {"text":"héllo wörld"}\n\n';
    final bytes = utf8.encode(text);
    // split inside the multi-byte "é" and elsewhere
    final cut1 = text.indexOf('é') + 1;
    final chunks = <List<int>>[
      bytes.sublist(0, cut1),
      bytes.sublist(cut1, cut1 + 5),
      bytes.sublist(cut1 + 5),
    ];
    final controller = StreamController<List<int>>();
    final parser = KletsoSseParser();
    final out = parser.bind(controller.stream).toList();
    chunks.forEach(controller.add);
    await controller.close();
    final events = await out;
    expect(events.single.data, '{"text":"héllo wörld"}');
    expect(events.single.id, '7');
    expect(parser.lastEventId, '7');
  });

  test(
    'multi-line data joins with newline; comments and unknown fields ignored',
    () async {
      final events = await parse([
        ': keep-alive\ndata: line one\ndata: line two\nfoo: bar\n\n',
      ]);
      expect(events.single.data, 'line one\nline two');
      expect(events.single.event, 'message');
    },
  );

  test('retry and id are tracked; id carries to later events', () async {
    final parser = KletsoSseParser();
    final events = await parse([
      'retry: 2500\nid: 3\ndata: a\n\ndata: b\n\n',
    ], parser);
    expect(parser.retry, const Duration(milliseconds: 2500));
    expect(events[0].id, '3');
    expect(events[1].id, '3');
  });

  test(
    'a dangling event without a trailing blank line is flushed on close',
    () async {
      final events = await parse(['data: tail']);
      expect(events.single.data, 'tail');
    },
  );

  test('field without colon and value without leading space', () async {
    final events = await parse(['data\ndata:x\n\n']);
    expect(events.single.data, '\nx');
    expect(events.single.toString(), contains('message'));
  });

  test('CRLF line endings', () async {
    final events = await parse(['event: ping\r\ndata: 1\r\n\r\n']);
    expect(events.single.event, 'ping');
  });
}
