// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two TTS defects fixed together:
//
//  1. activeVoices served the 53-entry KOKORO catalog when the engine was
//     Piper and no Piper voice was installed (activeEngine's `default:` branch
//     returns the Kokoro engine), contradicting the getter's own doc. Every
//     picker — desktop character voice, the web voice list — offered voices
//     Piper can never speak, and choosing one produced silence.
//  2. The streaming (call-mode) producer let a generation THROW. ElevenLabs is
//     the one engine that throws instead of returning null, so a 401/429/quota
//     mid-call left completedFiles[idx] unwritten: the in-order collector
//     wedged at that index, the producer died at its own throttle, and
//     speakStreaming never returned — the call overlay stayed busy forever.
//
// Real TtsService, no network: the ElevenLabs HTTP call is served by a
// MockClient installed with http.runWithClient (package:http's top-level
// functions resolve their Client through that zone).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/services.dart';

import '../golden/support/fakes_storage.dart';

void _mockAudioChannels() {
  for (final name in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(name),
          (MethodCall call) async => null,
        );
  }
}

class _VoiceProbeStorage extends FakeStorageService {
  _VoiceProbeStorage({this.engine = 'piper'}) {
    ttsSettings.setTtsEnabled(true);
    ttsSettings.setTtsEngine(engine);
    ttsSettings.setTtsVoiceModel('rachel');
    ttsSettings.setTtsReplaceCurlyQuotes(true);
    ttsSettings.setTtsConcurrency(2);
    ttsSettings.setTtsAudioLookahead(4);
    ttsSettings.setElevenlabsApiKey('test-key');
    ttsSettings.setElevenlabsModel('eleven_turbo_v2');
    sttSettings.setCallBufferSentences(2);
  }

  final String engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_mockAudioChannels);

  TtsService makeTts(_VoiceProbeStorage storage) {
    final tts = TtsService(storage, VoiceManager(storage));
    addTearDown(tts.dispose);
    return tts;
  }

  group('activeVoices never offers Kokoro voices under Piper', () {
    test('Piper with nothing installed lists no voices at all', () async {
      final tts = makeTts(_VoiceProbeStorage(engine: 'piper'));

      // First read is the stale-cache branch (it also kicks off a refresh).
      expect(
        tts.activeVoices,
        isEmpty,
        reason:
            'Piper voices live on disk; falling back to activeEngine here '
            'hands out the Kokoro catalog, and picking one of those is '
            'silence the user cannot diagnose',
      );

      await tts.refreshAvailableVoices();
      expect(tts.activeVoices, isEmpty);
    });

    test('Kokoro still lists its built-in catalog', () async {
      final tts = makeTts(_VoiceProbeStorage(engine: 'kokoro'));

      expect(tts.activeVoices, isNotEmpty);
      await tts.refreshAvailableVoices();
      expect(tts.activeVoices, isNotEmpty);
      expect(tts.activeVoices.any((v) => v.id == 'af_heart'), isTrue);
    });
  });

  group('speakStreaming survives an engine that throws mid-call', () {
    test('an ElevenLabs 429 ends the call cleanly instead of hanging', () async {
      final tts = makeTts(_VoiceProbeStorage(engine: 'elevenlabs'));
      var requests = 0;

      await http.runWithClient(
        () => tts
            .speakStreaming(
              Stream.fromIterable([
                'The first spoken sentence arrives.',
                'The second spoken sentence follows it.',
                'The third spoken sentence closes the reply.',
              ]),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => fail(
                'speakStreaming never returned — a throwing generation wedges '
                'the in-order collector and kills the producer, so the call '
                'overlay stays busy until the user hangs up',
              ),
            ),
        () => MockClient((request) async {
          requests++;
          return http.Response(
            '{"detail": {"status": "too_many_requests"}}',
            429,
          );
        }),
      );

      expect(requests, greaterThan(0), reason: 'the engine really was called');
      expect(tts.isSpeaking, isFalse);
      expect(tts.isGenerating, isFalse);
      expect(tts.nowSpeaking, isNull);
      expect(
        tts.lastError,
        contains('rate limit'),
        reason:
            'the failure must reach the user, not vanish into an unhandled '
            'async error',
      );
    });
  });
}
