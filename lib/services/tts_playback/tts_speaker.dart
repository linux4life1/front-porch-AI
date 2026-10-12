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

import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/services/kokoro_chunk.dart';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/kokoro_engine.dart';
import 'package:front_porch_ai/services/ordered_audio_collector.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'tts_context.dart';
import 'tts_text.dart';

/// Buffered "speak the whole message" pipeline behind [TtsService.speak].
class TtsSpeaker {
  TtsSpeaker(this._c);

  final TtsContext _c;

  OrderedAudioCollector? _audioCollector;

  /// Supersede ticket. A second Speak while the first is still generating
  /// must make the first one silent — but the shared `isSpeaking` flag
  /// cannot say that, because the newcomer sets it straight back to true,
  /// and the suspended first call then resumes, plays its own audio over
  /// the newcomer's and resets the newcomer's state on the way out.
  /// Ownership therefore needs a monotonic ticket.
  int _ticket = 0;

  /// Speak the given text using the active TTS engine.
  ///
  /// Generates audio for the entire message first (buffered), then plays
  /// it back seamlessly. Shows generation progress.
  Future<void> speak(String text, {String? voiceKey, String? messageId}) async {
    if (!_c.storage.ttsSettings.ttsEnabled) {
      print('TTS: disabled, skipping');
      return;
    }

    _c.state.lastError = null;
    await _c.stop();

    // Take this utterance's ticket (see [_ticket]). `mine()` is the
    // ownership test every step after an await must use instead of a bare
    // `isSpeaking`: false means either the user stopped playback or a
    // newer Speak took over, and in both cases this call must go quietly.
    final myTicket = _ticket + 1;
    _ticket = myTicket;
    bool stillMine() => _ticket == myTicket;
    bool mine() => _c.state.isSpeaking && stillMine();

    // Resolve voice. A character's own voice deliberately wins over the
    // global one — say so in the log, because "I changed the voice in
    // Settings and it kept talking in the old one" is otherwise invisible.
    var voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _c.storage.ttsSettings.ttsVoiceModel;
    if (voice.isEmpty) {
      // Reachable right after an engine switch (the old engine's voice id
      // cannot carry over, so it is cleared). Returning in silence made TTS
      // look broken; lastError is surfaced by chat_page.
      print('TTS: no voice configured');
      _c.state.lastError = 'Pick a voice in Settings → Text-to-Speech first.';
      _c.state.notify();
      return;
    }
    if (voiceKey != null &&
        voiceKey.isNotEmpty &&
        voiceKey != _c.storage.ttsSettings.ttsVoiceModel) {
      print(
        'TTS: using this character\'s assigned voice "$voiceKey" instead of '
        'the global voice "${_c.storage.ttsSettings.ttsVoiceModel}".',
      );
    }

    // Defensive check: if the resolved voice key is clearly incompatible
    // with the current engine (e.g. Kokoro voice assigned to a character while
    // Piper is selected), fall back to the global voice for this engine.
    if (_c.isPiperEngine && !await _c.voiceManager.isVoiceInstalled(voice)) {
      print(
        'TTS WARNING: Character voice "$voice" not found for Piper engine. '
        'Falling back to global Piper voice. (This usually means a character '
        'was assigned a Kokoro voice while Piper was selected.)',
      );
      voice = _c.storage.ttsSettings.ttsVoiceModel;
      if (voice.isEmpty) return;
    }

    final sanitized = _c.sanitize(text);
    if (sanitized.trim().isEmpty) {
      print('TTS: text empty after sanitization');
      return;
    }

    final speed = _c.storage.ttsSettings.ttsSpeechRate;

    // Check cache — replay instantly if same message & same content
    final textHash = sanitized.hashCode;
    final cached = _c.cache.hit(
      messageId: messageId,
      textHash: textHash,
      voice: voice,
      engine: _c.storage.ttsSettings.ttsEngine,
      speed: speed,
    );
    if (cached != null) {
      print('TTS: cache hit for message $messageId');
      _c.state.isSpeaking = true;
      _c.state.isGenerating = false;
      _c.state.currentMessageId = messageId;
      _c.state.notify();
      try {
        await _c.player.play(cached);
      } catch (e) {
        print('TTS cache playback error: $e');
      } finally {
        if (stillMine()) {
          _c.state.isSpeaking = false;
          _c.state.currentMessageId = null;
          _c.state.notify();
        }
      }
      return;
    }

    // Different message — clear old cache
    if (messageId != _c.cache.messageId) {
      _c.cache.clear();
    }

    print(
      'TTS: engine=${_c.storage.ttsSettings.ttsEngine}, voice=$voice, text="${sanitized.substring(0, sanitized.length.clamp(0, 60))}..."',
    );
    _c.state.isSpeaking = true;
    _c.state.isGenerating = true;
    _c.state.generationProgress = 0.0;
    _c.state.currentMessageId = messageId;
    _c.state.notify();

    try {
      // For Kokoro, ensure model is downloaded
      if (_c.storage.ttsSettings.ttsEngine == 'kokoro') {
        final ready = await _c.activeEngine.ensureModelReady(
          onProgress: (p) {
            _c.state.modelDownloadProgress = p;
            _c.state.isDownloadingModel = p < 1.0;
            _c.state.notify();
          },
        );
        _c.state.isDownloadingModel = false;
        if (!ready || !mine()) {
          print('TTS: Kokoro model not ready');
          return;
        }

        // Pre-start the worker pool so first audio doesn't have cold-start delay
        if (_c.activeEngine is KokoroEngine) {
          unawaited((_c.activeEngine as KokoroEngine).ensureWorkersWarm());
        }
      }

      final bool isKokoro = _c.storage.ttsSettings.ttsEngine == 'kokoro';
      final bool isPiper = _c.isPiperEngine;

      // Unified modern path for Kokoro (persistent) and Piper (one-shot).
      // Both now benefit from proper sanitization, smart chunking for long text,
      // real progress reporting, and correct ordering/collation.
      // Piper remains strictly one-shot under the hood (as the binary is designed).
      if (isKokoro || isPiper) {
        final engineName = isPiper ? 'Piper' : 'Kokoro';
        final modeLabel = _c.storage.ttsSettings.ttsNarrateQuotedOnly
            ? 'Only Quotes'
            : _c.storage.ttsSettings.ttsIgnoreAsterisks
            ? 'Ignore Asterisks'
            : 'Verbatim';
        debugPrint(
          '[TtsService] $engineName single full-text generation ($modeLabel mode)',
        );

        _c.state.generationProgress = 0.01;
        _c.state.isGenerating = true;
        _c.state.notify();

        List<File> generatedWavs = [];

        if (isPiper) {
          // Piper: per-chunk one-shot on the in-process sherpa engine
          // (sidecar retirement phase 4b — the legacy binary is gone).
          if (!await _c.ensurePiperVoice(voice)) {
            _c.state.isGenerating = false;
            _c.state.notify();
            return;
          }

          final bool readEverythingMode =
              !_c.storage.ttsSettings.ttsIgnoreAsterisks &&
              !_c.storage.ttsSettings.ttsNarrateQuotedOnly;

          final List<KokoroChunk> chunks;
          if (readEverythingMode) {
            chunks = KokoroChunker.splitFixedCharacterCount(
              text: sanitized,
              voice: voice,
              speed: speed,
              lang: 'en-us',
              modelPath: '',
              voicesPath: '',
              chunkSize: KokoroChunker.verbatimChunkSize,
            );
          } else {
            chunks = KokoroChunker.split(
              text: sanitized,
              voice: voice,
              speed: speed,
              lang: 'en-us',
              modelPath: '',
              voicesPath: '',
              maxChars: 450,
            );
          }

          final total = chunks.length;
          for (int i = 0; i < total; i++) {
            if (!mine()) break;

            final wav = await _c.piperGenerateWav(
              voice,
              chunks[i].text,
              i,
              speed,
            );
            if (wav != null) {
              generatedWavs.add(wav);
            }

            _c.state.generationProgress = (i + 1) / total;
            _c.state.notify();
          }
        } else {
          // Kokoro: uses the persistent worker pool + internal chunking + collation
          final wav = await _c.activeEngine.generateAudio(
            sanitized,
            voice,
            speed,
            onProgress: (progress) {
              _c.state.generationProgress = progress;
              _c.state.notify();
            },
          );

          if (wav != null) {
            generatedWavs = [wav];
          }
        }

        // Superseded (or stopped) while generating: leave every shared field
        // to whoever owns it now, and don't leave the temp audio behind.
        if (!mine()) {
          cleanupTtsFiles(generatedWavs);
          return;
        }

        _c.state.isGenerating = false;
        _c.state.notify();

        if (generatedWavs.isNotEmpty) {
          File? finalAudio;

          if (generatedWavs.length == 1) {
            finalAudio = generatedWavs.first;
          } else {
            finalAudio = await WavUtils.concatenateWavFiles(generatedWavs);
            cleanupTtsFiles(generatedWavs);
          }

          if (finalAudio != null) {
            // Concatenation is awaited — re-check ownership before touching
            // the shared cache or starting a second player.
            if (!mine()) {
              cleanupTtsFiles([finalAudio]);
              return;
            }
            _c.cache.store(
              finalAudio,
              messageId: messageId,
              textHash: sanitized.hashCode,
              voice: voice,
              engine: _c.storage.ttsSettings.ttsEngine,
              speed: speed,
            );

            await _c.player.play(finalAudio);
          }
        } else {
          _c.state.generationProgress = 0.0;
          _c.state.notify();
        }

        return; // finally block will reset speaking state
      }

      final sentences = splitTtsSentences(sanitized);
      final wavFiles = <File?>[]; // Filled via OrderedAudioCollector for Kokoro

      // Phase 1: Generate audio
      // ElevenLabs is fast enough to process full text in one request —
      // skip sentence splitting for better intonation and fewer API calls.
      // (Kokoro and Piper returned above; only the cloud engines get here.)
      if (_c.storage.ttsSettings.ttsEngine == 'elevenlabs') {
        final engine = _c.activeEngine;
        final speed = _c.storage.ttsSettings.ttsSpeechRate;
        _c.state.generationProgress = 0.5;
        _c.state.notify();
        final wav = await engine.generateAudio(sanitized, voice, speed);
        if (!mine()) {
          // Superseded (or stopped) while the request was out — the progress
          // bar and every other shared field belong to someone else now.
          if (wav != null) cleanupTtsFiles([wav]);
          return;
        }
        if (wav != null) {
          wavFiles.add(wav);
        }
        _c.state.generationProgress = 1.0;
        _c.state.notify();
      } else {
        // Parallel for Kokoro / OpenAI — all results go through the OrderedAudioCollector
        final engine = _c.activeEngine;
        final speed = _c.storage.ttsSettings.ttsSpeechRate;
        final maxConcurrency = _c.storage.ttsSettings.ttsConcurrency;

        _audioCollector = OrderedAudioCollector(
          maxLookahead: _c.storage.ttsSettings.ttsAudioLookahead,
        );
        _audioCollector!.reset(); // Ensure clean state for new utterance

        debugPrint(
          '[TtsService] Starting parallel generation of ${sentences.length} sentences (concurrency=$maxConcurrency)',
        );

        for (
          int batchStart = 0;
          batchStart < sentences.length;
          batchStart += maxConcurrency
        ) {
          if (!mine()) break;

          final batchEnd = (batchStart + maxConcurrency).clamp(
            0,
            sentences.length,
          );
          final futures = <Future<File?>>[];

          for (int i = batchStart; i < batchEnd; i++) {
            futures.add(engine.generateAudio(sentences[i], voice, speed));
          }

          final results = await Future.wait(futures);

          // Superseded (or stopped) while this batch was generating: these
          // files belong to nobody now, and the collector below is already
          // the NEW utterance's — submitting into it would corrupt its order.
          if (!mine()) {
            cleanupTtsFiles(results.whereType<File>().toList());
            break;
          }

          bool failed = false;
          for (int j = 0; j < results.length; j++) {
            final sentenceIndex = batchStart + j;
            final file = results[j];

            if (file == null) {
              failed = true;
              break;
            }

            // Submit to collector — it will only release files in the correct global order
            final readyFiles = _audioCollector!.submit(sentenceIndex, file);
            for (final readyFile in readyFiles) {
              wavFiles.add(readyFile); // We collect in correct order
            }
          }
          if (failed) break;

          _c.state.generationProgress = batchEnd / sentences.length;
          _c.state.notify();
        }
      }

      // wavFiles should be in correct order thanks to OrderedAudioCollector
      final validWavFiles = wavFiles.whereType<File>().toList();

      if (!mine() || validWavFiles.isEmpty) {
        cleanupTtsFiles(validWavFiles);
        return;
      }

      // Phase 2: Concatenate and play
      _c.state.isGenerating = false;
      _c.state.notify();

      File? audioFile;
      if (validWavFiles.length == 1) {
        // One file is all there is to play: concatenateWavFiles hands back
        // that very File for a single-element list, so the cleanup in the
        // other branch would delete the audio we are about to play (and the
        // one we are about to cache). ElevenLabs also lands here — its single
        // response is an MP3 that must never go through WAV concatenation.
        audioFile = validWavFiles.first;
      } else {
        audioFile = await WavUtils.concatenateWavFiles(validWavFiles);
        cleanupTtsFiles(validWavFiles);
      }

      if (audioFile != null && mine()) {
        // Cache the audio for instant replay
        _c.cache.store(
          audioFile,
          messageId: messageId,
          textHash: sanitized.hashCode,
          voice: voice,
          engine: _c.storage.ttsSettings.ttsEngine,
          speed: speed,
        );
        await _c.player.play(audioFile);
        // Don't delete — it's cached now
      }
    } on ElevenLabsApiException catch (e) {
      print('TTS ElevenLabs error: $e');
      // The state reset + notify live in the `finally` below, which runs on
      // this return too — a second copy here only risked the two drifting.
      _c.state.lastError = e.message;
      return;
    } catch (e) {
      print('TTS error: $e');
    } finally {
      // Only the owner may clear the shared state: a superseded call reaching
      // here must not switch off the Speak that replaced it.
      if (stillMine()) {
        _c.state.isSpeaking = false;
        _c.state.isGenerating = false;
        _c.state.generationProgress = 0.0;
        _c.state.currentMessageId = null;
        _c.state.notify();
      }
    }
  }
}
