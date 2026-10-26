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

import 'package:audioplayers/audioplayers.dart';

import 'scene_sound_service.dart';

/// The scene sound on audioplayers: one player looping the ambience and
/// one for the thunder, as the story reader plays its ambient loop and
/// page turn (`lib/ui/pages/story_reader_page.dart`). The files are bundled
/// MP3s, which every desktop backend audioplayers uses decodes (Media
/// Foundation on Windows, AVPlayer on macOS, GStreamer on Linux).
class AudioplayersSceneSoundOutput implements SceneSoundOutput {
  final AudioPlayer _loop = AudioPlayer();
  final AudioPlayer _shot = AudioPlayer();
  bool _looping = false;

  @override
  Future<void> loop(String? asset, double volume) async {
    if (asset == null) {
      await _loop.stop();
      return;
    }
    if (!_looping) {
      await _loop.setReleaseMode(ReleaseMode.loop);
      _looping = true;
    }
    await _loop.play(AssetSource(asset), volume: volume);
  }

  @override
  Future<void> setLoopVolume(double volume) => _loop.setVolume(volume);

  @override
  Future<void> pauseLoop() => _loop.pause();

  @override
  Future<void> resumeLoop() => _loop.resume();

  @override
  Future<void> oneShot(String asset, double volume) =>
      _shot.play(AssetSource(asset), volume: volume);

  @override
  Future<void> dispose() async {
    await _loop.dispose();
    await _shot.dispose();
  }
}
