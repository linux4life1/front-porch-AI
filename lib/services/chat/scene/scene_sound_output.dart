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
import 'package:front_porch_ai/services/audio_playback.dart';

import 'scene_sound_service.dart';

/// The scene sound on audioplayers: one player looping the ambience and
/// one for the thunder, as the story reader plays its ambient loop and
/// page turn (`lib/ui/pages/story_reader_page.dart`). The files are bundled
/// MP3s, which every desktop backend audioplayers uses decodes (Media
/// Foundation on Windows, AVPlayer on macOS, GStreamer on Linux). Players
/// are built on first use through [AudioPlayback]; where it says no, every
/// call is silent.
class AudioplayersSceneSoundOutput implements SceneSoundOutput {
  Future<AudioPlayer?>? _loop;
  Future<AudioPlayer?>? _shot;
  bool _looping = false;

  Future<AudioPlayer?> _loopPlayer() => _loop ??= AudioPlayback.create();

  @override
  Future<void> loop(String? asset, double volume) async {
    if (asset == null) {
      await (await _loop)?.stop();
      return;
    }
    final player = await _loopPlayer();
    if (player == null) return;
    if (!_looping) {
      await player.setReleaseMode(ReleaseMode.loop);
      _looping = true;
    }
    await player.play(AssetSource(asset), volume: volume);
  }

  @override
  Future<void> setLoopVolume(double volume) async =>
      (await _loop)?.setVolume(volume);

  @override
  Future<void> pauseLoop() async => (await _loop)?.pause();

  @override
  Future<void> resumeLoop() async => (await _loop)?.resume();

  @override
  Future<void> oneShot(String asset, double volume) async {
    final player = await (_shot ??= AudioPlayback.create());
    await player?.play(AssetSource(asset), volume: volume);
  }

  @override
  Future<void> dispose() async {
    await (await _loop)?.dispose();
    await (await _shot)?.dispose();
  }
}
