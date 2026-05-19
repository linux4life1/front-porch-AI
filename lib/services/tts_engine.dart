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
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// Abstract interface that all TTS engines implement.
///
/// Each engine generates a WAV file from text — the TtsService handles 
/// playback, buffering, progress, and lifecycle.
abstract class TtsEngine {
  /// Human-readable engine name, e.g. 'Kokoro', 'OpenAI TTS', 'Piper'.
  String get engineName;

  /// Unique engine identifier: 'kokoro', 'openai', 'piper'.
  String get engineId;

  /// Check if this engine is ready to generate audio.
  Future<bool> get isAvailable;

  /// Generate a WAV audio file from the given text.
  /// Returns null if generation fails.
  ///
  /// [onProgress] is optional and only meaningfully used by Kokoro in verbatim
  /// ("read everything") mode to report 0.0–1.0 chunk completion for the UI spinner.
  Future<File?> generateAudio(
    String text,
    String voice,
    double speed, {
    void Function(double progress)? onProgress,
  });

  /// List of voices available for this engine.
  List<TtsVoiceInfo> get availableVoices;

  /// Optional: download required model files (e.g. Kokoro first-run).
  /// Returns true if ready, false if download failed.
  /// [onProgress] reports 0.0–1.0 download progress.
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async => true;
}
