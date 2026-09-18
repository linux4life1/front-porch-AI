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

/// Per-instance supersede tickets for [TtsServiceSpeak.speak].
///
/// A second Speak while the first is still generating must make the first one
/// silent — but the shared `_isSpeaking` flag cannot say that, because the
/// newcomer sets it straight back to true, and the suspended first call then
/// resumes, plays its own audio over the newcomer's and resets the newcomer's
/// state on the way out. Ownership therefore needs a monotonic ticket.
/// Extensions cannot add instance fields, so it lives here, keyed on the
/// service instance (an [Expando] keeps it per-instance and GC-safe).
final Expando<int> _speakTickets = Expando<int>('ttsSpeakTicket');

/// Buffered "speak the whole message" pipeline (extracted verbatim from
/// tts_service.dart, zero behaviour change).
extension TtsServiceSpeak on TtsService {
  /// Speak the given text using the active TTS engine.
  ///
  /// Generates audio for the entire message first (buffered), then plays
  /// it back seamlessly. Shows generation progress.
  Future<void> speak(String text, {String? voiceKey, String? messageId}) async {
    if (!_storageService.ttsSettings.ttsEnabled) {
      print('TTS: disabled, skipping');
      return;
    }

    _lastError = null;
    await stop();

    // Take this utterance's ticket (see [_speakTickets]). `mine()` is the
    // ownership test every step after an await must use instead of a bare
    // `_isSpeaking`: false means either the user stopped playback or a newer
    // Speak took over, and in both cases this call must go quietly.
    final myTicket = (_speakTickets[this] ?? 0) + 1;
    _speakTickets[this] = myTicket;
    bool stillMine() => _speakTickets[this] == myTicket;
    bool mine() => _isSpeaking && stillMine();

    // Resolve voice. A character's own voice deliberately wins over the
    // global one — say so in the log, because "I changed the voice in
    // Settings and it kept talking in the old one" is otherwise invisible.
    var voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _storageService.ttsSettings.ttsVoiceModel;
    if (voice.isEmpty) {
      // Reachable right after an engine switch (the old engine's voice id
      // cannot carry over, so it is cleared). Returning in silence made TTS
      // look broken; lastError is surfaced by chat_page.
      print('TTS: no voice configured');
      _lastError = 'Pick a voice in Settings → Text-to-Speech first.';
      _notify();
      return;
    }
    if (voiceKey != null &&
        voiceKey.isNotEmpty &&
        voiceKey != _storageService.ttsSettings.ttsVoiceModel) {
      print(
        'TTS: using this character\'s assigned voice "$voiceKey" instead of '
        'the global voice "${_storageService.ttsSettings.ttsVoiceModel}".',
      );
    }

    // Defensive check: if the resolved voice key is clearly incompatible
    // with the current engine (e.g. Kokoro voice assigned to a character while
    // Piper is selected), fall back to the global voice for this engine.
    if (_isPiperEngine && !await _voiceManager.isVoiceInstalled(voice)) {
      print(
        'TTS WARNING: Character voice "$voice" not found for Piper engine. '
        'Falling back to global Piper voice. (This usually means a character '
        'was assigned a Kokoro voice while Piper was selected.)',
      );
      voice = _storageService.ttsSettings.ttsVoiceModel;
      if (voice.isEmpty) return;
    }

    final sanitized = _sanitizeText(text);
    if (sanitized.trim().isEmpty) {
      print('TTS: text empty after sanitization');
      return;
    }

    final speed = _storageService.ttsSettings.ttsSpeechRate;

    // Check cache — replay instantly if same message & same content
    final textHash = sanitized.hashCode;
    if (messageId != null &&
        messageId == _cachedMessageId &&
        textHash == _cachedTextHash &&
        voice == _cachedVoice &&
        _storageService.ttsSettings.ttsEngine == _cachedEngine &&
        speed == _cachedSpeed &&
        _cachedWav != null &&
        _cachedWav!.existsSync()) {
      print('TTS: cache hit for message $messageId');
      _isSpeaking = true;
      _isGenerating = false;
      _currentMessageId = messageId;
      _notify();
      try {
        await _playWavFile(_cachedWav!);
      } catch (e) {
        print('TTS cache playback error: $e');
      } finally {
        if (stillMine()) {
          _isSpeaking = false;
          _currentMessageId = null;
          _notify();
        }
      }
      return;
    }

    // Different message — clear old cache
    if (messageId != _cachedMessageId) {
      _clearCache();
    }

    print(
      'TTS: engine=${_storageService.ttsSettings.ttsEngine}, voice=$voice, text="${sanitized.substring(0, sanitized.length.clamp(0, 60))}..."',
    );
    _isSpeaking = true;
    _isGenerating = true;
    _generationProgress = 0.0;
    _currentMessageId = messageId;
    _notify();

    try {
      // For Kokoro, ensure model is downloaded
      if (_storageService.ttsSettings.ttsEngine == 'kokoro') {
        final ready = await activeEngine.ensureModelReady(
          onProgress: (p) {
            _modelDownloadProgress = p;
            _isDownloadingModel = p < 1.0;
            _notify();
          },
        );
        _isDownloadingModel = false;
        if (!ready || !mine()) {
          print('TTS: Kokoro model not ready');
          return;
        }

        // Pre-start the worker pool so first audio doesn't have cold-start delay
        if (activeEngine is KokoroEngine) {
          unawaited((activeEngine as KokoroEngine).ensureWorkersWarm());
        }
      }

      final bool isKokoro = _storageService.ttsSettings.ttsEngine == 'kokoro';
      final bool isPiper = _isPiperEngine;

      // Unified modern path for Kokoro (persistent) and Piper (one-shot).
      // Both now benefit from proper sanitization, smart chunking for long text,
      // real progress reporting, and correct ordering/collation.
      // Piper remains strictly one-shot under the hood (as the binary is designed).
      if (isKokoro || isPiper) {
        final engineName = isPiper ? 'Piper' : 'Kokoro';
        final modeLabel = _storageService.ttsSettings.ttsNarrateQuotedOnly
            ? 'Only Quotes'
            : _storageService.ttsSettings.ttsIgnoreAsterisks
            ? 'Ignore Asterisks'
            : 'Verbatim';
        kDebugPrint(
          '[TtsService] $engineName single full-text generation ($modeLabel mode)',
        );

        _generationProgress = 0.01;
        _isGenerating = true;
        _notify();

        List<File> generatedWavs = [];

        if (isPiper) {
          // Piper: per-chunk one-shot on the in-process sherpa engine
          // (sidecar retirement phase 4b — the legacy binary is gone).
          if (!await _ensurePiperVoice(voice)) {
            _isGenerating = false;
            _notify();
            return;
          }

          final bool readEverythingMode =
              !_storageService.ttsSettings.ttsIgnoreAsterisks &&
              !_storageService.ttsSettings.ttsNarrateQuotedOnly;

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

            final wav = await _piperGenerateWav(
              voice,
              chunks[i].text,
              i,
              speed,
            );
            if (wav != null) {
              generatedWavs.add(wav);
            }

            _generationProgress = (i + 1) / total;
            _notify();
          }
        } else {
          // Kokoro: uses the persistent worker pool + internal chunking + collation
          final wav = await activeEngine.generateAudio(
            sanitized,
            voice,
            speed,
            onProgress: (progress) {
              _generationProgress = progress;
              _notify();
            },
          );

          if (wav != null) {
            generatedWavs = [wav];
          }
        }

        // Superseded (or stopped) while generating: leave every shared field
        // to whoever owns it now, and don't leave the temp audio behind.
        if (!mine()) {
          _cleanupFiles(generatedWavs);
          return;
        }

        _isGenerating = false;
        _notify();

        if (generatedWavs.isNotEmpty) {
          File? finalAudio;

          if (generatedWavs.length == 1) {
            finalAudio = generatedWavs.first;
          } else {
            finalAudio = await WavUtils.concatenateWavFiles(generatedWavs);
            _cleanupFiles(generatedWavs);
          }

          if (finalAudio != null) {
            // Concatenation is awaited — re-check ownership before touching
            // the shared cache or starting a second player.
            if (!mine()) {
              _cleanupFiles([finalAudio]);
              return;
            }
            _cachedWav = finalAudio;
            _cachedMessageId = messageId;
            _cachedTextHash = sanitized.hashCode;
            _cachedVoice = voice;
            _cachedEngine = _storageService.ttsSettings.ttsEngine;
            _cachedSpeed = speed;

            await _playWavFile(finalAudio);
          }
        } else {
          _generationProgress = 0.0;
          _notify();
        }

        return; // finally block will reset speaking state
      }

      final sentences = _splitSentences(sanitized);
      final wavFiles = <File?>[]; // Filled via OrderedAudioCollector for Kokoro

      // Phase 1: Generate audio
      // ElevenLabs is fast enough to process full text in one request —
      // skip sentence splitting for better intonation and fewer API calls.
      // (Kokoro and Piper returned above; only the cloud engines get here.)
      if (_storageService.ttsSettings.ttsEngine == 'elevenlabs') {
        final engine = activeEngine;
        final speed = _storageService.ttsSettings.ttsSpeechRate;
        _generationProgress = 0.5;
        _notify();
        final wav = await engine.generateAudio(sanitized, voice, speed);
        if (!mine()) {
          // Superseded (or stopped) while the request was out — the progress
          // bar and every other shared field belong to someone else now.
          if (wav != null) _cleanupFiles([wav]);
          return;
        }
        if (wav != null) {
          wavFiles.add(wav);
        }
        _generationProgress = 1.0;
        _notify();
      } else {
        // Parallel for Kokoro / OpenAI — all results go through the OrderedAudioCollector
        final engine = activeEngine;
        final speed = _storageService.ttsSettings.ttsSpeechRate;
        final maxConcurrency = _storageService.ttsSettings.ttsConcurrency;

        _audioCollector = OrderedAudioCollector(
          maxLookahead: _storageService.ttsSettings.ttsAudioLookahead,
        );
        _audioCollector!.reset(); // Ensure clean state for new utterance

        kDebugPrint(
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
            _cleanupFiles(results.whereType<File>().toList());
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

          _generationProgress = batchEnd / sentences.length;
          _notify();
        }
      }

      // wavFiles should be in correct order thanks to OrderedAudioCollector
      final validWavFiles = wavFiles.whereType<File>().toList();

      if (!mine() || validWavFiles.isEmpty) {
        _cleanupFiles(validWavFiles);
        return;
      }

      // Phase 2: Concatenate and play
      _isGenerating = false;
      _notify();

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
        _cleanupFiles(validWavFiles);
      }

      if (audioFile != null && mine()) {
        // Cache the audio for instant replay
        _cachedWav = audioFile;
        _cachedMessageId = messageId;
        _cachedTextHash = sanitized.hashCode;
        _cachedVoice = voice;
        _cachedEngine = _storageService.ttsSettings.ttsEngine;
        _cachedSpeed = speed;
        await _playWavFile(audioFile);
        // Don't delete — it's cached now
      }
    } on ElevenLabsApiException catch (e) {
      print('TTS ElevenLabs error: $e');
      // The state reset + notify live in the `finally` below, which runs on
      // this return too — a second copy here only risked the two drifting.
      _lastError = e.message;
      return;
    } catch (e) {
      print('TTS error: $e');
    } finally {
      // Only the owner may clear the shared state: a superseded call reaching
      // here must not switch off the Speak that replaced it.
      if (stillMine()) {
        _isSpeaking = false;
        _isGenerating = false;
        _generationProgress = 0.0;
        _currentMessageId = null;
        _notify();
      }
    }
  }
}
