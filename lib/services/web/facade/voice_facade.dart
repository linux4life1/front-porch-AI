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
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';

/// Audio bytes plus the MIME type to serve them with.
typedef AudioPayload = ({Uint8List bytes, String contentType});

/// Web adapter for voice: text-to-speech that synthesizes to a file (without
/// any host-side playback — the browser plays it on the *client* device) and
/// speech-to-text over an uploaded mic recording. Thin over [TtsService] and
/// [SttService]; all engine selection / model handling stays in those services.
class VoiceFacade {
  VoiceFacade(this._tts, this._stt, this._storage);

  final TtsService _tts;
  final SttService _stt;
  final StorageService _storage;

  /// Capability snapshot for the web client to decide which controls to show.
  Map<String, dynamic> status() => {
        'ttsEnabled': _storage.ttsEnabled,
        'ttsEngine': _storage.ttsEngine,
        'sttEnabled': _storage.sttEnabled,
        'sttAvailable': _stt.isAvailable,
      };

  /// Synthesize [text] to audio bytes (no host playback). Returns the bytes plus
  /// their MIME type, or null when TTS is off / produced nothing.
  Future<AudioPayload?> speak(String text, {String? voiceKey}) async {
    if (!_storage.ttsEnabled || text.trim().isEmpty) return null;
    final file = await _tts.generateAudioFile(text, voiceKey: voiceKey);
    if (file == null || !file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    // ElevenLabs returns mp3; every other engine returns a (merged) WAV.
    final contentType =
        p.extension(file.path).toLowerCase() == '.mp3' ? 'audio/mpeg' : 'audio/wav';
    return (bytes: bytes, contentType: contentType);
  }

  /// Transcribe uploaded mic audio recorded on the client device. [bytes] is the
  /// raw recording; [ext] is its container extension (e.g. `webm`, `wav`) so the
  /// temp file Whisper reads has a sensible suffix. Returns the text or null.
  Future<String?> transcribe(List<int> bytes, {String? ext}) async {
    if (!_stt.isAvailable || bytes.isEmpty) return null;
    final safeExt = (ext == null || ext.isEmpty)
        ? 'webm'
        : ext.replaceAll(RegExp(r'[^a-z0-9]'), '').toLowerCase();
    final tmp = File(p.join(
      Directory.systemTemp.path,
      'fpai_web_stt_${bytes.length}_${bytes.hashCode}.$safeExt',
    ));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      return await _stt.transcribeAudioFile(tmp.path);
    } finally {
      if (tmp.existsSync()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }
}
