// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The tts_service.dart orchestration net — required by the god-file
// campaign's provability rule BEFORE tts_service.dart is split into
// tts_service.speak.dart / .streaming.dart / .support.dart part files
// (see the split map). Until this file existed, NOTHING constructed a real
// TtsService anywhere in the suite — the only coverage was FakeTtsService's
// compile-time interface pin (test/golden/support/fakes.dart) plus the
// underlying engine tests in test/services/tts/. Zero test had ever driven
// speak()/speakStreaming()/generateAudioFile() themselves.
//
// This net drives the REAL TtsService end to end, offline and
// deterministically, by picking the one engine configuration that can fail
// SAFELY with no network and no local model files: the 'openai' engine with
// an empty API key. OpenAiTtsEngine.generateAudio() checks the key and
// returns null before ever building an HTTP request (see
// lib/services/openai_tts_engine.dart), and the Kokoro-model-readiness block
// inside speak()/speakStreaming() is gated on `ttsEngine == 'kokoro'`, so it
// is never entered. That gives every test a real, fully-wired TtsService
// exercising its actual control flow (voice resolution, the sanitize
// pipeline, engine routing, the busy-state machine, cleanup) without ever
// touching a network socket or a multi-hundred-MB model download — both of
// which the Kokoro/Piper/ElevenLabs-with-a-key paths would require. Where a
// behavior genuinely cannot be reached this way (the replay cache HIT path,
// real generated audio, real playback), it is named in this file's own
// doc comments and in the task's Limitations rather than faked into a
// decorative assertion.
//
// audioplayers' platform channels don't exist headless, so they're mocked
// exactly like test/ui/pages/story_reader_page_interaction_test.dart does.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../golden/support/fakes_storage.dart';

/// TtsService's [AudioPlayer] field is constructed eagerly and immediately
/// fires a platform `create` call; without a mock handler that throws
/// (MissingPluginException) into an unwatched Future, which flutter_test
/// treats as a test failure. Same two channel names, same "answer
/// everything with null" handler as the reader precedent.
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

/// A [FakeStorageService] with every TTS getter TtsService's orchestration
/// actually reads made mutable, plus the two getters
/// (`ttsAudioLookahead`, `callBufferSentences`) the shared fake doesn't
/// implement at all — TtsService's cloud-generation branch and
/// speakStreaming() both read them unconditionally, so without an override
/// here they'd hit the fake's catch-all `noSuchMethod` and throw.
class _TtsProbeStorage extends FakeStorageService {
  _TtsProbeStorage({
    bool enabled = true,
    String engine = 'openai',
    String voiceModel = 'global-voice',
    bool narrateQuotedOnly = false,
    bool replaceCurlyQuotes = true,
  }) {
    ttsSettings.setTtsEnabled(enabled);
    ttsSettings.setTtsEngine(engine);
    ttsSettings.setTtsVoiceModel(voiceModel);
    ttsSettings.setTtsNarrateQuotedOnly(narrateQuotedOnly);
    ttsSettings.setTtsReplaceCurlyQuotes(replaceCurlyQuotes);
    ttsSettings.setTtsConcurrency(2);
    ttsSettings.setTtsAudioLookahead(4);
    sttSettings.setCallBufferSentences(2);
  }
}

/// What a single awaited TtsService call produced: every `print()` /
/// `debugPrint()` line it emitted (both routed through the same capture —
/// speak()'s state/voice/sanitize logs use plain `print`, the routing-
/// decision log uses `kDebugPrint` -> `debugPrint`), plus whether
/// isGenerating / isSpeaking were ever observed true via a real
/// [ChangeNotifier] listener while the call was in flight.
class _Observed {
  _Observed(this.logs, this.sawGenerating, this.sawSpeaking);
  final List<String> logs;
  final bool sawGenerating;
  final bool sawSpeaking;

  bool logsContain(String needle) => logs.any((l) => l.contains(needle));
}

/// Runs [action] against [tts] while capturing console output and the
/// isGenerating/isSpeaking history a real listener would see. This is the
/// harness every pin below rides: print/debugPrint capture makes the
/// private `_sanitizeText`/voice-resolution output observable without
/// touching TtsService's privates, and the listener makes "did this call
/// ever actually start generating" observable without a spy engine.
Future<_Observed> _observe(
  TtsService tts,
  Future<void> Function() action,
) async {
  final logs = <String>[];
  var sawGenerating = false;
  var sawSpeaking = false;
  void listener() {
    if (tts.isGenerating) sawGenerating = true;
    if (tts.isSpeaking) sawSpeaking = true;
  }

  tts.addListener(listener);
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    await runZoned(
      action,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => logs.add(line),
      ),
    );
  } finally {
    debugPrint = originalDebugPrint;
    tts.removeListener(listener);
  }
  return _Observed(logs, sawGenerating, sawSpeaking);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_mockAudioChannels);

  TtsService makeTts(_TtsProbeStorage storage) {
    final tts = TtsService(storage, VoiceManager(storage));
    addTearDown(tts.dispose);
    return tts;
  }

  group('speak() — ttsEnabled gate', () {
    test(
      'disabled: returns immediately, never enters the busy state',
      () async {
        final storage = _TtsProbeStorage(enabled: false);
        final tts = makeTts(storage);

        final observed = await _observe(
          tts,
          () =>
              tts.speak('A perfectly normal line that would otherwise speak.'),
        );

        expect(
          observed.sawGenerating,
          isFalse,
          reason:
              'ttsEnabled=false must gate speak() before it ever sets '
              'isGenerating — this is the very first line of the method',
        );
        expect(observed.sawSpeaking, isFalse);
        expect(tts.isSpeaking, isFalse);
        expect(tts.isGenerating, isFalse);
      },
    );
  });

  group('speak() — voice resolution', () {
    test(
      "a character's voiceKey wins over the global voice, and is logged",
      () async {
        final storage = _TtsProbeStorage(voiceModel: 'global-voice');
        final tts = makeTts(storage);

        final observed = await _observe(
          tts,
          () => tts.speak(
            'Testing which voice gets used for this line of dialogue.',
            voiceKey: 'character-voice',
          ),
        );

        expect(
          observed.logsContain(
            'using this character\'s assigned voice "character-voice" '
            'instead of the global voice "global-voice"',
          ),
          isTrue,
          reason:
              'a character-specific voiceKey overriding the global one '
              'must be logged — silently doing the wrong thing here is '
              'invisible to the user',
        );
        expect(
          observed.logsContain('voice=character-voice'),
          isTrue,
          reason:
              'the resolved voice actually used downstream must be the '
              "character's voiceKey",
        );
        expect(observed.logsContain('voice=global-voice'), isFalse);
      },
    );
  });

  group(
    'speak() — sanitize pipeline (_sanitizeText, the future support seam)',
    () {
      test(
        'curly quotes, OOC, asterisks, markdown, custom-emoji and unicode '
        'emoji are all stripped from what actually gets logged/spoken',
        () async {
          final storage = _TtsProbeStorage(replaceCurlyQuotes: true);
          final tts = makeTts(storage);

          const input =
              '“a” (OOC: drop me) *gone* \u{1F600} '
              '[LinkWord](http://example.com) :wave: # HeadingWord _ul_ ~tl~';

          final observed = await _observe(tts, () => tts.speak(input));

          // Curly quotes -> straight quotes.
          expect(observed.logsContain('"a"'), isTrue);
          expect(observed.logsContain('“'), isFalse);
          expect(observed.logsContain('”'), isFalse);
          // OOC parenthetical fully removed, including its content.
          expect(observed.logsContain('OOC'), isFalse);
          expect(observed.logsContain('drop me'), isFalse);
          // Asterisks stripped but the enclosed word survives.
          expect(observed.logsContain('gone'), isTrue);
          expect(observed.logsContain('*'), isFalse);
          // Markdown links speak their label. This once pinned the opposite:
          // the code used `replaceAll(RegExp, r'$1')`, and Dart's
          // replaceAll(Pattern, String) has no $1 backreferences (only
          // replaceAllMapped does), so TTS literally said "dollar one" in
          // place of every link label. The net's authoring pass caught it;
          // the fix (replaceAllMapped) landed before this net did.
          expect(
            observed.logsContain(r'$1'),
            isFalse,
            reason:
                'a literal \$1 reaching the spoken text means the '
                'backreference-less replaceAll regressed',
          );
          expect(
            observed.logsContain('LinkWord'),
            isTrue,
            reason: 'the markdown link label must survive into speech',
          );
          expect(observed.logsContain('example.com'), isFalse);
          // Markdown heading marker stripped, text kept.
          expect(observed.logsContain('HeadingWord'), isTrue);
          expect(observed.logsContain('#'), isFalse);
          // Underscore/tilde emphasis markers stripped, text kept.
          expect(observed.logsContain('ul'), isTrue);
          expect(observed.logsContain('tl'), isTrue);
          expect(observed.logsContain('_ul_'), isFalse);
          expect(observed.logsContain('~tl~'), isFalse);
          // Custom ":emoji:" token and the real unicode emoji both removed.
          expect(observed.logsContain(':wave:'), isFalse);
          expect(observed.logsContain('\u{1F600}'), isFalse);
        },
      );

      test('ttsNarrateQuotedOnly with no quotes anywhere sanitizes to empty '
          'and speak() bails before ever generating', () async {
        final storage = _TtsProbeStorage(narrateQuotedOnly: true);
        final tts = makeTts(storage);

        final observed = await _observe(
          tts,
          () => tts.speak(
            'This whole line has no quotation marks in it whatsoever so it '
            'should vanish completely.',
          ),
        );

        expect(
          observed.sawGenerating,
          isFalse,
          reason:
              'narrateQuotedOnly with zero quoted spans must empty the '
              'sanitized text and hit the early "text empty after '
              'sanitization" return, never the busy-state / generation code',
        );
        expect(tts.isSpeaking, isFalse);
        expect(tts.isGenerating, isFalse);
      });

      test('a message that is ONLY a <think> block sanitizes to empty and is '
          'never spoken', () async {
        final storage = _TtsProbeStorage();
        final tts = makeTts(storage);

        final observed = await _observe(
          tts,
          () => tts.speak(
            '<think>Internal reasoning nobody should ever hear spoken '
            'aloud.</think>',
          ),
        );

        expect(
          observed.sawGenerating,
          isFalse,
          reason:
              'reasoning-tag debris must never reach generation — '
              'Kokoro would otherwise tokenize the stray tag text as prose',
        );
        expect(tts.isSpeaking, isFalse);
        expect(tts.isGenerating, isFalse);
      });
    },
  );

  group('speak() — engine routing + the busy-state machine', () {
    test('a non-kokoro, non-piper engine takes the cloud/sentence branch, '
        'not the unified Kokoro/Piper branch', () async {
      final storage = _TtsProbeStorage(engine: 'openai');
      final tts = makeTts(storage);

      final observed = await _observe(
        tts,
        () => tts.speak(
          'Multiple sentences should route through the cloud engine path. '
          'This is the second sentence for batching.',
        ),
      );

      expect(
        observed.logsContain(
          'Starting parallel generation of 2 sentences (concurrency=2)',
        ),
        isTrue,
        reason: 'ttsEngine=openai must take the cloud/sentence-batch branch',
      );
      expect(
        observed.logsContain('single full-text generation'),
        isFalse,
        reason: 'must NOT take the Kokoro/Piper unified branch',
      );
      expect(
        observed.sawGenerating,
        isTrue,
        reason:
            'the busy state must actually be entered before the '
            'engine call is attempted',
      );
      expect(observed.sawSpeaking, isTrue);
    });

    test('when generation produces no audio, the finally block resets '
        'every busy-state field', () async {
      final storage = _TtsProbeStorage(engine: 'openai');
      final tts = makeTts(storage);

      await tts.speak('A line that will fail to generate any audio at all.');

      expect(tts.isSpeaking, isFalse);
      expect(tts.isGenerating, isFalse);
      expect(tts.generationProgress, 0.0);
      expect(tts.currentMessageId, isNull);
      expect(
        tts.lastError,
        isNull,
        reason:
            'a plain generation failure (no audio, not an API error) '
            'must not set lastError — that field is for ElevenLabs-style '
            'user-facing failures specifically',
      );
    });
  });

  group('generateAudioFile() — headless, stateless', () {
    test('never touches isSpeaking/isGenerating and never fires '
        'notifyListeners', () async {
      final storage = _TtsProbeStorage(engine: 'openai');
      final tts = makeTts(storage);

      var notifyCount = 0;
      tts.addListener(() => notifyCount++);

      final result = await tts
          .generateAudioFile(
            'Simple narration line for the headless audio file path.',
          )
          .timeout(const Duration(seconds: 5));

      expect(
        result,
        isNull,
        reason:
            'with no API key configured, generation must fail closed '
            'and return null rather than throwing',
      );
      expect(
        notifyCount,
        0,
        reason:
            'generateAudioFile() is documented (split map Cluster F) '
            'as touching no state flags and no cache — it must never '
            'notify listeners at all',
      );
      expect(tts.isSpeaking, isFalse);
      expect(tts.isGenerating, isFalse);
    });
  });

  group('speakStreaming() — call-mode drain (the future streaming seam)', () {
    test('an all-failing engine drains the stream cleanly: no hang, no '
        'playback, full state reset', () async {
      final storage = _TtsProbeStorage(engine: 'openai');
      final tts = makeTts(storage);

      final observed = await _observe(
        tts,
        () => tts
            .speakStreaming(
              Stream.fromIterable([
                'The first spoken sentence arrives.',
                'The second spoken sentence follows soon after.',
              ]),
            )
            .timeout(const Duration(seconds: 10)),
      );

      expect(
        observed.sawGenerating,
        isTrue,
        reason:
            'speakStreaming sets the busy state before resolving the '
            'first sentence, per its own doc comment',
      );
      expect(
        tts.isSpeaking,
        isFalse,
        reason:
            'once the stream drains with nothing playable, the '
            'finally block must reset isSpeaking',
      );
      expect(tts.isGenerating, isFalse);
      expect(tts.currentMessageId, isNull);
    });
  });
}
