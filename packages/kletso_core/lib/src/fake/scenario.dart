import 'package:meta/meta.dart';

/// Knobs for `KletsoFakeBackend`: how slow and how unreliable the fake
/// runtime behaves. All defaults are instant and reliable (unit tests); use
/// [KletsoFakeScenario.demo] for a lifelike example app.
@immutable
final class KletsoFakeScenario {
  /// Creates a scenario.
  const KletsoFakeScenario({
    this.apiLatency = Duration.zero,
    this.thinkingDelay = Duration.zero,
    this.deltaDelay = Duration.zero,
    this.toolDelay = Duration.zero,
    this.failHandshakes = 0,
    this.dropSocketAfterEvents,
    this.dropSocketCloseCode = 1001,
    this.duplicateEveryNth,
    this.expireTokenAfterEvents,
    this.rejectToken = false,
    this.rateLimitEveryNthMessage,
    this.seedConversationLog = false,
    this.greeting = true,
    this.sampleMedia = false,
  });

  /// Lifelike timings for the example app, no faults.
  const KletsoFakeScenario.demo({
    this.seedConversationLog = false,
    this.dropSocketAfterEvents,
    this.expireTokenAfterEvents,
    this.duplicateEveryNth,
    this.sampleMedia = true,
  }) : apiLatency = const Duration(milliseconds: 250),
       thinkingDelay = const Duration(milliseconds: 700),
       deltaDelay = const Duration(milliseconds: 45),
       toolDelay = const Duration(milliseconds: 900),
       failHandshakes = 0,
       dropSocketCloseCode = 1001,
       rejectToken = false,
       rateLimitEveryNthMessage = null,
       greeting = true;

  /// Delay of every REST call.
  final Duration apiLatency;

  /// Delay between receiving a user turn and the first event of the reply.
  final Duration thinkingDelay;

  /// Delay between streamed text deltas.
  final Duration deltaDelay;

  /// Duration of a simulated tool call.
  final Duration toolDelay;

  /// The first N `open()` calls throw a network error (tests reconnect and
  /// the WebSocket → SSE fallback).
  final int failHandshakes;

  /// Close every socket with [dropSocketCloseCode] after it delivered this
  /// many events (deploy-style drop; the client must resume via `seq`).
  final int? dropSocketAfterEvents;

  /// Close code for [dropSocketAfterEvents].
  final int dropSocketCloseCode;

  /// Send every Nth event twice (the client must dedupe).
  final int? duplicateEveryNth;

  /// Close the first socket with 4403 after this many events, once (the
  /// client must refresh the token and reconnect).
  final int? expireTokenAfterEvents;

  /// Reject every handshake with 4401 (auth failure path).
  final bool rejectToken;

  /// Answer every Nth user message with a `rate_limited` error frame instead
  /// of a reply.
  final int? rateLimitEveryNthMessage;

  /// Preload the first conversation with the 20-message fixture log.
  final bool seedConversationLog;

  /// Send the agent greeting when a conversation is created.
  final bool greeting;

  /// Replace the fixtures' `cdn.acme.com` media URLs with public sample files
  /// so host video/audio players actually play in demos.
  final bool sampleMedia;
}
