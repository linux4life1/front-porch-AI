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
import 'package:front_porch_ai/services/kokoro_debug.dart';
import 'package:front_porch_ai/services/kokoro_chunk.dart';
import 'package:front_porch_ai/services/ordered_audio_collector.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/kokoro_engine.dart';
import 'package:front_porch_ai/services/openai_tts_engine.dart';
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/services/tts/sherpa_piper_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';

part 'tts_service.speak.dart';
part 'tts_service.streaming.dart';
part 'tts_service.support.dart';

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
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Engines
  late final KokoroEngine _kokoroEngine = KokoroEngine(_storageService);
  OrderedAudioCollector? _audioCollector;
  final OpenAiTtsEngine _openaiEngine = OpenAiTtsEngine();
  final ElevenLabsTtsEngine _elevenlabsEngine = ElevenLabsTtsEngine();

  bool _isSpeaking = false;
  bool _isGenerating = false;
  String? _currentMessageId;
  // The exact sentence the streaming (call-mode) playback is voicing right
  // now — the call overlay's live caption. Null outside streaming playback,
  // so captions can never show a line the character is not saying.
  String? _nowSpeaking;
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
  // Speed is part of the replay identity: without it, "play → move the
  // Speech Rate slider → play again" replayed the OLD-speed WAV, which made
  // the slider read as a no-op for Kokoro (whose generation plumbing was
  // actually fine) and masked Piper's real hardcoded-speed bug.
  double? _cachedSpeed;

  bool get isSpeaking => _isSpeaking;
  bool get isGenerating => _isGenerating;
  String? get currentMessageId => _currentMessageId;
  String? get nowSpeaking => _nowSpeaking;
  double get generationProgress => _generationProgress;
  double get modelDownloadProgress => _modelDownloadProgress;
  bool get isDownloadingModel => _isDownloadingModel;

  /// Last error message from a TTS engine (e.g. quota exceeded).
  /// The UI should observe this and show a snackbar/alert when non-null.
  String? _lastError;
  String? get lastError => _lastError;
  void clearError() {
    _lastError = null;
    _notify();
  }

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
    if (_isDownloadingModel) return false; // already downloading
    _isDownloadingModel = true;
    _modelDownloadProgress = 0.0;
    _notify();

    try {
      final ready = await activeEngine.ensureModelReady(
        onProgress: (p) {
          _modelDownloadProgress = p;
          _notify();
        },
      );
      return ready;
    } catch (e) {
      print('TTS downloadModel error: $e');
      return false;
    } finally {
      _isDownloadingModel = false;
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
    _clearCache();
    releaseLocalEngine();
    _audioPlayer.dispose();
    super.dispose();
  }

  // notifyListeners() is @protected/@visibleForTesting on ChangeNotifier, so
  // the extension parts (not instance members of TtsService itself) cannot
  // call it directly without analyzer warnings. Same forwarder pattern as
  // CharacterRepository and StoryPipelineService's split parts — and unlike a
  // public pass-through override, it does not widen the public API.
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
    _isSpeaking = false;
    _isGenerating = false;
    _generationProgress = 0.0;
    _currentMessageId = null;
    _nowSpeaking = null;

    _afplayProcess?.kill();
    _afplayProcess = null;

    await _audioPlayer.stop();
    if (_disposed) return;
    _notify();
  }
}
