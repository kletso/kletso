import 'dart:typed_data';

import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:test/test.dart';

void main() {
  final clientFrames = (KletsoFixtures.realtimeClientFrames! as List)
      .cast<Map<String, Object?>>();
  final serverFrames = (KletsoFixtures.realtimeServerFrames! as List)
      .cast<Map<String, Object?>>();

  test('client frame fixtures cover every frame type and round-trip', () {
    final seen = <Type>{};
    for (final raw in clientFrames) {
      final f = KletsoClientFrame.fromJson(raw);
      seen.add(f.runtimeType);
      expect(f.t, raw['t']);
      expect(
        jsonEquals(f.toJson(), raw),
        isTrue,
        reason: '$raw vs ${f.toJson()}',
      );
      expect(KletsoClientFrame.fromJson(f.toJson()), f);
      expect(f.toString(), contains(f.t));
    }
    expect(seen, <Type>{
      KletsoAuthFrame,
      KletsoMessageFrame,
      KletsoActionFrame,
      KletsoContextFrame,
      KletsoTrackFrame,
      KletsoScreenFrame,
      KletsoSwitchFrame,
      KletsoTypingFrame,
      KletsoPingFrame,
      KletsoVoiceStartFrame,
      KletsoVoiceStopFrame,
      KletsoVoiceCommitFrame,
      KletsoVoicePlayedFrame,
      KletsoVoiceTextFrame,
    });
  });

  test('voice frames default and parse their enums', () {
    final start =
        KletsoClientFrame.fromJson({'t': 'voice.start', 'clientId': 'c'})
            as KletsoVoiceStartFrame;
    expect(start.mode, KletsoVoiceMode.vad);
    expect(start.sampleRate, 24000);
    expect(
      (KletsoClientFrame.fromJson({'t': 'voice.stop', 'reason': 'warp'})
              as KletsoVoiceStopFrame)
          .reason,
      KletsoVoiceStopReason.user,
    );
    expect(
      () => KletsoClientFrame.fromJson({'t': 'voice.played', 'itemId': 'i'}),
      throwsA(isA<KletsoSchemaException>()),
    );
  });

  test('binary audio frames encode, decode and reject junk', () {
    final pcm = Uint8List.fromList(<int>[0, 0, 0xFF, 0x7F, 0x00, 0x80]);
    final f = KletsoAudioFrame(kind: KletsoAudioFrame.audioIn, pcm: pcm);
    final wire = f.encode();
    expect(wire.first, 0x01);
    expect(wire.length, 7);
    final back = KletsoAudioFrame.decode(wire)!;
    expect(back.kind, KletsoAudioFrame.audioIn);
    expect(back.pcm, pcm);
    expect(back.duration.inMicroseconds, 3 * 1000000 ~/ 24000);
    expect(back.rms, closeTo(0.816, 0.01));
    expect(KletsoAudioFrame.decode(<int>[]), isNull);
    expect(KletsoAudioFrame.decode(<int>[0x09, 0, 0]), isNull);
    expect(KletsoAudioFrame.decode(<int>[0x02, 0]), isNull, reason: 'odd');
    expect(
      KletsoAudioFrame.decode(Uint8List(KletsoAudioFrame.maxBytes + 1)),
      isNull,
    );
    expect(
      KletsoAudioFrame(kind: KletsoAudioFrame.audioOut, pcm: Uint8List(0)).rms,
      0,
    );
  });

  test('server frame fixtures cover every frame type and round-trip', () {
    final seen = <Type>{};
    for (final raw in serverFrames) {
      final f = KletsoServerFrame.fromJson(raw);
      seen.add(f.runtimeType);
      expect(
        jsonEquals(f.toJson(), raw),
        isTrue,
        reason: '$raw vs ${f.toJson()}',
      );
      expect(KletsoServerFrame.fromJson(f.toJson()), f);
    }
    expect(seen, <Type>{
      KletsoReadyFrame,
      KletsoPongFrame,
      KletsoEventFrame,
      KletsoErrorFrame,
    });
  });

  test('event frames carry a parsed envelope', () {
    final f = KletsoServerFrame.fromJson(serverFrames[3]) as KletsoEventFrame;
    expect(f.event.seq, 42);
    expect(f.event.payload, isA<KletsoMessageDelta>());
  });

  test(
    'unknown server frames are preserved, unknown client frames rejected',
    () {
      final f = KletsoServerFrame.fromJson({'t': 'hint', 'x': 1});
      expect(f, isA<KletsoUnknownServerFrame>());
      expect(f.toJson(), {'t': 'hint', 'x': 1});
      expect(
        () => KletsoClientFrame.fromJson({'t': 'teleport'}),
        throwsA(isA<KletsoSchemaException>()),
      );
      expect(
        () => KletsoClientFrame.fromJson({'t': 'message'}),
        throwsA(isA<KletsoSchemaException>()),
      );
      expect(
        () => KletsoServerFrame.fromJson({'t': 'ready'}),
        throwsA(isA<KletsoSchemaException>()),
      );
      expect(
        () => KletsoServerFrame.fromJson(7),
        throwsA(isA<KletsoSchemaException>()),
      );
    },
  );

  test('defaults', () {
    expect(const KletsoAuthFrame(token: 'kst_x').toJson(), {
      't': 'auth',
      'token': 'kst_x',
      'after': 0,
    });
    expect(const KletsoMessageFrame(clientId: 'c', text: 'hi').toJson(), {
      't': 'message',
      'text': 'hi',
      'value': null,
      'clientId': 'c',
    });
    expect(const KletsoTrackFrame(name: 'x').toJson(), {
      't': 'track',
      'name': 'x',
    });
    expect(const KletsoErrorFrame(code: 'c', message: 'm').retryable, isFalse);
    expect(KletsoCloseCodes.tokenExpired, 4403);
    expect(KletsoCloseCodes.authFailed, 4401);
    expect(const KletsoContextFrame.merge({'a': 1}).toJson(), {
      't': 'context',
      'merge': {'a': 1},
    });
    expect(const KletsoContextFrame.replace({}).replace, isEmpty);
    expect(
      () => KletsoClientFrame.fromJson({'t': 'context'}),
      throwsA(isA<KletsoSchemaException>()),
    );
    expect(
      () => KletsoClientFrame.fromJson({
        't': 'context',
        'merge': <String, Object?>{},
        'replace': <String, Object?>{},
      }),
      throwsA(isA<KletsoSchemaException>()),
    );
    expect(const KletsoPingFrame().hashCode, const KletsoPingFrame().hashCode);
  });
}
