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

import 'dart:async';
import 'dart:io';

import 'package:front_porch_ai/services/kokoro_engine.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'tts_context.dart';
import 'tts_text.dart';

/// Headless generation behind [TtsService.generateAudioFile]: the web
/// server and the audiobook/narration services take the file, nothing plays.
class TtsHeadlessGenerator {
  TtsHeadlessGenerator(this._c);

  final TtsContext _c;

  /// Generate audio for the given text and return the WAV file without playing.
  /// Used by the web server to stream audio to the browser.
  Future<File?> generateAudioFile(String text, {String? voiceKey}) async {
    if (!_c.storage.ttsSettings.ttsEnabled) return null;

    var voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _c.storage.ttsSettings.ttsVoiceModel;
    if (voice.isEmpty) return null;

    // Defensive mismatch protection (same as in speak())
    if (_c.isPiperEngine && !await _c.voiceManager.isVoiceInstalled(voice)) {
      print(
        'TTS WARNING (generateAudioFile): Character voice "$voice" not found for Piper. Falling back.',
      );
      voice = _c.storage.ttsSettings.ttsVoiceModel;
      if (voice.isEmpty) return null;
    }

    final sanitized = _c.sanitize(text);
    if (sanitized.trim().isEmpty) return null;

    if (_c.isPiperEngine && !await _c.ensurePiperVoice(voice)) return null;

    try {
      if (_c.storage.ttsSettings.ttsEngine == 'kokoro') {
        final ready = await _c.activeEngine.ensureModelReady(
          onProgress: (_) {},
        );
        if (!ready) return null;

        if (_c.activeEngine is KokoroEngine) {
          unawaited((_c.activeEngine as KokoroEngine).ensureWorkersWarm());
        }
      }

      final sentences = splitTtsSentences(sanitized);
      final wavFiles = <File>[];

      if (_c.storage.ttsSettings.ttsEngine == 'elevenlabs') {
        // ElevenLabs: send full text as one request for natural intonation
        final engine = _c.activeEngine;
        final speed = _c.storage.ttsSettings.ttsSpeechRate;
        final wav = await engine.generateAudio(sanitized, voice, speed);
        if (wav != null) wavFiles.add(wav);
      } else if (_c.isPiperEngine) {
        final speed = _c.storage.ttsSettings.ttsSpeechRate;
        for (int i = 0; i < sentences.length; i++) {
          final wav = await _c.piperGenerateWav(voice, sentences[i], i, speed);
          if (wav == null) break;
          wavFiles.add(wav);
        }
      } else {
        final engine = _c.activeEngine;
        final speed = _c.storage.ttsSettings.ttsSpeechRate;
        final maxConcurrency = _c.storage.ttsSettings.ttsConcurrency;

        for (
          int batchStart = 0;
          batchStart < sentences.length;
          batchStart += maxConcurrency
        ) {
          final batchEnd = (batchStart + maxConcurrency).clamp(
            0,
            sentences.length,
          );
          final futures = <Future<File?>>[];
          for (int i = batchStart; i < batchEnd; i++) {
            futures.add(engine.generateAudio(sentences[i], voice, speed));
          }
          final results = await Future.wait(futures);
          bool failed = false;
          for (final result in results) {
            if (result == null) {
              failed = true;
              break;
            }
            wavFiles.add(result);
          }
          if (failed) break;
        }
      }

      if (wavFiles.isEmpty) return null;

      // A lone part IS the result — nothing to concatenate (and ElevenLabs
      // returns a single MP3, which must not be run through WAV stitching
      // anyway). Returning early is what keeps _cleanupFiles from deleting it:
      // concatenateWavFiles hands back wavFiles.first by identity for a
      // one-element list, so cleaning up here would delete the very file we
      // return. Same guard the buffered speak() path already carries.
      if (wavFiles.length == 1) return wavFiles.first;

      final combinedWav = await WavUtils.concatenateWavFiles(wavFiles);
      cleanupTtsFiles(wavFiles);
      return combinedWav;
    } catch (e) {
      print('TTS generateAudioFile error: $e');
      return null;
    }
  }
}
