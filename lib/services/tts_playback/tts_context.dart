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

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts/sherpa_piper_engine.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/voice_manager.dart';

import 'tts_replay_cache.dart';
import 'tts_text.dart';
import 'tts_wav_player.dart';

/// What TtsService shows its listeners. The pipelines write it; every write
/// that should be heard is followed by [notify].
class TtsPlaybackState {
  TtsPlaybackState(this._notify);

  final void Function() _notify;

  bool isSpeaking = false;
  bool isGenerating = false;
  String? currentMessageId;
  // The exact sentence the streaming (call-mode) playback is voicing right
  // now — the call overlay's live caption. Null outside streaming playback,
  // so captions can never show a line the character is not saying.
  String? nowSpeaking;
  double generationProgress = 0.0;
  double modelDownloadProgress = 0.0;
  bool isDownloadingModel = false;

  /// Last error message from a TTS engine (e.g. quota exceeded).
  String? lastError;

  void notify() => _notify();
}

/// Everything the speak, streaming and headless pipelines share: settings,
/// voices, the observable state, the player, the replay cache, and the
/// in-process Piper engine. [activeEngine] and [stop] call back into
/// TtsService so its own members stay the ones that answer.
class TtsContext {
  TtsContext({
    required this.storage,
    required this.voiceManager,
    required this.state,
    required this.player,
    required this.cache,
    required SherpaPiperEngine piper,
    required TtsEngine Function() activeEngine,
    required Future<void> Function() stop,
  }) : _piper = piper,
       _activeEngine = activeEngine,
       _stop = stop;

  final StorageService storage;
  final VoiceManager voiceManager;
  final TtsPlaybackState state;
  final TtsWavPlayer player;
  final TtsReplayCache cache;
  final SherpaPiperEngine _piper;
  final TtsEngine Function() _activeEngine;
  final Future<void> Function() _stop;

  TtsEngine get activeEngine => _activeEngine();

  Future<void> stop() => _stop();

  bool get isPiperEngine => storage.ttsSettings.ttsEngine == 'piper';

  String sanitize(String text) {
    final s = storage.ttsSettings;
    return sanitizeTtsText(
      text,
      replaceCurlyQuotes: s.ttsReplaceCurlyQuotes,
      ignoreAsterisks: s.ttsIgnoreAsterisks,
      narrateQuotedOnly: s.ttsNarrateQuotedOnly,
    );
  }

  /// Makes sure the sherpa re-export for [voice] is on disk (downloading it
  /// on first use). Returns false — with [TtsPlaybackState.lastError] set and
  /// the failure tallied — when the voice can't be played: there is no
  /// legacy piper binary anymore, so a voice with no sherpa export (e.g. a
  /// hand-made custom voice) simply cannot speak.
  Future<bool> ensurePiperVoice(String voice) async {
    final root = storage.rootPath;
    if (root == null) return false;
    try {
      final ok = await SherpaPiperEngine.ensureVoice(root, voice);
      if (!ok) {
        state.lastError =
            'The voice "$voice" has no engine model on this machine. '
            'Official voices re-download from the Voice Model Browser; a '
            'custom voice can be re-imported there via "Add custom voice".';
        EngineHealth.instance.reportFailure(
          EngineHealth.piper,
          'no sherpa export for "$voice"',
          expected: true,
        );
      }
      return ok;
    } catch (e) {
      state.lastError = 'Piper voice download failed: $e';
      EngineHealth.instance.reportFailure(
        EngineHealth.piper,
        'voice download failed: $e',
      );
      return false;
    }
  }

  /// Generates one chunk of [text] with the in-process sherpa engine.
  /// Callers run [ensurePiperVoice] first (once per utterance).
  Future<File?> piperGenerateWav(
    String voice,
    String text,
    int index,
    double speed,
  ) async {
    try {
      final wav = await _piper.generate(
        root: storage.rootPath!,
        voiceKey: voice,
        text: text,
        speed: speed,
        outputPath: p.join(
          Directory.systemTemp.path,
          'piper_tts_${DateTime.now().millisecondsSinceEpoch}_$index.wav',
        ),
      );
      EngineHealth.instance.reportNative(EngineHealth.piper);
      return wav;
    } catch (e) {
      print('[TTS-Native] piper generation failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.piper,
        'generation failed: $e',
      );
      return null;
    }
  }
}
