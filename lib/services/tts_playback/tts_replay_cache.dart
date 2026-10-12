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

/// The last generated audio, kept for instant replay of the same message.
class TtsReplayCache {
  File? _wav;
  String? _messageId;
  int? _textHash; // hash of sanitized text to detect edits
  String? _voice;
  String? _engine;
  // Speed is part of the replay identity: without it, "play → move the
  // Speech Rate slider → play again" replayed the OLD-speed WAV, which made
  // the slider read as a no-op for Kokoro (whose generation plumbing was
  // actually fine) and masked Piper's real hardcoded-speed bug.
  double? _speed;

  String? get messageId => _messageId;

  /// The cached file when it was made for exactly this message, text,
  /// voice, engine and speed and is still on disk.
  File? hit({
    required String? messageId,
    required int textHash,
    required String voice,
    required String engine,
    required double speed,
  }) {
    final wav = _wav;
    if (messageId != null &&
        messageId == _messageId &&
        textHash == _textHash &&
        voice == _voice &&
        engine == _engine &&
        speed == _speed &&
        wav != null &&
        wav.existsSync()) {
      return wav;
    }
    return null;
  }

  void store(
    File wav, {
    required String? messageId,
    required int textHash,
    required String voice,
    required String engine,
    required double speed,
  }) {
    _wav = wav;
    _messageId = messageId;
    _textHash = textHash;
    _voice = voice;
    _engine = engine;
    _speed = speed;
  }

  /// Delete the cached audio file and reset cache state.
  void clear() {
    if (_wav != null) {
      try {
        _wav!.deleteSync();
      } catch (_) {}
      _wav = null;
    }
    _messageId = null;
    _textHash = null;
    _voice = null;
    _engine = null;
  }
}
