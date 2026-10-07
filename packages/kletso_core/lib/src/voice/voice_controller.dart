import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:kletso_ui_schema/kletso_ui_schema.dart';
import 'package:meta/meta.dart';

import '../events.dart';
import '../exceptions.dart';
import '../value_listenable.dart';
import 'audio_io.dart';

/// Lifecycle of a voice session as seen by the UI.
enum KletsoVoiceStatus {
  /// No session; [KletsoVoiceController.start] may be called.
  idle,

  /// `voice.start` sent, waiting for `voice.started`.
  connecting,

  /// Open: the microphone is live and the model waits for speech.
  listening,

  /// Open: speech ended, the model or a tool is working.
  thinking,

  /// Open: the assistant is speaking.
  speaking,

  /// The session ended; see [KletsoVoiceController.endReason]. Transient:
  /// the controller returns to [idle] right after.
  ended,
}

/// What the controller needs from the client; implemented by `KletsoClient`.
@internal
abstract interface class KletsoVoiceLink {
  /// Fresh client id for frames that need one.
  String newClientId();

  /// Queues a JSON frame on the connection.
  void sendFrame(KletsoClientFrame frame);

  /// Sends an audio frame; `false` when the connection cannot right now.
  bool sendAudio(KletsoAudioFrame frame);

  /// Whether the open socket can carry audio.
  bool get supportsBinary;

  /// Assistant audio frames from the connection.
  Stream<KletsoAudioFrame> get audio;

  /// Every client event (server envelopes and client errors).
  Stream<KletsoEvent> get events;

  /// Makes sure a conversation is active.
  Future<void> ensureConversation();

  /// Whether the agent offers voice (session bootstrap).
  bool get voiceEnabled;

  /// Whether the agent is configured for push-to-talk.
  bool get pushToTalk;
}

/// Drives one voice session on the active conversation (D78): sends the
/// `voice.*` frames, forwards microphone audio, plays assistant audio through
/// the installed [KletsoAudioIo], tracks the state the server reports and
/// exposes captions and levels for the UI.
///
/// Without an installed [KletsoAudioIo] the controller still works at the
/// protocol level (tests, hosts with their own audio stack): feed PCM with
/// [sendAudio] and read assistant audio from [audioOut].
final class KletsoVoiceController {
  /// Creates a controller bound to [link]. Hosts get it from
  /// `KletsoClient.voice`.
  @internal
  KletsoVoiceController(this._link) {
    _sub = _link.events.listen(_onEvent);
  }

  final KletsoVoiceLink _link;
  late final StreamSubscription<KletsoEvent> _sub;
  StreamSubscription<KletsoAudioFrame>? _audioSub;
  StreamSubscription<Uint8List>? _captureSub;
  KletsoAudioIo? _io;
  Completer<void>? _starting;
  Timer? _playedTimer;
  Timer? _levelDecay;
  DateTime? _answerStartedAt;
  int _answerBytes = 0;
  bool _disposed = false;

  final KletsoValueNotifier<KletsoVoiceStatus> _status =
      KletsoValueNotifier<KletsoVoiceStatus>(KletsoVoiceStatus.idle);
  final KletsoValueNotifier<String> _userTranscript =
      KletsoValueNotifier<String>('');
  final KletsoValueNotifier<String> _caption = KletsoValueNotifier<String>('');
  final KletsoValueNotifier<double> _outputLevel = KletsoValueNotifier<double>(
    0,
  );
  final KletsoValueNotifier<double> _inputLevel = KletsoValueNotifier<double>(
    0,
  );
  final KletsoValueNotifier<bool> _muted = KletsoValueNotifier<bool>(false);
  final StreamController<KletsoAudioFrame> _audioOut =
      StreamController<KletsoAudioFrame>.broadcast();
  KletsoVoiceEndReason? _endReason;
  String? _endMessage;
  String? _captionMessageId;

  // ---- observables ----------------------------------------------------------

  /// Session status.
  KletsoValueListenable<KletsoVoiceStatus> get status => _status;

  /// Whether a session is open (listening, thinking or speaking).
  bool get isActive => switch (_status.value) {
    KletsoVoiceStatus.listening ||
    KletsoVoiceStatus.thinking ||
    KletsoVoiceStatus.speaking => true,
    _ => false,
  };

  /// What the user is saying, as the server transcribes it (partial, then
  /// final; cleared when the assistant starts answering).
  KletsoValueListenable<String> get userTranscript => _userTranscript;

  /// What the assistant is saying right now (the transcript of its speech,
  /// accumulating; cleared on the next user turn).
  KletsoValueListenable<String> get caption => _caption;

  /// Loudness of the assistant's voice, 0..1, for lip-sync. From the audio
  /// IO when installed, otherwise estimated from the arriving frames.
  KletsoValueListenable<double> get outputLevel => _outputLevel;

  /// Loudness of the microphone, 0..1.
  KletsoValueListenable<double> get inputLevel => _inputLevel;

  /// Whether the microphone is muted (audio is captured but not sent).
  KletsoValueListenable<bool> get muted => _muted;

  /// Assistant audio frames (PCM16 24 kHz mono) for hosts that play audio
  /// themselves. Also delivered to the installed [KletsoAudioIo].
  Stream<KletsoAudioFrame> get audioOut => _audioOut.stream;

  /// Why the last session ended, if it has.
  KletsoVoiceEndReason? get endReason => _endReason;

  /// Human-readable reason for the last end (server error text), if any.
  String? get endMessage => _endMessage;

  /// Whether voice can be offered: the agent has it on, the socket can carry
  /// audio, and either an audio IO is installed or the host handles audio.
  bool get available =>
      _link.voiceEnabled && _link.supportsBinary && (_io != null || _hostAudio);
  bool _hostAudio = false;

  /// The installed audio IO, if any.
  KletsoAudioIo? get audioIo => _io;

  /// Whether the agent uses push-to-talk.
  bool get pushToTalk => _link.pushToTalk;

  // ---- setup --------------------------------------------------------------------

  /// Installs the platform audio implementation (done by
  /// `KletsoVoice.install` in `package:kletso_voice`). Pass `null` to remove
  /// it.
  void setAudioIo(KletsoAudioIo? io) {
    _checkNotDisposed();
    _io = io;
  }

  /// Declares that the host plays and captures audio itself (through
  /// [audioOut] and [sendAudio]), so [available] is `true` without an IO.
  // ignore: avoid_positional_boolean_parameters
  void setHostHandlesAudio(bool value) => _hostAudio = value;

  // ---- session ---------------------------------------------------------------

  /// Starts a voice session on the active conversation. Completes when the
  /// server confirms (`voice.started`) or rejects it (the error is thrown:
  /// [KletsoServerException] with code `not_configured`,
  /// `voice_unavailable`, `voice_rate_limited`, …).
  Future<void> start() async {
    _checkNotDisposed();
    if (_status.value != KletsoVoiceStatus.idle) {
      throw const KletsoStateException('a voice session is already running');
    }
    if (!_link.supportsBinary) {
      throw const KletsoServerException(
        'voice needs the WebSocket transport',
        code: 'voice_unavailable',
      );
    }
    final io = _io;
    if (io != null && !await io.requestPermission()) {
      throw const KletsoServerException(
        'microphone permission denied',
        code: 'permission_denied',
      );
    }
    await _link.ensureConversation();
    _endReason = null;
    _endMessage = null;
    _userTranscript.value = '';
    _caption.value = '';
    _status.value = KletsoVoiceStatus.connecting;
    final starting = _starting = Completer<void>();
    _link.sendFrame(
      KletsoVoiceStartFrame(
        clientId: _link.newClientId(),
        mode: _link.pushToTalk ? KletsoVoiceMode.ptt : KletsoVoiceMode.vad,
      ),
    );
    try {
      await starting.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _status.value = KletsoVoiceStatus.idle;
      _starting = null;
      throw const KletsoTimeoutException('no answer to voice.start');
    }
  }

  /// Ends the session. Safe to call when none is running.
  Future<void> stop({bool background = false}) async {
    if (_disposed) return;
    if (_status.value == KletsoVoiceStatus.idle) return;
    _link.sendFrame(
      KletsoVoiceStopFrame(
        reason: background
            ? KletsoVoiceStopReason.background
            : KletsoVoiceStopReason.user,
      ),
    );
    await _stopAudio();
    if (_status.value == KletsoVoiceStatus.connecting) {
      _starting?.completeError(
        const KletsoStateException('voice session cancelled'),
      );
      _starting = null;
      _status.value = KletsoVoiceStatus.idle;
    }
  }

  /// Push-to-talk release: answer what was said since the button went down.
  void commit() {
    if (!isActive) return;
    _link.sendFrame(const KletsoVoiceCommitFrame());
  }

  /// Sends typed text into the voice session (the voice model answers aloud).
  void sendText(String text) {
    if (!isActive || text.trim().isEmpty) return;
    _link.sendFrame(KletsoVoiceTextFrame(text: text.trim()));
  }

  /// Mutes or unmutes the microphone without ending the session.
  // ignore: avoid_positional_boolean_parameters
  void setMuted(bool value) => _muted.value = value;

  /// Sends one chunk of microphone PCM16 (24 kHz mono). Hosts with their own
  /// capture call this; the installed IO is wired automatically.
  void sendAudio(Uint8List pcm) {
    if (!isActive || _muted.value || pcm.isEmpty) return;
    final frame = KletsoAudioFrame(kind: KletsoAudioFrame.audioIn, pcm: pcm);
    if (_io == null) _inputLevel.value = frame.rms;
    _link.sendAudio(frame);
  }

  /// Releases the controller.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub.cancel();
    await _stopAudio();
    _playedTimer?.cancel();
    _levelDecay?.cancel();
    _status.dispose();
    _userTranscript.dispose();
    _caption.dispose();
    _outputLevel.dispose();
    _inputLevel.dispose();
    _muted.dispose();
    await _audioOut.close();
  }

  // ---- internals -----------------------------------------------------------------

  void _onEvent(KletsoEvent event) {
    if (_disposed) return;
    if (event is KletsoClientError) {
      final e = event.exception;
      if (_status.value == KletsoVoiceStatus.connecting &&
          e is KletsoServerException &&
          (e.code == 'voice_unavailable' ||
              e.code == 'voice_rate_limited' ||
              e.code == 'conflict' ||
              e.code == 'not_configured')) {
        _failStart(e);
      }
      return;
    }
    if (event is! KletsoServerEvent) return;
    switch (event.payload) {
      case KletsoVoiceStarted():
        _starting?.complete();
        _starting = null;
        _status.value = KletsoVoiceStatus.listening;
        unawaited(_startAudio());
      case KletsoVoiceStateEvent(:final state):
        if (!isActive && _status.value != KletsoVoiceStatus.connecting) return;
        switch (state) {
          case KletsoVoiceState.listening || KletsoVoiceState.idle:
            _status.value = KletsoVoiceStatus.listening;
            _answerStartedAt = null;
            _stopPlayedReports();
          case KletsoVoiceState.thinking:
            _status.value = KletsoVoiceStatus.thinking;
          case KletsoVoiceState.speaking:
            _status.value = KletsoVoiceStatus.speaking;
            _startPlayedReports();
          case KletsoVoiceState.unknown:
            break;
        }
      case KletsoVoiceTranscript(:final text):
        _userTranscript.value = text;
      case KletsoMessageCreated(:final role, :final modality, :final messageId)
          when modality == KletsoMessageModality.voice:
        if (role == KletsoRole.assistant) {
          _captionMessageId = messageId;
          _caption.value = '';
        } else if (role == KletsoRole.user) {
          _caption.value = '';
        }
      case KletsoMessageDelta(:final messageId, :final text, :final modality)
          when modality == KletsoMessageModality.voice:
        if (_captionMessageId == null || _captionMessageId == messageId) {
          _captionMessageId = messageId;
          _caption.value = _caption.value + text;
        }
      case KletsoMessageCompleted(
            :final messageId,
            :final text,
            :final modality,
          )
          when modality == KletsoMessageModality.voice:
        if (_captionMessageId == messageId) _caption.value = text;
      case KletsoVoiceInterrupted():
        unawaited(_flushPlayback());
        _status.value = KletsoVoiceStatus.listening;
      case KletsoVoiceEnded(:final reason):
        _endReason = reason;
        _finish();
      case KletsoErrorEvent(:final code, :final message):
        if (_status.value == KletsoVoiceStatus.connecting) {
          _endMessage = message;
          if (code == 'not_configured' || code == 'voice_unavailable') {
            _failStart(KletsoServerException(message, code: code));
          }
        } else if (isActive && code.startsWith('voice_')) {
          _endMessage = message;
        }
      default:
        break;
    }
  }

  void _failStart(KletsoException e) {
    final starting = _starting;
    _starting = null;
    _status.value = KletsoVoiceStatus.idle;
    if (starting != null && !starting.isCompleted) starting.completeError(e);
  }

  void _finish() {
    _starting?.completeError(
      KletsoServerException(
        _endMessage ?? 'voice session ended',
        code: _endReason?.wire ?? 'voice_ended',
      ),
    );
    _starting = null;
    unawaited(_stopAudio());
    _status.value = KletsoVoiceStatus.ended;
    _status.value = KletsoVoiceStatus.idle;
  }

  Future<void> _startAudio() async {
    _audioSub ??= _link.audio.listen(_onAudioOut);
    final io = _io;
    if (io == null) return;
    try {
      final capture = await io.openCapture();
      _captureSub = capture.listen(sendAudio);
      io.inputLevel.addListener(_mirrorInputLevel);
      io.outputLevel.addListener(_mirrorOutputLevel);
    } on Object catch (e) {
      _endMessage = 'microphone failed: $e';
      await stop();
    }
  }

  void _mirrorInputLevel() => _inputLevel.value = _io?.inputLevel.value ?? 0;
  void _mirrorOutputLevel() => _outputLevel.value = _io?.outputLevel.value ?? 0;

  Future<void> _stopAudio() async {
    _stopPlayedReports();
    await _captureSub?.cancel();
    _captureSub = null;
    await _audioSub?.cancel();
    _audioSub = null;
    final io = _io;
    if (io != null) {
      io.inputLevel.removeListener(_mirrorInputLevel);
      io.outputLevel.removeListener(_mirrorOutputLevel);
      try {
        await io.closeCapture();
        await io.flush();
      } on Object {
        // Platform teardown problems must not break the session end.
      }
    }
    _inputLevel.value = 0;
    _outputLevel.value = 0;
    _answerStartedAt = null;
    _answerBytes = 0;
  }

  void _onAudioOut(KletsoAudioFrame frame) {
    if (!isActive) return;
    _audioOut.add(frame);
    final io = _io;
    if (io != null) {
      io.enqueue(frame.pcm);
    } else {
      // No player: estimate the level from the frames as they arrive so the
      // avatar still moves in demos and tests.
      _outputLevel.value = frame.rms;
      _levelDecay?.cancel();
      _levelDecay = Timer(
        frame.duration + const Duration(milliseconds: 80),
        () {
          if (!_disposed) _outputLevel.value = 0;
        },
      );
    }
    _answerStartedAt ??= clock.now();
    _answerBytes += frame.pcm.lengthInBytes;
  }

  Future<void> _flushPlayback() async {
    _reportPlayed();
    final io = _io;
    if (io != null) await io.flush();
    _outputLevel.value = 0;
    _answerStartedAt = null;
    _answerBytes = 0;
  }

  void _startPlayedReports() {
    _playedTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _reportPlayed(),
    );
  }

  void _stopPlayedReports() {
    _playedTimer?.cancel();
    _playedTimer = null;
  }

  /// Tells the server how much of the current answer has been heard, so an
  /// interruption cuts the transcript in the right place. `current` means
  /// the item being played.
  void _reportPlayed() {
    if (!isActive) return;
    final io = _io;
    final int ms;
    if (io != null) {
      ms = io.playedMs;
    } else {
      final started = _answerStartedAt;
      if (started == null) return;
      final produced = _answerBytes * 1000 ~/ KletsoAudioFrame.bytesPerSecond;
      final elapsed = clock.now().difference(started).inMilliseconds;
      ms = elapsed < produced ? elapsed : produced;
    }
    _link.sendFrame(KletsoVoicePlayedFrame(itemId: 'current', ms: ms));
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw const KletsoStateException('voice controller disposed');
    }
  }
}
