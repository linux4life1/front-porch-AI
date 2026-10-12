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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/services/kokoro_engine.dart';

import 'tts_context.dart';
import 'tts_text.dart';

/// Call-mode playback behind [TtsService.speakStreaming]: sentences are
/// voiced as they arrive from a stream.
class TtsStreamer {
  TtsStreamer(this._c);

  final TtsContext _c;

  /// Speak sentences as they arrive from a stream (for call mode).
  ///
  /// Uses a producer-consumer pattern: a producer generates audio files
  /// concurrently as sentences arrive, while a consumer plays them in order.
  /// An initial buffer of 3 sentences gives a head start so playback is smooth.
  Future<void> speakStreaming(
    Stream<String> sentenceStream, {
    String? voiceKey,
  }) async {
    if (!_c.storage.ttsSettings.ttsEnabled) return;

    await _c.stop();

    // Busy from the first moment: the call session's mic gating reads
    // isSpeaking/isGenerating, so they must be true through the whole
    // setup (voice checks, model readiness), not just once audio starts.
    _c.state.isSpeaking = true;
    _c.state.isGenerating = true;
    _c.state.notify();
    void bail() {
      _c.state.isSpeaking = false;
      _c.state.isGenerating = false;
      _c.state.notify();
    }

    // Resolve voice
    var voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _c.storage.ttsSettings.ttsVoiceModel;
    if (voice.isEmpty) {
      print('TTS streaming: no voice configured');
      _c.state.lastError = 'Pick a voice in Settings → Text-to-Speech first.';
      _c.state.notify();
      bail();
      return;
    }

    // Defensive mismatch protection (same as in speak())
    if (_c.isPiperEngine && !await _c.voiceManager.isVoiceInstalled(voice)) {
      print(
        'TTS WARNING (streaming): Character voice "$voice" not found for Piper. Falling back.',
      );
      voice = _c.storage.ttsSettings.ttsVoiceModel;
      if (voice.isEmpty) {
        bail();
        return;
      }
    }

    // For Piper, make sure the sherpa voice bundle is on disk
    if (_c.isPiperEngine && !await _c.ensurePiperVoice(voice)) {
      bail();
      return;
    }

    // Ensure Kokoro model is ready
    if (_c.storage.ttsSettings.ttsEngine == 'kokoro') {
      final ready = await _c.activeEngine.ensureModelReady(
        onProgress: (p) {
          _c.state.modelDownloadProgress = p;
          _c.state.isDownloadingModel = p < 1.0;
          _c.state.notify();
        },
      );
      _c.state.isDownloadingModel = false;
      if (!ready) {
        bail();
        return;
      }

      if (_c.activeEngine is KokoroEngine) {
        unawaited((_c.activeEngine as KokoroEngine).ensureWorkersWarm());
      }
    }

    _c.cache.clear(); // no caching for streaming

    final engine = _c.activeEngine;
    final speed = _c.storage.ttsSettings.ttsSpeechRate;
    final tempFiles = <File>[];

    // Shared queue between producer and consumer. Each entry carries the
    // sentence text alongside its audio so the consumer can publish
    // [nowSpeaking] in sync with what is actually coming out of the speaker
    // (the call overlay's live caption).
    final audioQueue = <(File, String)>[];
    bool producerDone = false;
    int bufferTarget = _c.storage.sttSettings.callBufferSentences.clamp(1, 10);

    try {
      var maxConcurrency = _c.isPiperEngine
          ? 1
          : _c.storage.ttsSettings.ttsConcurrency.clamp(1, 8);
      // ElevenLabs: one at a time from the stream (already fast enough)
      if (_c.storage.ttsSettings.ttsEngine == 'elevenlabs') {
        maxConcurrency = 1;
      }

      // ── Producer: fire off concurrent generation futures ──
      final orderedFutures = <Future<File?>>[];
      final sentenceTexts = <String>[]; // index-aligned with orderedFutures
      final completedFiles = <int, File?>{};
      int nextToQueue = 0;
      Completer<void>? futureReady; // signals when a new future completes

      final producerFuture = () async {
        await for (final sentence in sentenceStream) {
          if (!_c.state.isSpeaking) break;
          if (sentence == '__DONE__') break;

          final sanitized = _c.sanitize(sentence);
          if (sanitized.trim().isEmpty) continue;

          final idx = orderedFutures.length;
          sentenceTexts.add(sanitized);
          debugPrint('TTS streaming[$idx]: launching "$sanitized"');

          // Fire off generation without awaiting — runs concurrently
          final future = () async {
            File? wavFile;
            try {
              if (_c.isPiperEngine) {
                wavFile = await _c.piperGenerateWav(
                  voice,
                  sanitized,
                  idx,
                  speed,
                );
              } else {
                debugPrint(
                  '[TtsService] Streaming: generating audio for chunk (len=${sanitized.length})',
                );
                wavFile = await engine.generateAudio(sanitized, voice, speed);
              }
            } on ElevenLabsApiException catch (e) {
              // ElevenLabs THROWS where every other engine returns null. An
              // escaping throw left completedFiles[idx] unwritten, so the
              // in-order collector wedged at that index forever (the rest of
              // the reply never played, speakStreaming never returned, and the
              // orphaned .then below raised an unhandled async error). Convert
              // to the null the collector is written for, and surface the
              // message so the user sees the quota/key problem.
              print('TTS ElevenLabs streaming error: $e');
              _c.state.lastError = e.message;
              wavFile = null;
            } catch (e) {
              print('TTS streaming generation error: $e');
              wavFile = null;
            }
            return wavFile;
          }();

          orderedFutures.add(future);

          // When this future completes, store result and signal collector
          future.then((file) {
            completedFiles[idx] = file;
            if (file != null) tempFiles.add(file);
            if (futureReady != null && !futureReady.isCompleted) {
              futureReady.complete();
            }
          });

          // Throttle: if we have too many in-flight, wait for some to complete
          final inFlight = orderedFutures.length - nextToQueue;
          if (inFlight >= maxConcurrency) {
            await orderedFutures[nextToQueue]; // wait for oldest to finish
          }
        }
        producerDone = true;
        if (futureReady != null && !futureReady.isCompleted) {
          futureReady.complete();
        }
      }();

      // ── Collector: gather completed results in order into audioQueue ──
      void collectReady() {
        while (completedFiles.containsKey(nextToQueue)) {
          final file = completedFiles[nextToQueue];
          // A failed generation stores null — skip that sentence instead
          // of aborting the whole streaming session.
          if (file != null) {
            audioQueue.add((file, sentenceTexts[nextToQueue]));
          }
          nextToQueue++;
        }
      }

      // Wait for initial buffer to fill
      while (!producerDone &&
          audioQueue.length < bufferTarget &&
          _c.state.isSpeaking) {
        futureReady = Completer<void>();
        await futureReady.future;
        collectReady();
      }

      // ── Consumer: play audio in order ──
      _c.state.isGenerating = false;
      _c.state.notify();

      while (_c.state.isSpeaking) {
        collectReady(); // gather any newly completed results
        if (audioQueue.isNotEmpty) {
          final (toPlay, line) = audioQueue.removeAt(0);
          _c.state.nowSpeaking = line;
          _c.state.notify();
          await _c.player.play(toPlay);
        } else if (producerDone && !completedFiles.containsKey(nextToQueue)) {
          break; // nothing left to play or generate
        } else {
          // Wait for more audio from producer
          futureReady = Completer<void>();
          await futureReady.future;
          collectReady();
        }
      }

      await producerFuture; // ensure producer finishes cleanly
    } on ElevenLabsApiException catch (e) {
      print('TTS ElevenLabs streaming error: $e');
      _c.state.lastError = e.message;
    } catch (e) {
      print('TTS streaming error: $e');
    } finally {
      _c.state.isSpeaking = false;
      _c.state.isGenerating = false;
      _c.state.generationProgress = 0.0;
      _c.state.currentMessageId = null;
      _c.state.nowSpeaking = null;
      _c.state.notify();

      // Clean up temp files
      cleanupTtsFiles(tempFiles);
    }
  }
}
