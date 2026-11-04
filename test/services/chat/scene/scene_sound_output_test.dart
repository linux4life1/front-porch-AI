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

// The seam itself (docs/design/ambient-stage.md §5): the loop must never
// stop to restart, because the native ReleaseMode.loop ends the file,
// seeks and resumes, and that gap is the periodic hitch the maintainer
// hears in the rain. These pin the ping-pong handover: the idle player is
// already sounding before the lead stops, the gains crossfade, the pair
// swap and keep alternating, a player without a duration still loops,
// and hold/resume reach the players that actually have the sound.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound_output.dart';

/// Shared virtual transport: one pump step is one poll, and every running
/// player's playhead moves one tick — no player may "lose" time just
/// because the watch was reading the other one (the real wall does not
/// pause the idle twin mid-crossfade).
class _World {
  final players = <_FakePlayer>[];
  void advance() {
    for (final p in players) {
      if (p.running) p._pos += _tick;
    }
  }
}

class _FakePlayer extends AudioPlayer {
  _FakePlayer(
    this.tag,
    this.log,
    this.world, {
    this.duration = const Duration(seconds: 2),
  }) : super(playerId: tag) {
    world.players.add(this);
  }

  final String tag;
  final List<String> log;
  final _World world;
  final Duration? duration;

  double vol = -1;
  bool running = false;
  int plays = 0;
  ReleaseMode? lastReleaseMode;
  Duration _pos = Duration.zero;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
    vol = volume ?? 1;
    _pos = position ?? Duration.zero;
    running = true;
    log.add('$tag play vol=$vol');
  }

  @override
  Future<void> pause() async {
    running = false;
    log.add('$tag pause');
  }

  @override
  Future<void> resume() async {
    running = true;
    log.add('$tag resume');
  }

  @override
  Future<void> stop() async {
    running = false;
    _pos = Duration.zero;
    log.add('$tag stop');
  }

  @override
  Future<void> seek(Duration position) async {
    _pos = position;
    log.add('$tag seek ${position.inMilliseconds}');
  }

  @override
  Future<void> setVolume(double volume) async {
    vol = volume;
    log.add('$tag vol ${volume.toStringAsFixed(3)}');
  }

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {
    lastReleaseMode = releaseMode;
    log.add('$tag mode ${releaseMode.name}');
  }

  @override
  Future<Duration?> getDuration() async => duration;

  @override
  Future<Duration?> getCurrentPosition() async {
    world.advance();
    return _pos;
  }

  @override
  Stream<Duration> get onDurationChanged => duration == null
      ? const Stream<Duration>.empty()
      : Stream.value(duration!);

  @override
  Future<void> dispose() async => log.add('$tag dispose');
}

/// The watch steps the pump with the output's own quantum, so seams land
/// exactly on a tick.
const _tick = Duration(milliseconds: 50);

Future<void> _pump(WidgetTester tester, Duration total) async {
  var left = total;
  while (left > Duration.zero) {
    final step = left < _tick ? left : _tick;
    await tester.pump(step);
    left -= step;
  }
}

void main() {
  const seam = AudioplayersSceneSoundOutput.kSceneLoopSeam;
  const loop = Duration(seconds: 2);

  testWidgets('the handover plays before the lead stops — no silence', (
    tester,
  ) async {
    final log = <String>[];
    final world = _World();
    final players = [
      _FakePlayer('a', log, world),
      _FakePlayer('b', log, world),
    ];
    var made = 0;
    final out = AudioplayersSceneSoundOutput(
      playerFactory: () async => players[made++],
    );

    await out.loop('audio/scene/rain.mp3', 0.5);
    expect(log, contains('a play vol=0.5'));
    expect(log, contains('a mode stop')); // the watch, not ReleaseMode.loop

    // Up to just past the seam (1.4 s in): b joins while a still sounds.
    await _pump(tester, loop - seam + const Duration(milliseconds: 100));
    expect(players[1].plays, 1, reason: 'handover started at the seam');
    expect(players[0].running, isTrue, reason: 'lead still sounding');
    final handover = log.indexOf('b play vol=0.0');
    expect(handover, greaterThanOrEqualTo(0));
    expect(log.indexWhere((c) => c == 'a stop'), -1, reason: 'a has not cut');

    // Past end of file a hands over: b holds full gain before a is put
    // down — sound never stops. (To 2.1 s, just past the swap at 2.05 s.)
    await _pump(tester, const Duration(milliseconds: 600));
    expect(
      log.indexWhere((c) => c == 'a stop'),
      greaterThan(handover),
      reason: 'b is up before a is stopped',
    );
    expect(players[1].vol, greaterThan(0.49));
    expect(players[1].running, isTrue);

    // And the pair keeps alternating: b leads a full file and hands back
    // (its own seam at 2.8 s, a playing again, b stopped at 3.4 s).
    await _pump(tester, const Duration(milliseconds: 1400));
    expect(players[0].plays, 2, reason: 'the loop ping-pongs on');
    expect(players[0].running, isTrue);
    expect(players[1].running, isFalse);

    await out.loop(null, 0);
    expect(log, contains('b stop'));
  });

  testWidgets('a player without a duration rides the native loop', (
    tester,
  ) async {
    final log = <String>[];
    final world = _World();
    final players = [
      _FakePlayer('a', log, world, duration: null),
      _FakePlayer('b', log, world, duration: null),
    ];
    var made = 0;
    final out = AudioplayersSceneSoundOutput(
      playerFactory: () async => players[made++],
    );
    await out.loop('audio/scene/rain.mp3', 0.5);
    expect(log, contains('a mode loop'), reason: 'old behaviour as fallback');
    await _pump(tester, loop * 2 + const Duration(seconds: 1));
    expect(players[0].plays, 1);
    expect(players[1].plays, 0, reason: 'no watch, so no handover attempts');
  });

  testWidgets('hold and resume reach the players that have the sound', (
    tester,
  ) async {
    final log = <String>[];
    final world = _World();
    final players = [
      _FakePlayer('a', log, world),
      _FakePlayer('b', log, world),
    ];
    var made = 0;
    final out = AudioplayersSceneSoundOutput(
      playerFactory: () async => players[made++],
    );
    await out.loop('audio/scene/rain.mp3', 0.5);
    // Stop mid-crossfade: two players are up, and both must hold.
    await _pump(tester, loop - seam + const Duration(milliseconds: 100));
    expect(players[1].running, isTrue);
    await out.pauseLoop();
    expect(players[0].running, isFalse);
    expect(players[1].running, isFalse);
    // While held, the watch must not push volume or hand anything over.
    final before = log.length;
    await _pump(tester, seam * 3);
    expect(log.skip(before).where((c) => c.contains('vol')), isEmpty);
    expect(log.skip(before), isNot(contains('a seek 0')));
    await out.resumeLoop();
    expect(players[0].running, isTrue);
    expect(players[1].running, isTrue);
    await out.loop(null, 0); // frees the watch; no timer may outlive the test
  });
}
