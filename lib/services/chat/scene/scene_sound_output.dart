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
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/audio_playback.dart';

import 'scene_sound_service.dart';

/// The scene sound on audioplayers: a ping-pong pair of players looping
/// the ambience and one for the thunder, as the story reader plays its
/// ambient loop and page turn (`lib/ui/pages/story_reader_page.dart`). The
/// files are bundled MP3s, which every desktop backend audioplayers uses
/// decodes (Media Foundation on Windows, AVPlayer on macOS, GStreamer on
/// Linux). Players are built on first use through [AudioPlayback]; where
/// it says no, every call is silent.
///
/// The loop does NOT ride `ReleaseMode.loop`: that mode lets the file
/// finish, then asynchronously seeks back to zero and resumes, and on
/// macOS the gap between the last sample and the restarted first one is
/// occasionally long enough to hear — a periodic hitch in the rain
/// (WrappedMediaPlayer.swift: onComplete → seek(0) → resume). Two players
/// take turns instead: when the lead nears the end of the file, the idle
/// one starts the same file from zero and the pair crossfades across the
/// seam over [kSceneLoopSeam], so sound never stops. The recordings cut
/// in `dl/ambient-src/` are seam-continuous (tail into head), so a gentle
/// equal-power crossfade over them is inaudible.
class AudioplayersSceneSoundOutput implements SceneSoundOutput {
  AudioplayersSceneSoundOutput({
    @visibleForTesting Future<AudioPlayer?> Function()? playerFactory,
  }) : _newPlayer = playerFactory ?? AudioPlayback.create;

  final Future<AudioPlayer?> Function() _newPlayer;

  /// How early before the end of file the handover starts. Long enough
  /// for a player to spin up and crossfade, short enough to stay
  /// inaudible on rain and wind.
  static const kSceneLoopSeam = Duration(milliseconds: 600);

  /// The watch's poll step: finer than the seam, cheap next to decoding.
  static const _tick = Duration(milliseconds: 50);

  // Two ping-pong slots; [_leadAt] is the index of the looping player and
  // the other is the handover the seam fades into.
  final List<AudioPlayer?> _players = [null, null];
  final List<Future<AudioPlayer?>?> _making = [null, null];
  Future<AudioPlayer?>? _shot;
  int _leadAt = 0;
  AudioPlayer? _takeover;
  String? _asset;
  Duration _duration = Duration.zero;
  double _gain = 1;
  double _crossF = 0;
  bool _crossing = false;
  bool _paused = false;
  int _gen = 0;
  Timer? _watch;

  AudioPlayer? get _lead => _players[_leadAt];

  @override
  Future<void> loop(String? asset, double volume) async {
    final gen = ++_gen;
    _watch?.cancel();
    _watch = null;
    _paused = false;
    _gain = volume;
    _takeover = null;
    _crossing = false;
    _crossF = 0;
    if (asset == null) {
      _asset = null;
      await _stopAll();
      return;
    }
    final lead = await _slot(0);
    if (gen != _gen) return;
    if (lead == null) return;
    _leadAt = 0;
    // Warm the handover slot now; a loop's first seam must find it ready.
    unawaited(_slot(1));
    _asset = asset;
    await _stopOther();
    await lead.setReleaseMode(ReleaseMode.stop);
    await lead.play(_sourceFor(asset), volume: volume);
    final duration = await _durationOf(lead);
    if (gen != _gen) return;
    _duration = duration;
    if (_duration > kSceneLoopSeam * 2) {
      _watch = Timer.periodic(_tick, (_) => _onTick(gen));
    } else {
      // No reportable length (or a file shorter than two seams): ride the
      // native loop. It hitches at the seam sometimes, but it plays.
      await lead.setReleaseMode(ReleaseMode.loop);
    }
  }

  @override
  Future<void> setLoopVolume(double volume) async {
    _gain = volume;
    final lead = _lead;
    if (lead == null) return;
    await _setMix(lead);
  }

  @override
  Future<void> pauseLoop() async {
    _paused = true;
    final lead = _lead;
    final over = _takeover;
    if (lead != null) await _quietly(lead.pause(), 'pause the loop');
    if (over != null) await _quietly(over.pause(), 'pause the handover');
  }

  @override
  Future<void> resumeLoop() async {
    _paused = false;
    final lead = _lead;
    final over = _takeover;
    if (over != null) await _quietly(over.resume(), 'resume the handover');
    if (lead != null) await _quietly(lead.resume(), 'resume the loop');
  }

  @override
  Future<void> oneShot(String asset, double volume) async {
    final player = await (_shot ??= _newPlayer());
    await player?.play(AssetSource(asset), volume: volume);
  }

  @override
  Future<void> dispose() async {
    _gen++;
    _watch?.cancel();
    _watch = null;
    _takeover = null;
    for (var i = 0; i < _players.length; i++) {
      final player = _players[i];
      if (player == null) continue;
      await _quietly(player.dispose(), 'release a loop player');
    }
    _players[0] = null;
    _players[1] = null;
    final shot = await _shot;
    if (shot != null) await _quietly(shot.dispose(), 'release the shot player');
  }

  void _onTick(int gen) {
    if (_paused || gen != _gen) return;
    unawaited(_step(gen));
  }

  Future<void> _step(int gen) async {
    final lead = _lead;
    final asset = _asset;
    if (lead == null || asset == null) return;
    final pos = await _position(lead);
    if (gen != _gen || _paused || _lead != lead) return;
    final seamAt = _duration - kSceneLoopSeam;
    if (_takeover == null) {
      if (pos < seamAt || _crossing) return;
      _crossing = true;
      unawaited(_beginCross(lead, asset, gen));
      return;
    }
    final into = pos - seamAt;
    _crossF = (into.inMilliseconds / kSceneLoopSeam.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    await _setMix(lead);
    if (gen != _gen || _lead != lead) return;
    // The lead reaches end of file inside the window (ReleaseMode.stop
    // leaves it there); by then the handover holds the full gain, so
    // swapping roles has no silence around it.
    if (_crossF >= 1.0) {
      final over = _takeover!;
      _takeover = null;
      _crossing = false;
      _crossF = 0;
      _leadAt = 1 - _leadAt;
      await _quietly(lead.stop(), 'stop the crossed player');
      assert(identical(_lead, over));
    }
  }

  Future<void> _beginCross(AudioPlayer lead, String asset, int gen) async {
    final over = await _slot(1 - _leadAt);
    if (gen != _gen || _paused || _lead != lead) {
      _crossing = false;
      return;
    }
    if (over == null) {
      // No handover player: the best a single player can do is seek home
      // while it still has runway — often seamless, sometimes one hitch.
      _crossing = false;
      await _quietly(lead.seek(Duration.zero), 'rewind the loop');
      return;
    }
    _takeover = over;
    try {
      await over.setReleaseMode(ReleaseMode.stop);
      await over.play(_sourceFor(asset), volume: 0);
    } catch (e) {
      if (_takeover == over) {
        _takeover = null;
        _crossing = false;
      }
      await _quietly(
        lead.seek(Duration.zero),
        'rewind the loop after a failed handover',
      );
      debugPrint(
        'SceneSound: loop handover failed, riding the native seek: $e',
      );
    }
  }

  /// The current mix: all gain to the lead, or the equal-power split of
  /// the seam while a handover crosses.
  Future<void> _setMix(AudioPlayer lead) async {
    final over = _takeover;
    if (over == null) {
      await _quietly(lead.setVolume(_gain), 'set the loop volume');
      return;
    }
    final angle = _crossF * math.pi / 2;
    await _quietly(
      lead.setVolume(_gain * math.cos(angle)),
      'fade the loop out across the seam',
    );
    await _quietly(
      over.setVolume(_gain * math.sin(angle)),
      'fade the handover in across the seam',
    );
  }

  /// Ping-pong slot [i]: created once through the factory; a failed
  /// creation is retried by the next caller.
  Future<AudioPlayer?> _slot(int i) async {
    final made = await (_making[i] ??= _newPlayer());
    if (made != null) {
      _players[i] = made;
      return made;
    }
    // Retry after a miss so a transient factory failure is not permanent.
    if (_making[i] != null) _making[i] = null;
    return _players[i];
  }

  /// Stops the slot the lead is NOT on (fresh swaps start the new file on
  /// the lead slot alone).
  Future<void> _stopOther() async {
    final other = _players[1 - _leadAt];
    if (other == null) return;
    try {
      await other.stop();
    } catch (e, st) {
      debugPrint('SceneSound: could not stop the idle player: $e\n$st');
      rethrow;
    }
  }

  Future<void> _stopAll() async {
    for (final player in _players) {
      if (player == null) continue;
      try {
        await player.stop();
      } catch (e, st) {
        debugPrint('SceneSound: could not stop a loop player: $e\n$st');
        rethrow;
      }
    }
  }

  Future<Duration> _position(AudioPlayer player) async {
    try {
      return await player.getCurrentPosition() ?? Duration.zero;
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<Duration> _durationOf(AudioPlayer player) async {
    try {
      final d = await player.getDuration();
      if (d != null && d > Duration.zero) return d;
    } catch (_) {
      // The duration stream may carry it when the call misses.
    }
    try {
      return await player.onDurationChanged
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<void> _quietly(Future<void> op, String what) async {
    try {
      await op;
    } catch (e, st) {
      debugPrint('SceneSound: could not $what: $e\n$st');
    }
  }

  /// Bundled assets keep their `audio/scene/` path, URLs their own, and a
  /// resolved device file plays from disk.
  static Source _sourceFor(String path) => path.startsWith('audio/')
      ? AssetSource(path)
      : (path.startsWith('http://') || path.startsWith('https://')
            ? UrlSource(path)
            : DeviceFileSource(path));
}
