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

part of 'tts_service.dart';

/// The two non-buffered generation entry points: call-mode streaming
/// playback and headless (web/audiobook) generation. Extracted verbatim
/// from tts_service.dart, zero behaviour change.
extension TtsServiceStreamingAndHeadless on TtsService {
  /// Speak sentences as they arrive from a stream (for call mode).
  ///
  /// Uses a producer-consumer pattern: a producer generates audio files
  /// concurrently as sentences arrive, while a consumer plays them in order.
  /// An initial buffer of 3 sentences gives a head start so playback is smooth.
  Future<void> speakStreaming(
    Stream<String> sentenceStream, {
    String? voiceKey,
  }) async {
    if (!_storageService.ttsSettings.ttsEnabled) return;

    await stop();

    // Busy from the first moment: the call session's mic gating reads
    // isSpeaking/isGenerating, so they must be true through the whole
    // setup (voice checks, model readiness), not just once audio starts.
    _isSpeaking = true;
    _isGenerating = true;
    _notify();
    void bail() {
      _isSpeaking = false;
      _isGenerating = false;
      _notify();
    }

    // Resolve voice
    var voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _storageService.ttsSettings.ttsVoiceModel;
    if (voice.isEmpty) {
      print('TTS streaming: no voice configured');
      _lastError = 'Pick a voice in Settings → Text-to-Speech first.';
      _notify();
      bail();
      return;
    }

    // Defensive mismatch protection (same as in speak())
    if (_isPiperEngine && !await _voiceManager.isVoiceInstalled(voice)) {
      print(
        'TTS WARNING (streaming): Character voice "$voice" not found for Piper. Falling back.',
      );
      voice = _storageService.ttsSettings.ttsVoiceModel;
      if (voice.isEmpty) {
        bail();
        return;
      }
    }

    // For Piper, make sure the sherpa voice bundle is on disk
    if (_isPiperEngine && !await _ensurePiperVoice(voice)) {
      bail();
      return;
    }

    // Ensure Kokoro model is ready
    if (_storageService.ttsSettings.ttsEngine == 'kokoro') {
      final ready = await activeEngine.ensureModelReady(
        onProgress: (p) {
          _modelDownloadProgress = p;
          _isDownloadingModel = p < 1.0;
          _notify();
        },
      );
      _isDownloadingModel = false;
      if (!ready) {
        bail();
        return;
      }

      if (activeEngine is KokoroEngine) {
        unawaited((activeEngine as KokoroEngine).ensureWorkersWarm());
      }
    }

    _clearCache(); // no caching for streaming

    final engine = activeEngine;
    final speed = _storageService.ttsSettings.ttsSpeechRate;
    final tempFiles = <File>[];

    // Shared queue between producer and consumer. Each entry carries the
    // sentence text alongside its audio so the consumer can publish
    // [nowSpeaking] in sync with what is actually coming out of the speaker
    // (the call overlay's live caption).
    final audioQueue = <(File, String)>[];
    bool producerDone = false;
    int bufferTarget = _storageService.sttSettings.callBufferSentences.clamp(
      1,
      10,
    );

    try {
      var maxConcurrency = _isPiperEngine
          ? 1
          : _storageService.ttsSettings.ttsConcurrency.clamp(1, 8);
      // ElevenLabs: one at a time from the stream (already fast enough)
      if (_storageService.ttsSettings.ttsEngine == 'elevenlabs') {
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
          if (!_isSpeaking) break;
          if (sentence == '__DONE__') break;

          final sanitized = _sanitizeText(sentence);
          if (sanitized.trim().isEmpty) continue;

          final idx = orderedFutures.length;
          sentenceTexts.add(sanitized);
          debugPrint('TTS streaming[$idx]: launching "$sanitized"');

          // Fire off generation without awaiting — runs concurrently
          final future = () async {
            File? wavFile;
            try {
              if (_isPiperEngine) {
                wavFile = await _piperGenerateWav(voice, sanitized, idx, speed);
              } else {
                kDebugPrint(
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
              _lastError = e.message;
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
      while (!producerDone && audioQueue.length < bufferTarget && _isSpeaking) {
        futureReady = Completer<void>();
        await futureReady.future;
        collectReady();
      }

      // ── Consumer: play audio in order ──
      _isGenerating = false;
      _notify();

      while (_isSpeaking) {
        collectReady(); // gather any newly completed results
        if (audioQueue.isNotEmpty) {
          final (toPlay, line) = audioQueue.removeAt(0);
          _nowSpeaking = line;
          _notify();
          await _playWavFile(toPlay);
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
      _lastError = e.message;
    } catch (e) {
      print('TTS streaming error: $e');
    } finally {
      _isSpeaking = false;
      _isGenerating = false;
      _generationProgress = 0.0;
      _currentMessageId = null;
      _nowSpeaking = null;
      _notify();

      // Clean up temp files
      _cleanupFiles(tempFiles);
    }
  }

  /// Generate audio for the given text and return the WAV file without playing.
  /// Used by the web server to stream audio to the browser.
  Future<File?> generateAudioFile(String text, {String? voiceKey}) async {
    if (!_storageService.ttsSettings.ttsEnabled) return null;

    var voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _storageService.ttsSettings.ttsVoiceModel;
    if (voice.isEmpty) return null;

    // Defensive mismatch protection (same as in speak())
    if (_isPiperEngine && !await _voiceManager.isVoiceInstalled(voice)) {
      print(
        'TTS WARNING (generateAudioFile): Character voice "$voice" not found for Piper. Falling back.',
      );
      voice = _storageService.ttsSettings.ttsVoiceModel;
      if (voice.isEmpty) return null;
    }

    final sanitized = _sanitizeText(text);
    if (sanitized.trim().isEmpty) return null;

    if (_isPiperEngine && !await _ensurePiperVoice(voice)) return null;

    try {
      if (_storageService.ttsSettings.ttsEngine == 'kokoro') {
        final ready = await activeEngine.ensureModelReady(onProgress: (_) {});
        if (!ready) return null;

        if (activeEngine is KokoroEngine) {
          unawaited((activeEngine as KokoroEngine).ensureWorkersWarm());
        }
      }

      final sentences = _splitSentences(sanitized);
      final wavFiles = <File>[];

      if (_storageService.ttsSettings.ttsEngine == 'elevenlabs') {
        // ElevenLabs: send full text as one request for natural intonation
        final engine = activeEngine;
        final speed = _storageService.ttsSettings.ttsSpeechRate;
        final wav = await engine.generateAudio(sanitized, voice, speed);
        if (wav != null) wavFiles.add(wav);
      } else if (_isPiperEngine) {
        final speed = _storageService.ttsSettings.ttsSpeechRate;
        for (int i = 0; i < sentences.length; i++) {
          final wav = await _piperGenerateWav(voice, sentences[i], i, speed);
          if (wav == null) break;
          wavFiles.add(wav);
        }
      } else {
        final engine = activeEngine;
        final speed = _storageService.ttsSettings.ttsSpeechRate;
        final maxConcurrency = _storageService.ttsSettings.ttsConcurrency;

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
      _cleanupFiles(wavFiles);
      return combinedWav;
    } catch (e) {
      print('TTS generateAudioFile error: $e');
      return null;
    }
  }
}
