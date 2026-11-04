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
// swap and keep alternating, and — the bug the first ping-pong shipped
// with — the swap still lands when the lead's reported position zeroes
// at completion, because the cross runs on the watch's clock, not on
// position. A player without a duration still loops natively, and
// hold/resume reach the players that have the sound.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound_output.dart';

/// The pump steps in the watch's quantum and drives every running playhead
/// each step — real time moves whether or not the watch happened to look,
/// which is exactly how a completion can land mid-cross.
const _tick = Duration(milliseconds: 50);

class _World {
  final players = <_FakePlayer>[];

  void tick() {
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
    // macOS zeroes the reported position when the item completes; a
    // fade measured from it must survive being handed the zero.
    if (duration != null && _pos >= duration!) return null;
    return _pos;
  }

  @override
  Stream<Duration> get onDurationChanged => duration == null
      ? const Stream<Duration>.empty()
      : Stream.value(duration!);

  @override
  Future<void> dispose() async => log.add('$tag dispose');
}

/// Advance the world and the pump together, one watch step at a time.
Future<void> _pump(WidgetTester tester, _World world, Duration total) async {
  var left = total;
  while (left > Duration.zero) {
    final step = left < _tick ? left : _tick;
    await tester.pump(step);
    world.tick();
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
    await _pump(tester, world, loop - seam + const Duration(milliseconds: 100));
    expect(players[1].plays, 1, reason: 'handover started at the seam');
    expect(players[0].running, isTrue, reason: 'lead still sounding');
    final handover = log.indexOf('b play vol=0.0');
    expect(handover, greaterThanOrEqualTo(0));
    // (loop()'s own pre-play stop logged before this; look past it.)
    expect(
      log.sublist(handover + 1).where((c) => c == 'a stop'),
      isEmpty,
      reason: 'a has not cut',
    );

    // Through end of file — where a completes and zeroes its reported
    // position mid-cross — and the swap still lands: b holds full gain
    // and only then is a put down. (To 2.1 s.)
    await _pump(tester, world, const Duration(milliseconds: 600));
    expect(
      log.sublist(handover + 1),
      contains('a stop'),
      reason: 'b is up before a is stopped',
    );
    expect(players[1].vol, greaterThan(0.49));
    expect(players[1].running, isTrue);

    // And the pair keeps alternating: b leads a full file (its own seam
    // at 2.8 s), a plays again, and b hands over at 4.0 s.
    await _pump(tester, world, const Duration(milliseconds: 2000));
    expect(players[0].plays, 2, reason: 'the loop ping-pongs on');
    expect(players[0].running, isTrue);
    expect(players[1].running, isFalse);

    await out.loop(null, 0);
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
    await _pump(tester, world, loop * 2 + const Duration(seconds: 1));
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
    await _pump(tester, world, loop - seam + const Duration(milliseconds: 100));
    expect(players[1].running, isTrue);
    await out.pauseLoop();
    expect(players[0].running, isFalse);
    expect(players[1].running, isFalse);
    // While held, the watch must not push volume or hand anything over.
    // (Time passes for the room — world.tick — but the players, being
    // paused, do not advance, and no fades run.)
    final before = log.length;
    for (var i = 0; i < 36; i++) {
      await tester.pump(_tick);
      world.tick();
    }
    expect(log.skip(before).where((c) => c.contains('vol')), isEmpty);
    expect(log.skip(before), isNot(contains('a seek 0')));
    await out.resumeLoop();
    expect(players[0].running, isTrue);
    expect(players[1].running, isTrue);
    await out.loop(null, 0); // frees the watch; no timer may outlive the test
  });
}
