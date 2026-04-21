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
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/kokoro_engine.dart';
import 'package:front_porch_ai/services/openai_tts_engine.dart';
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// Text-to-speech service — multi-engine architecture.
///
/// Supports: Kokoro (local, default), OpenAI TTS (cloud), Piper (fallback).
/// Handles buffered playback, progress tracking, and text sanitization.
class TtsService extends ChangeNotifier {
  final StorageService _storageService;
  final VoiceManager _voiceManager;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Engines
  late final KokoroEngine _kokoroEngine = KokoroEngine(_storageService);
  final OpenAiTtsEngine _openaiEngine = OpenAiTtsEngine();
  final ElevenLabsTtsEngine _elevenlabsEngine = ElevenLabsTtsEngine();

  Process? _piperProcess;
  bool _isSpeaking = false;
  bool _isGenerating = false;
  String? _currentMessageId;
  double _generationProgress = 0.0;
  double _modelDownloadProgress = 0.0;
  bool _isDownloadingModel = false;
  Process? _afplayProcess; // macOS audio playback process

  // Audio cache — keeps the last generated WAV for instant replay
  File? _cachedWav;
  String? _cachedMessageId;
  int? _cachedTextHash; // hash of sanitized text to detect edits
  String? _cachedVoice;
  String? _cachedEngine;

  bool get isSpeaking => _isSpeaking;
  bool get isGenerating => _isGenerating;
  String? get currentMessageId => _currentMessageId;
  double get generationProgress => _generationProgress;
  double get modelDownloadProgress => _modelDownloadProgress;
  bool get isDownloadingModel => _isDownloadingModel;

  /// Last error message from a TTS engine (e.g. quota exceeded).
  /// The UI should observe this and show a snackbar/alert when non-null.
  String? _lastError;
  String? get lastError => _lastError;
  void clearError() { _lastError = null; notifyListeners(); }

  /// The currently active TTS engine instance.
  TtsEngine get activeEngine {
    switch (_storageService.ttsEngine) {
      case 'openai':
        _openaiEngine.apiKey = _storageService.openaiTtsApiKey;
        _openaiEngine.model = _storageService.openaiTtsModel;
        _openaiEngine.baseUrl = _storageService.openaiTtsBaseUrl;
        return _openaiEngine;
      case 'elevenlabs':
        _elevenlabsEngine.apiKey = _storageService.elevenlabsApiKey;
        _elevenlabsEngine.model = _storageService.elevenlabsModel;
        _elevenlabsEngine.stability = _storageService.elevenlabsStability;
        _elevenlabsEngine.similarityBoost = _storageService.elevenlabsSimilarity;
        _elevenlabsEngine.style = _storageService.elevenlabsStyle;
        return _elevenlabsEngine;
      case 'kokoro':
        return _kokoroEngine;
      default:
        return _kokoroEngine; // Piper handled separately for backward compat
    }
  }

  /// Whether the current engine is Piper (legacy path).
  bool get _isPiperEngine => _storageService.ttsEngine == 'piper';

  /// Available voices for the active engine.
  List<TtsVoiceInfo> get activeVoices => activeEngine.availableVoices;

  /// Manually download / ensure the model for the active engine is ready.
  /// Returns true if the model is ready after this call.
  Future<bool> downloadModel() async {
    if (_isDownloadingModel) return false; // already downloading
    _isDownloadingModel = true;
    _modelDownloadProgress = 0.0;
    notifyListeners();

    try {
      final ready = await activeEngine.ensureModelReady(onProgress: (p) {
        _modelDownloadProgress = p;
        notifyListeners();
      });
      return ready;
    } catch (e) {
      print('TTS downloadModel error: $e');
      return false;
    } finally {
      _isDownloadingModel = false;
      notifyListeners();
    }
  }

  /// Whether the active engine's model files are already downloaded.
  Future<bool> isModelDownloaded() => activeEngine.isAvailable;

  TtsService(this._storageService, this._voiceManager);

  @override
  void dispose() {
    stop();
    _clearCache();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Speak the given text using the active TTS engine.
  ///
  /// Generates audio for the entire message first (buffered), then plays
  /// it back seamlessly. Shows generation progress.
  Future<void> speak(String text, {String? voiceKey, String? messageId}) async {
    if (!_storageService.ttsEnabled) {
      print('TTS: disabled, skipping');
      return;
    }

    _lastError = null;
    await stop();

    // Resolve voice
    final voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _storageService.ttsVoiceModel;
    if (voice.isEmpty) {
      print('TTS: no voice configured');
      return;
    }

    final sanitized = _sanitizeText(text);
    if (sanitized.trim().isEmpty) {
      print('TTS: text empty after sanitization');
      return;
    }

    // For Piper, check model file exists
    if (_isPiperEngine) {
      final modelPath = await _voiceManager.getVoiceModelPath(voice);
      if (!File(modelPath).existsSync()) {
        print('TTS: Piper voice model not found at $modelPath');
        return;
      }
    }

    // Check cache — replay instantly if same message & same content
    final textHash = sanitized.hashCode;
    if (messageId != null &&
        messageId == _cachedMessageId &&
        textHash == _cachedTextHash &&
        voice == _cachedVoice &&
        _storageService.ttsEngine == _cachedEngine &&
        _cachedWav != null &&
        _cachedWav!.existsSync()) {
      print('TTS: cache hit for message $messageId');
      _isSpeaking = true;
      _isGenerating = false;
      _currentMessageId = messageId;
      notifyListeners();
      try {
        await _playWavFile(_cachedWav!);
      } catch (e) {
        print('TTS cache playback error: $e');
      } finally {
        _isSpeaking = false;
        _currentMessageId = null;
        notifyListeners();
      }
      return;
    }

    // Different message — clear old cache
    if (messageId != _cachedMessageId) {
      _clearCache();
    }

    print('TTS: engine=${_storageService.ttsEngine}, voice=$voice, text="${sanitized.substring(0, sanitized.length.clamp(0, 60))}..."');
    _isSpeaking = true;
    _isGenerating = true;
    _generationProgress = 0.0;
    _currentMessageId = messageId;
    notifyListeners();

    try {
      // For Kokoro, ensure model is downloaded
      if (_storageService.ttsEngine == 'kokoro') {
        final ready = await activeEngine.ensureModelReady(onProgress: (p) {
          _modelDownloadProgress = p;
          _isDownloadingModel = p < 1.0;
          notifyListeners();
        });
        _isDownloadingModel = false;
        if (!ready || !_isSpeaking) {
          print('TTS: Kokoro model not ready');
          return;
        }
      }

      final sentences = _splitSentences(sanitized);
      final wavFiles = List<File?>.filled(sentences.length, null);

      // Phase 1: Generate audio
      // ElevenLabs is fast enough to process full text in one request —
      // skip sentence splitting for better intonation and fewer API calls.
      if (_storageService.ttsEngine == 'elevenlabs') {
        final engine = activeEngine;
        final speed = _storageService.ttsSpeechRate;
        _generationProgress = 0.5;
        notifyListeners();
        final wav = await engine.generateAudio(sanitized, voice, speed);
        if (wav != null && _isSpeaking) {
          wavFiles[0] = wav;
        }
        _generationProgress = 1.0;
        notifyListeners();
      } else if (_isPiperEngine) {
        // Sequential for Piper (legacy)
        for (int i = 0; i < sentences.length; i++) {
          if (!_isSpeaking) break;
          final modelPath = await _voiceManager.getVoiceModelPath(voice);
          wavFiles[i] = await _generatePiperWav(sentences[i], modelPath, i);
          if (wavFiles[i] == null || !_isSpeaking) break;
          _generationProgress = (i + 1) / sentences.length;
          notifyListeners();
        }
      } else {
        // Parallel for Kokoro / OpenAI
        final engine = activeEngine;
        final speed = _storageService.ttsSpeechRate;
        final maxConcurrency = _storageService.ttsConcurrency;

        for (int batchStart = 0; batchStart < sentences.length; batchStart += maxConcurrency) {
          if (!_isSpeaking) break;

          final batchEnd = (batchStart + maxConcurrency).clamp(0, sentences.length);
          final futures = <Future<File?>>[];

          for (int i = batchStart; i < batchEnd; i++) {
            futures.add(engine.generateAudio(sentences[i], voice, speed));
          }

          final results = await Future.wait(futures);

          // Store results in order
          bool failed = false;
          for (int j = 0; j < results.length; j++) {
            if (results[j] == null || !_isSpeaking) { failed = true; break; }
            wavFiles[batchStart + j] = results[j];
          }
          if (failed) break;

          _generationProgress = batchEnd / sentences.length;
          notifyListeners();
        }
      }

      // Collect non-null results in order
      final validWavFiles = wavFiles.whereType<File>().toList();

      if (!_isSpeaking || validWavFiles.isEmpty) {
        _cleanupFiles(validWavFiles);
        return;
      }

      // Phase 2: Concatenate and play
      _isGenerating = false;
      notifyListeners();

      File? audioFile;
      if (_storageService.ttsEngine == 'elevenlabs' && validWavFiles.length == 1) {
        // ElevenLabs returns a single MP3 — play directly, no WAV concat needed.
        audioFile = validWavFiles.first;
      } else {
        audioFile = await _concatenateWavFiles(validWavFiles);
        _cleanupFiles(validWavFiles);
      }

      if (audioFile != null && _isSpeaking) {
        // Cache the audio for instant replay
        _cachedWav = audioFile;
        _cachedMessageId = messageId;
        _cachedTextHash = sanitized.hashCode;
        _cachedVoice = voice;
        _cachedEngine = _storageService.ttsEngine;
        await _playWavFile(audioFile);
        // Don't delete — it's cached now
      }
    } on ElevenLabsApiException catch (e) {
      print('TTS ElevenLabs error: $e');
      _lastError = e.message;
      _isSpeaking = false;
      _isGenerating = false;
      _generationProgress = 0.0;
      _currentMessageId = null;
      notifyListeners();
      return;
    } catch (e) {
      print('TTS error: $e');
    } finally {
      _isSpeaking = false;
      _isGenerating = false;
      _generationProgress = 0.0;
      _currentMessageId = null;
      notifyListeners();
    }
  }

  /// Speak sentences as they arrive from a stream (for call mode).
  ///
  /// Uses a producer-consumer pattern: a producer generates audio files
  /// concurrently as sentences arrive, while a consumer plays them in order.
  /// An initial buffer of 3 sentences gives a head start so playback is smooth.
  Future<void> speakStreaming(Stream<String> sentenceStream, {String? voiceKey}) async {
    if (!_storageService.ttsEnabled) return;

    await stop();

    // Resolve voice
    final voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _storageService.ttsVoiceModel;
    if (voice.isEmpty) {
      print('TTS streaming: no voice configured');
      return;
    }

    // For Piper, check model exists
    if (_isPiperEngine) {
      final modelPath = await _voiceManager.getVoiceModelPath(voice);
      if (!File(modelPath).existsSync()) return;
    }

    // Ensure Kokoro model is ready
    if (_storageService.ttsEngine == 'kokoro') {
      final ready = await activeEngine.ensureModelReady(onProgress: (p) {
        _modelDownloadProgress = p;
        _isDownloadingModel = p < 1.0;
        notifyListeners();
      });
      _isDownloadingModel = false;
      if (!ready) return;
    }

    _isSpeaking = true;
    _isGenerating = true;
    _clearCache(); // no caching for streaming
    notifyListeners();

    final engine = activeEngine;
    final speed = _storageService.ttsSpeechRate;
    final tempFiles = <File>[];

    // Shared queue between producer and consumer
    final audioQueue = <File>[];
    bool producerDone = false;
    Completer<void>? audioAvailable;
    int bufferTarget = _storageService.callBufferSentences.clamp(1, 10);

    try {
      var maxConcurrency = _isPiperEngine ? 1 : _storageService.ttsConcurrency.clamp(1, 16);
      // ElevenLabs: one at a time from the stream (already fast enough)
      if (_storageService.ttsEngine == 'elevenlabs') maxConcurrency = 1;

      // ── Producer: fire off concurrent generation futures ──
      final orderedFutures = <Future<File?>>[];
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
          debugPrint('TTS streaming[$idx]: launching "$sanitized"');

          // Fire off generation without awaiting — runs concurrently
          final future = () async {
            File? wavFile;
            if (_isPiperEngine) {
              final modelPath = await _voiceManager.getVoiceModelPath(voice);
              wavFile = await _generatePiperWav(sanitized, modelPath, idx);
            } else {
              wavFile = await engine.generateAudio(sanitized, voice, speed);
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
          final file = completedFiles[nextToQueue]!;
          audioQueue.add(file);
          nextToQueue++;
          if (audioAvailable != null && !audioAvailable!.isCompleted) {
            audioAvailable!.complete();
          }
        }
      }

      // Wait for initial buffer to fill
      while (!producerDone && audioQueue.length < bufferTarget && _isSpeaking) {
        futureReady = Completer<void>();
        await futureReady!.future;
        collectReady();
      }

      // ── Consumer: play audio in order ──
      _isGenerating = false;
      notifyListeners();

      while (_isSpeaking) {
        collectReady(); // gather any newly completed results
        if (audioQueue.isNotEmpty) {
          final toPlay = audioQueue.removeAt(0);
          await _playWavFile(toPlay);
        } else if (producerDone && !completedFiles.containsKey(nextToQueue)) {
          break; // nothing left to play or generate
        } else {
          // Wait for more audio from producer
          futureReady = Completer<void>();
          await futureReady!.future;
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
      notifyListeners();

      // Clean up temp files
      _cleanupFiles(tempFiles);
    }
  }

  /// Generate audio for the given text and return the WAV file without playing.
  /// Used by the web server to stream audio to the browser.
  Future<File?> generateAudioFile(String text, {String? voiceKey}) async {
    if (!_storageService.ttsEnabled) return null;

    final voice = (voiceKey != null && voiceKey.isNotEmpty)
        ? voiceKey
        : _storageService.ttsVoiceModel;
    if (voice.isEmpty) return null;

    final sanitized = _sanitizeText(text);
    if (sanitized.trim().isEmpty) return null;

    if (_isPiperEngine) {
      final modelPath = await _voiceManager.getVoiceModelPath(voice);
      if (!File(modelPath).existsSync()) return null;
    }

    try {
      if (_storageService.ttsEngine == 'kokoro') {
        final ready = await activeEngine.ensureModelReady(onProgress: (_) {});
        if (!ready) return null;
      }

      final sentences = _splitSentences(sanitized);
      final wavFiles = <File>[];

      if (_storageService.ttsEngine == 'elevenlabs') {
        // ElevenLabs: send full text as one request for natural intonation
        final engine = activeEngine;
        final speed = _storageService.ttsSpeechRate;
        final wav = await engine.generateAudio(sanitized, voice, speed);
        if (wav != null) wavFiles.add(wav);
      } else if (_isPiperEngine) {
        for (int i = 0; i < sentences.length; i++) {
          final modelPath = await _voiceManager.getVoiceModelPath(voice);
          final wav = await _generatePiperWav(sentences[i], modelPath, i);
          if (wav == null) break;
          wavFiles.add(wav);
        }
      } else {
        final engine = activeEngine;
        final speed = _storageService.ttsSpeechRate;
        final maxConcurrency = _storageService.ttsConcurrency;

        for (int batchStart = 0; batchStart < sentences.length; batchStart += maxConcurrency) {
          final batchEnd = (batchStart + maxConcurrency).clamp(0, sentences.length);
          final futures = <Future<File?>>[];
          for (int i = batchStart; i < batchEnd; i++) {
            futures.add(engine.generateAudio(sentences[i], voice, speed));
          }
          final results = await Future.wait(futures);
          bool failed = false;
          for (final result in results) {
            if (result == null) { failed = true; break; }
            wavFiles.add(result);
          }
          if (failed) break;
        }
      }

      if (wavFiles.isEmpty) return null;

      // ElevenLabs returns a single MP3 — skip WAV concatenation.
      if (_storageService.ttsEngine == 'elevenlabs' && wavFiles.length == 1) {
        return wavFiles.first;
      }

      final combinedWav = await _concatenateWavFiles(wavFiles);
      _cleanupFiles(wavFiles);
      return combinedWav;
    } catch (e) {
      print('TTS generateAudioFile error: $e');
      return null;
    }
  }

  /// Stop any active speech.
  Future<void> stop() async {
    _isSpeaking = false;
    _isGenerating = false;
    _generationProgress = 0.0;
    _currentMessageId = null;

    _piperProcess?.kill();
    _piperProcess = null;

    _afplayProcess?.kill();
    _afplayProcess = null;

    await _audioPlayer.stop();
    notifyListeners();
  }

  // ---- Piper legacy support ----

  /// Resolve the path to the bundled Piper binary (PyInstaller --onedir bundle).
  String _piperBinaryPath() {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      return p.join(execDir, 'piper', 'piper', 'piper.exe');
    } else if (Platform.isMacOS) {
      final contentsDir = File(Platform.resolvedExecutable).parent.parent.path;
      return p.join(contentsDir, 'Resources', 'piper', 'piper', 'piper');
    } else {
      return p.join(execDir, 'piper', 'piper', 'piper');
    }
  }

  /// Check if the Piper binary is available.
  bool get isPiperAvailable {
    try {
      return File(_piperBinaryPath()).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Generate a WAV file using Piper.
  Future<File?> _generatePiperWav(String text, String modelPath, int index) async {
    try {
      final piperPath = _piperBinaryPath();
      final voicesDir = p.dirname(modelPath);
      final voiceName = p.basenameWithoutExtension(modelPath);

      final tempDir = Directory.systemTemp;
      final wavFile = File(p.join(tempDir.path,
          'piper_tts_${DateTime.now().millisecondsSinceEpoch}_$index.wav'));

      _piperProcess = await Process.start(piperPath, [
        '-m', voiceName,
        '--data-dir', voicesDir,
        '-f', wavFile.path,
      ]);

      _piperProcess!.stdin.writeln(text);
      await _piperProcess!.stdin.close();

      final stderr = await _piperProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      if (stderr.isNotEmpty) print('Piper stderr: $stderr');

      final exitCode = await _piperProcess!.exitCode;
      _piperProcess = null;

      if (exitCode != 0 || !wavFile.existsSync() || wavFile.lengthSync() == 0) {
        print('Piper failed with exit code $exitCode');
        return null;
      }
      return wavFile;
    } catch (e) {
      print('Piper error: $e');
      _piperProcess = null;
      return null;
    }
  }

  // ---- Audio utilities ----

  /// Concatenate multiple WAV files into a single WAV file.
  Future<File?> _concatenateWavFiles(List<File> wavFiles) async {
    if (wavFiles.isEmpty) return null;
    if (wavFiles.length == 1) return wavFiles.first;

    try {
      final firstBytes = await wavFiles.first.readAsBytes();
      if (firstBytes.length < 44) return null;

      final bd = ByteData.sublistView(firstBytes);
      final sampleRate = bd.getUint32(24, Endian.little);
      final channels = bd.getUint16(22, Endian.little);
      final bitsPerSample = bd.getUint16(34, Endian.little);
      final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
      final blockAlign = channels * (bitsPerSample ~/ 8);

      final pcmChunks = <Uint8List>[];
      int totalPcmBytes = 0;

      for (final file in wavFiles) {
        final bytes = await file.readAsBytes();
        if (bytes.length <= 44) continue;

        int dataOffset = 12;
        while (dataOffset < bytes.length - 8) {
          final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
          final chunkSize = ByteData.sublistView(bytes).getUint32(dataOffset + 4, Endian.little);
          if (chunkId == 'data') {
            final pcmStart = dataOffset + 8;
            final pcmEnd = (pcmStart + chunkSize).clamp(0, bytes.length);
            final pcm = bytes.sublist(pcmStart, pcmEnd);
            pcmChunks.add(Uint8List.fromList(pcm));
            totalPcmBytes += pcm.length;
            break;
          }
          dataOffset += 8 + chunkSize;
        }
      }

      if (totalPcmBytes == 0) return null;

      final fileSize = 36 + totalPcmBytes;
      final header = ByteData(44);
      // RIFF
      header.setUint8(0, 0x52); header.setUint8(1, 0x49);
      header.setUint8(2, 0x46); header.setUint8(3, 0x46);
      header.setUint32(4, fileSize, Endian.little);
      header.setUint8(8, 0x57); header.setUint8(9, 0x41);
      header.setUint8(10, 0x56); header.setUint8(11, 0x45);
      // fmt
      header.setUint8(12, 0x66); header.setUint8(13, 0x6D);
      header.setUint8(14, 0x74); header.setUint8(15, 0x20);
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, channels, Endian.little);
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(28, byteRate, Endian.little);
      header.setUint16(32, blockAlign, Endian.little);
      header.setUint16(34, bitsPerSample, Endian.little);
      // data
      header.setUint8(36, 0x64); header.setUint8(37, 0x61);
      header.setUint8(38, 0x74); header.setUint8(39, 0x61);
      header.setUint32(40, totalPcmBytes, Endian.little);

      final tempDir = Directory.systemTemp;
      final combinedFile = File(p.join(tempDir.path,
          'tts_combined_${DateTime.now().millisecondsSinceEpoch}.wav'));
      final sink = combinedFile.openWrite();
      sink.add(header.buffer.asUint8List());
      for (final chunk in pcmChunks) {
        sink.add(chunk);
      }
      await sink.close();

      return combinedFile;
    } catch (e) {
      print('Error concatenating WAV files: $e');
      return null;
    }
  }

  void _cleanupFiles(List<File> files) {
    for (final file in files) {
      try { file.deleteSync(); } catch (_) {}
    }
  }

  /// Delete the cached audio file and reset cache state.
  void _clearCache() {
    if (_cachedWav != null) {
      try { _cachedWav!.deleteSync(); } catch (_) {}
      _cachedWav = null;
    }
    _cachedMessageId = null;
    _cachedTextHash = null;
    _cachedVoice = null;
    _cachedEngine = null;
  }

  /// Play a WAV file.
  /// On macOS, uses the built-in `afplay` command for reliability
  /// (audioplayers has platform channel bugs on macOS).
  /// On other platforms, uses the audioplayers plugin.
  Future<void> _playWavFile(File wavFile) async {
    if (Platform.isMacOS) {
      // Use macOS built-in afplay for reliable playback
      try {
        _afplayProcess = await Process.start('afplay', [wavFile.path]);
        final exitCode = await _afplayProcess!.exitCode;
        _afplayProcess = null;
        if (exitCode != 0) {
          print('afplay exited with code $exitCode');
        }
      } catch (e) {
        _afplayProcess = null;
        print('afplay failed: $e');
      }
    } else {
      final completer = Completer<void>();

      late StreamSubscription sub;
      sub = _audioPlayer.onPlayerComplete.listen((_) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      });

      await _audioPlayer.play(DeviceFileSource(wavFile.path));
      await completer.future;
    }
  }

  // ---- Text processing ----

  /// Sanitize text for TTS: apply narration filters, remove think tags, markdown, emotes, OOC, etc.
  String _sanitizeText(String text) {
    var result = text;

    // ── Narration filters (SillyTavern-style) ──
    // Step 1: If ignoreAsterisks, remove all *...* blocks (including content inside them)
    if (_storageService.ttsIgnoreAsterisks) {
      // Handle multi-line action blocks: *action across\nmultiple lines*
      result = result.replaceAll(RegExp(r'\*[^*]+\*', dotAll: true), ' ');
    }
    // Step 2: If narrateQuotedOnly, extract only text within quotes (straight or curly)
    if (_storageService.ttsNarrateQuotedOnly) {
      // Match both straight "..." and curly "..." quotes
      final quotePattern = RegExp(r'(?:"([^"]+)"|["\u201C]([^\u201D"]+)["\u201D])');
      final matches = quotePattern.allMatches(result);
      final extracted = matches.map((m) => m.group(1) ?? m.group(2) ?? '').where((s) => s.trim().isNotEmpty).toList();
      result = extracted.isNotEmpty ? extracted.join('... ') : '';
    }

    // ── Standard cleanup ──
    result = result.replaceAll(RegExp(r'<think>.*?</think>', caseSensitive: false, dotAll: true), '');
    result = result.replaceAll(RegExp(r'<think>.*$', caseSensitive: false, dotAll: true), '');
    result = result.replaceAll(RegExp(r'\(OOC:.*?\)', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'\[OOC:.*?\]', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'\*'), '');
    result = result.replaceAll(RegExp(r'#{1,6}\s'), '');
    result = result.replaceAll(RegExp(r'[_~`]'), '');
    result = result.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1');
    result = result.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '');
    result = result.replaceAll(RegExp(r':[a-zA-Z0-9_]+:'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
  }

  /// Split text into sentences for progress tracking.
  List<String> _splitSentences(String text) {
    final sentences = <String>[];
    final parts = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      if (sentences.isNotEmpty && sentences.last.length < 20) {
        sentences.last = '${sentences.last} ${part.trim()}';
      } else {
        sentences.add(part.trim());
      }
    }
    if (sentences.isEmpty && text.trim().isNotEmpty) {
      sentences.add(text.trim());
    }
    return sentences;
  }
}
