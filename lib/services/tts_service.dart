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
import 'package:front_porch_ai/services/audio_playback.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/kokoro_engine.dart';
import 'package:front_porch_ai/services/openai_tts_engine.dart';
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/services/tts/sherpa_piper_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';
import 'package:front_porch_ai/services/tts_playback/tts_playback.dart';

/// Text-to-speech service — multi-engine architecture.
///
/// Supports: Kokoro (local, default), Piper (local), OpenAI TTS (cloud),
/// ElevenLabs (cloud). Handles buffered playback, progress tracking, and
/// text sanitization. All local audio is generated in-process by
/// sherpa-onnx (docs/design/sidecar-retirement.md — no Python involved).
class TtsService extends ChangeNotifier {
  final StorageService _storageService;
  final VoiceManager _voiceManager;

  /// In-process sherpa vits engine for Piper voices (phase 4b).
  final SherpaPiperEngine _piperNative = SherpaPiperEngine();
  late final TtsWavPlayer _player = TtsWavPlayer(
    onUnavailable: () => _state.lastError = AudioPlayback.missingMessage,
  );
  final TtsReplayCache _cache = TtsReplayCache();
  late final TtsPlaybackState _state = TtsPlaybackState(_notify);
  late final TtsContext _context = TtsContext(
    storage: _storageService,
    voiceManager: _voiceManager,
    state: _state,
    player: _player,
    cache: _cache,
    piper: _piperNative,
    activeEngine: () => activeEngine,
    stop: () => stop(),
  );
  late final TtsSpeaker _speaker = TtsSpeaker(_context);
  late final TtsStreamer _streamer = TtsStreamer(_context);
  late final TtsHeadlessGenerator _headless = TtsHeadlessGenerator(_context);

  // Engines
  late final KokoroEngine _kokoroEngine = KokoroEngine(_storageService);
  final OpenAiTtsEngine _openaiEngine = OpenAiTtsEngine();
  final ElevenLabsTtsEngine _elevenlabsEngine = ElevenLabsTtsEngine();

  bool get isSpeaking => _state.isSpeaking;
  bool get isGenerating => _state.isGenerating;
  String? get currentMessageId => _state.currentMessageId;

  /// The exact sentence the streaming (call-mode) playback is voicing now.
  String? get nowSpeaking => _state.nowSpeaking;
  double get generationProgress => _state.generationProgress;
  double get modelDownloadProgress => _state.modelDownloadProgress;
  bool get isDownloadingModel => _state.isDownloadingModel;

  /// Last error message from a TTS engine (e.g. quota exceeded).
  /// The UI should observe this and show a snackbar/alert when non-null.
  String? get lastError => _state.lastError;
  void clearError() {
    _state.lastError = null;
    _notify();
  }

  /// Speak the given text using the active TTS engine.
  ///
  /// Generates audio for the entire message first (buffered), then plays
  /// it back seamlessly. Shows generation progress.
  Future<void> speak(String text, {String? voiceKey, String? messageId}) =>
      _speaker.speak(text, voiceKey: voiceKey, messageId: messageId);

  /// Speak sentences as they arrive from a stream (for call mode).
  Future<void> speakStreaming(
    Stream<String> sentenceStream, {
    String? voiceKey,
  }) => _streamer.speakStreaming(sentenceStream, voiceKey: voiceKey);

  /// Generate audio for the given text and return the WAV file without playing.
  /// Used by the web server to stream audio to the browser.
  Future<File?> generateAudioFile(String text, {String? voiceKey}) =>
      _headless.generateAudioFile(text, voiceKey: voiceKey);

  /// The currently active TTS engine instance.
  TtsEngine get activeEngine {
    switch (_storageService.ttsSettings.ttsEngine) {
      case 'openai':
        _openaiEngine.apiKey = _storageService.ttsSettings.openaiTtsApiKey;
        _openaiEngine.model = _storageService.ttsSettings.openaiTtsModel;
        _openaiEngine.baseUrl = _storageService.ttsSettings.openaiTtsBaseUrl;
        return _openaiEngine;
      case 'elevenlabs':
        _elevenlabsEngine.apiKey = _storageService.ttsSettings.elevenlabsApiKey;
        _elevenlabsEngine.model = _storageService.ttsSettings.elevenlabsModel;
        _elevenlabsEngine.stability =
            _storageService.ttsSettings.elevenlabsStability;
        _elevenlabsEngine.similarityBoost =
            _storageService.ttsSettings.elevenlabsSimilarity;
        _elevenlabsEngine.style = _storageService.ttsSettings.elevenlabsStyle;
        return _elevenlabsEngine;
      case 'kokoro':
        return _kokoroEngine;
      default:
        return _kokoroEngine; // Piper handled separately for backward compat
    }
  }

  /// Whether the current engine is Piper.
  bool get _isPiperEngine => _storageService.ttsSettings.ttsEngine == 'piper';

  /// Cached voices for the currently selected engine.
  /// This is the source of truth used by UI pickers.
  List<TtsVoiceInfo> _currentAvailableVoices = const [];

  /// Engine id [_currentAvailableVoices] was built for — engine switches
  /// invalidate the cache here so no switch site has to remember to refresh.
  String _voicesCacheEngine = '';

  /// Available voices for the currently selected TTS engine.
  ///
  /// When the engine is 'piper', this returns real installed voices
  /// (including manually added custom voices) instead of falling back to Kokoro.
  List<TtsVoiceInfo> get activeVoices {
    if (_voicesCacheEngine != _storageService.ttsSettings.ttsEngine) {
      // Stale cache from the previously selected engine (the voice dropdown
      // used to keep showing Piper voices after switching to Kokoro). Serve
      // the new engine's built-ins immediately and refresh asynchronously
      // (scheduled as a new event — refresh notifies, and this getter can
      // run during build).
      unawaited(Future(refreshAvailableVoices));
      return _piperSafeFallback;
    }
    return _currentAvailableVoices.isNotEmpty
        ? _currentAvailableVoices
        : _piperSafeFallback;
  }

  /// Built-in voices to serve when the cache is empty or stale.
  ///
  /// Piper has none: its voices live on disk, and [activeEngine] falls through
  /// to `_kokoroEngine` for Piper (see its `default:` branch), so the old
  /// fallback offered the 53-entry Kokoro catalog under the Piper engine.
  /// Picking one of those produced silence — Piper has no such model and never
  /// can. An empty list is honest, and every picker already handles it.
  List<TtsVoiceInfo> get _piperSafeFallback =>
      _isPiperEngine ? const [] : activeEngine.availableVoices;

  /// Refreshes the voice list for the currently selected engine.
  /// Particularly important for Piper, where voices can be added manually
  /// (custom .onnx files) or via the Voice Browser.
  Future<void> refreshAvailableVoices() async {
    _voicesCacheEngine = _storageService.ttsSettings.ttsEngine;
    if (_isPiperEngine) {
      try {
        _currentAvailableVoices = await _voiceManager
            .getInstalledPiperVoicesAsTtsVoiceInfo();
      } catch (e) {
        print('TTS: Failed to refresh Piper voices: $e');
        _currentAvailableVoices = const [];
      }
    } else {
      _currentAvailableVoices = activeEngine.availableVoices;
    }
    _notify();
  }

  /// Manually download / ensure the model for the active engine is ready.
  /// Returns true if the model is ready after this call.
  Future<bool> downloadModel() async {
    if (_state.isDownloadingModel) return false; // already downloading
    _state.isDownloadingModel = true;
    _state.modelDownloadProgress = 0.0;
    _notify();

    try {
      final ready = await activeEngine.ensureModelReady(
        onProgress: (p) {
          _state.modelDownloadProgress = p;
          _notify();
        },
      );
      return ready;
    } catch (e) {
      print('TTS downloadModel error: $e');
      return false;
    } finally {
      _state.isDownloadingModel = false;
      _notify();
    }
  }

  /// Whether the active engine's model files are already downloaded.
  Future<bool> isModelDownloaded() => activeEngine.isAvailable;

  TtsService(this._storageService, this._voiceManager) {
    // Prime the voice list for the current engine (important for Piper + custom voices)
    unawaited(refreshAvailableVoices());
  }

  /// Set before teardown begins: dispose() fires stop() un-awaited (dispose
  /// must stay synchronous), and stop() resumes after an async gap — by then
  /// the notifier is disposed and notifyListeners() would assert in debug.
  bool _disposed = false;

  /// Drop the ~380MB Kokoro isolate when TTS is switched off (dispose only
  /// ran on app quit, so disable left the worker alive).
  void releaseLocalEngine() {
    _kokoroEngine.shutdown();
    _piperNative.shutdown();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _cache.clear();
    releaseLocalEngine();
    _player.dispose();
    super.dispose();
  }

  // The pipelines' state writes are heard through this (handed to
  // TtsPlaybackState); notifyListeners() itself is @protected.
  //
  // Disposed-guarded: dispose() fires stop() un-awaited (it must stay
  // synchronous), and speak()'s own tail resumes after async gaps — on a
  // slow machine either can land after teardown and notifyListeners() on a
  // disposed ChangeNotifier asserts in debug (Linux CI caught it; the dev
  // Mac never lost the race).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stop any active speech.
  Future<void> stop() async {
    _state.isSpeaking = false;
    _state.isGenerating = false;
    _state.generationProgress = 0.0;
    _state.currentMessageId = null;
    _state.nowSpeaking = null;

    await _player.stop();
    if (_disposed) return;
    _notify();
  }
}
