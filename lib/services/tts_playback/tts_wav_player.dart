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

import 'package:audioplayers/audioplayers.dart';

/// Plays one audio file at a time and stops it on demand. Owns the
/// audioplayers [AudioPlayer] (constructed eagerly, with the service) and
/// the macOS `afplay` process.
class TtsWavPlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Process? _afplayProcess; // macOS audio playback process

  /// Play a WAV file.
  /// On macOS, uses the built-in `afplay` command for reliability
  /// (audioplayers has platform channel bugs on macOS).
  /// On other platforms, uses the audioplayers plugin.
  Future<void> play(File wavFile) async {
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
      void finish() {
        if (!completer.isCompleted) completer.complete();
      }

      final sub = _audioPlayer.onPlayerComplete.listen((_) => finish());
      // Manual stop() emits PlayerState.stopped, NOT onPlayerComplete — so
      // without this second listener, hanging up (or pressing Stop) mid-
      // sentence leaves this await hanging forever on Windows/Linux: the
      // caller's loop never returns, its temp WAVs are never cleaned up, and
      // the orphaned subscription fires into the NEXT session. macOS never
      // sees it because that platform plays through afplay above. Same guard
      // as the read-along player in story_reader_page.readalong.dart.
      final stopSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped) finish();
      });

      try {
        await _audioPlayer.play(DeviceFileSource(wavFile.path));
        await completer.future;
      } finally {
        await sub.cancel();
        await stopSub.cancel();
      }
    }
  }

  /// Kills `afplay` at once, then stops the plugin player.
  Future<void> stop() async {
    _afplayProcess?.kill();
    _afplayProcess = null;
    await _audioPlayer.stop();
  }

  void dispose() => _audioPlayer.dispose();
}
