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

// The Ambient Stage's scene sound (docs/design/ambient-stage.md §5, PR 3):
// the loop for every condition and part of day, nothing with the setting
// off or without a scene, thunder after a storm's flash within the gap's
// bounds and never without a storm, the duck under a voice and back, the
// crossfade's ramp held to 0..1, and the hidden-window hold. The players
// are a fake and the timers are cranked by hand, so nothing here touches
// audioplayers or the clock.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound_service.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

const _dayparts = [
  'dawn',
  'morning',
  'late_morning',
  'afternoon',
  'evening',
  'night',
];

SceneTokens _scene(WeatherCondition c, {String daypart = 'afternoon'}) =>
    SceneSim.resolve(
      daypart: daypart,
      condition: c,
      temp: TempBand.mild,
      dark: true,
      seed: 7,
    );

/// What the service asked the players to do, in order.
class _FakeOutput implements SceneSoundOutput {
  final List<String> calls = [];
  final List<double> volumes = [];
  final List<(String, double)> shots = [];
  String? looping;
  bool disposed = false;

  @override
  Future<void> loop(String? asset, double volume) async {
    looping = asset;
    calls.add('loop ${asset ?? '-'}');
    volumes.add(volume);
  }

  @override
  Future<void> setLoopVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> pauseLoop() async => calls.add('pause');

  @override
  Future<void> resumeLoop() async => calls.add('resume');

  @override
  Future<void> oneShot(String asset, double volume) async {
    calls.add('shot $asset');
    shots.add((asset, volume));
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// Timers that run only when the test says so.
class _Clock {
  final List<_Manual> pending = [];

  Timer once(Duration after, void Function() run) {
    final t = _Manual(after, (_) => run(), periodic: false, clock: this);
    pending.add(t);
    return t;
  }

  Timer every(Duration step, void Function(Timer) tick) {
    final t = _Manual(step, tick, periodic: true, clock: this);
    pending.add(t);
    return t;
  }

  /// Runs every live timer's due work for [elapsed], one ramp step at a time.
  Future<void> advance(Duration elapsed) async {
    var left = elapsed;
    while (left > Duration.zero) {
      final step = left < kSceneRampStep ? left : kSceneRampStep;
      left -= step;
      for (final t in [...pending]) {
        t.elapse(step);
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<_Manual> get oneShots => [
    for (final t in pending)
      if (!t.periodic && t.isActive) t,
  ];
}

class _Manual implements Timer {
  _Manual(this.every, this.run, {required this.periodic, required this.clock});
  final Duration every;
  final void Function(Timer) run;
  final bool periodic;
  final _Clock clock;
  Duration _since = Duration.zero;
  bool _active = true;
  int _ticks = 0;

  void elapse(Duration d) {
    if (!_active) return;
    _since += d;
    while (_active && _since >= every) {
      _since -= every;
      _ticks++;
      if (!periodic) {
        _active = false;
        clock.pending.remove(this);
      }
      run(this);
    }
  }

  @override
  void cancel() {
    _active = false;
    clock.pending.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}

({SceneSoundService sound, _FakeOutput out, _Clock clock}) _service() {
  final out = _FakeOutput();
  final clock = _Clock();
  final sound = SceneSoundService(
    output: () => out,
    timer: clock.once,
    ticker: clock.every,
  );
  return (sound: sound, out: out, clock: clock);
}

Future<void> _settle(_Clock clock) => clock.advance(const Duration(seconds: 2));

void main() {
  group('the loop for a scene', () {
    test('every condition at every part of the day', () {
      final expected = <String, SceneLoop? Function(String daypart)>{
        'clear': (d) => const {'evening', 'night'}.contains(d)
            ? SceneLoop.crickets
            : SceneLoop.birds,
        'cloudy': (_) => null,
        'overcast': (_) => null,
        'fog': (_) => SceneLoop.fog,
        'rain': (_) => SceneLoop.rain,
        'storm': (_) => SceneLoop.stormRain,
        'snow': (_) => SceneLoop.wind,
      };
      expect(
        expected.keys.toSet(),
        WeatherCondition.values.map((c) => c.name).toSet(),
        reason: 'a new condition needs a row here and in sceneLoopFor',
      );
      for (final c in WeatherCondition.values) {
        for (final d in _dayparts) {
          expect(
            sceneLoopFor(condition: c.name, daypart: d),
            expected[c.name]!(d),
            reason: '${c.name} at $d',
          );
        }
      }
      expect(sceneLoopFor(condition: 'clear', daypart: 'teatime'), isNull);
      expect(sceneLoopFor(condition: 'hail', daypart: 'night'), isNull);
    });

    test('every loop and thunder has its file, small, with a licence', () {
      final dir = Directory('assets/audio/scene');
      final names = [
        for (final l in SceneLoop.values) l.file,
        ...kSceneThunder,
      ];
      var total = 0;
      for (final n in names) {
        final f = File('${dir.path}/$n.$kSceneSoundExt');
        expect(f.existsSync(), isTrue, reason: f.path);
        total += f.lengthSync();
      }
      expect(total, lessThan(600 * 1024), reason: 'keep the set small');
      final licence = File('${dir.path}/LICENSE.md').readAsStringSync();
      expect(licence, contains('CC0 1.0'));
      expect(licence, contains('tools/gen_scene_sounds.py'));
      expect(sceneSoundAsset('rain'), 'audio/scene/rain.mp3');
    });

    test('the web wire carries the setting, volume held to 0..1', () {
      expect(sceneSoundWire(on: true, volume: 0.4), {
        'on': true,
        'volume': 0.4,
      });
      expect(sceneSoundWire(on: false, volume: 3)['volume'], 1.0);
      expect(sceneSoundWire(on: false, volume: double.nan)['volume'], 0.0);
    });

    test('the service plays the scene\'s loop and changes with it', () async {
      final s = _service();
      s.sound.update(
        tokens: _scene(WeatherCondition.clear, daypart: 'morning'),
        enabled: true,
        volume: 0.8,
      );
      await _settle(s.clock);
      expect(s.out.looping, 'audio/scene/birds.mp3');
      expect(s.sound.gain, closeTo(0.8, 1e-9));

      s.sound.update(
        tokens: _scene(WeatherCondition.clear, daypart: 'night'),
        enabled: true,
        volume: 0.8,
      );
      await _settle(s.clock);
      expect(s.out.looping, 'audio/scene/crickets.mp3');
      expect(s.sound.playing, SceneLoop.crickets);
    });

    test('off, no scene, or a quiet sky plays nothing', () async {
      final off = _service();
      off.sound.update(
        tokens: _scene(WeatherCondition.rain),
        enabled: false,
        volume: 1,
      );
      await _settle(off.clock);
      expect(off.out.calls, isEmpty, reason: 'no player is even made');

      final none = _service();
      none.sound.update(tokens: null, enabled: true, volume: 1);
      await _settle(none.clock);
      expect(none.out.calls, isEmpty);

      final cloudy = _service();
      cloudy.sound.update(
        tokens: _scene(WeatherCondition.overcast),
        enabled: true,
        volume: 1,
      );
      await _settle(cloudy.clock);
      expect(cloudy.out.calls, isEmpty);

      // Turning it off, or the scene going, fades the loop out and stops it.
      final s = _service();
      s.sound.update(
        tokens: _scene(WeatherCondition.rain),
        enabled: true,
        volume: 1,
      );
      await _settle(s.clock);
      s.sound.update(
        tokens: _scene(WeatherCondition.rain),
        enabled: false,
        volume: 1,
      );
      await _settle(s.clock);
      expect(s.out.calls.last, 'loop -');
      expect(s.sound.playing, isNull);
      s.sound.update(
        tokens: _scene(WeatherCondition.snow),
        enabled: true,
        volume: 1,
      );
      await _settle(s.clock);
      expect(s.out.looping, 'audio/scene/wind.mp3');
      s.sound.update(tokens: null, enabled: true, volume: 1);
      await _settle(s.clock);
      expect(s.out.looping, isNull);
    });
  });

  group('crossfade', () {
    test('ramp values stay in 0..1 and reach their end on time', () {
      expect(sceneRampLength(0, 1), kSceneRampFull);
      expect(sceneRampLength(0.5, 0.2), kSceneRampFull * 0.3);
      expect(sceneRampLength(0.4, 0.4), Duration.zero);
      for (final (from, to) in [(0.0, 1.0), (1.0, 0.0), (0.3, 0.9)]) {
        var last = from;
        for (var ms = 0; ms <= 700; ms += 20) {
          final v = sceneRampAt(
            from: from,
            to: to,
            elapsed: Duration(milliseconds: ms),
          );
          expect(v, inInclusiveRange(0.0, 1.0));
          // Monotonic toward the end.
          expect(to >= from ? v >= last - 1e-12 : v <= last + 1e-12, isTrue);
          last = v;
        }
        expect(last, to);
      }
      expect(
        sceneRampAt(from: 2, to: -1, elapsed: Duration.zero),
        inInclusiveRange(0.0, 1.0),
      );
      expect(sceneRampAt(from: 0, to: 1, elapsed: -kSceneRampStep), 0);
    });

    test('a change of loop fades out, swaps at silence, fades in', () async {
      final s = _service();
      s.sound.update(
        tokens: _scene(WeatherCondition.rain),
        enabled: true,
        volume: 0.6,
      );
      await _settle(s.clock);
      s.out.volumes.clear();
      s.out.calls.clear();

      s.sound.update(
        tokens: _scene(WeatherCondition.storm),
        enabled: true,
        volume: 0.6,
      );
      // Mid-fade: still the rain, quieter.
      await s.clock.advance(const Duration(milliseconds: 160));
      expect(s.out.looping, 'audio/scene/rain.mp3');
      expect(s.sound.gain, inExclusiveRange(0.0, 0.6));
      await _settle(s.clock);
      expect(s.out.calls, ['loop audio/scene/storm_rain.mp3']);
      final swap = s.out.volumes.indexOf(0);
      expect(swap, greaterThan(0), reason: 'faded down before the swap');
      final down = s.out.volumes.sublist(0, swap + 1);
      final up = s.out.volumes.sublist(swap + 1);
      for (var i = 1; i < down.length; i++) {
        expect(down[i], lessThanOrEqualTo(down[i - 1]));
      }
      for (var i = 1; i < up.length; i++) {
        expect(up[i], greaterThanOrEqualTo(up[i - 1]));
      }
      expect(up.last, closeTo(0.6, 1e-9));
      expect(s.out.volumes.every((v) => v >= 0 && v <= 1), isTrue);
    });
  });

  group('thunder', () {
    test('the gap is held to 0.4..1.8 s and picks one of three', () {
      expect(thunderDelayFor(0.4), const Duration(milliseconds: 400));
      expect(thunderDelayFor(1.8), const Duration(milliseconds: 1800));
      expect(thunderDelayFor(0), const Duration(milliseconds: 400));
      expect(thunderDelayFor(9), const Duration(milliseconds: 1800));
      expect(thunderDelayFor(double.nan), const Duration(milliseconds: 400));
      expect(thunderFor(0.4), 'thunder_1');
      expect(thunderFor(1.1), 'thunder_2');
      expect(thunderFor(1.7), 'thunder_3');
      expect(thunderFor(1.8), 'thunder_3');
      final picked = {for (var d = 0.4; d <= 1.8; d += 0.01) thunderFor(d)};
      expect(picked, kSceneThunder.toSet());
    });

    test('a storm flash is answered after its gap at the volume', () async {
      final s = _service();
      s.sound.update(
        tokens: _scene(WeatherCondition.storm),
        enabled: true,
        volume: 0.5,
      );
      await _settle(s.clock);
      s.sound.onFlash(const SceneFlash(at: 3, rumbleDelay: 1.2));
      expect(s.clock.oneShots, hasLength(1));
      expect(s.clock.oneShots.single.every, const Duration(milliseconds: 1200));
      await s.clock.advance(const Duration(milliseconds: 1160));
      expect(s.out.shots, isEmpty, reason: 'not before the gap');
      await s.clock.advance(const Duration(milliseconds: 80));
      expect(s.out.shots, [('audio/scene/thunder_2.mp3', 0.5)]);

      // Under a voice the thunder is ducked like the loop.
      s.sound.speaking = true;
      s.sound.onFlash(const SceneFlash(at: 9, rumbleDelay: 0.4));
      await _settle(s.clock);
      expect(s.out.shots.last, ('audio/scene/thunder_1.mp3', 0.5 * kSceneDuck));
    });

    test('no thunder without a storm, with sound off, or hidden', () async {
      final rain = _service();
      rain.sound.update(
        tokens: _scene(WeatherCondition.rain),
        enabled: true,
        volume: 1,
      );
      rain.sound.onFlash(const SceneFlash(at: 1, rumbleDelay: 0.5));
      await _settle(rain.clock);
      expect(rain.out.shots, isEmpty);

      final off = _service();
      off.sound.update(
        tokens: _scene(WeatherCondition.storm),
        enabled: false,
        volume: 1,
      );
      off.sound.onFlash(const SceneFlash(at: 1, rumbleDelay: 0.5));
      await _settle(off.clock);
      expect(off.out.shots, isEmpty);

      // A rumble on its way is dropped when the window goes.
      final hidden = _service();
      hidden.sound.update(
        tokens: _scene(WeatherCondition.storm),
        enabled: true,
        volume: 1,
      );
      hidden.sound.onFlash(const SceneFlash(at: 1, rumbleDelay: 1.0));
      hidden.sound.visible = false;
      await _settle(hidden.clock);
      expect(hidden.out.shots, isEmpty);

      // And on dispose.
      final gone = _service();
      gone.sound.update(
        tokens: _scene(WeatherCondition.storm),
        enabled: true,
        volume: 1,
      );
      gone.sound.onFlash(const SceneFlash(at: 1, rumbleDelay: 1.0));
      await gone.sound.dispose();
      await _settle(gone.clock);
      expect(gone.out.shots, isEmpty);
      expect(gone.out.disposed, isTrue);
    });
  });

  group('ducking', () {
    test('a voice brings the loop to 30% and it comes back after', () async {
      expect(sceneLoopGain(volume: 0.8, speaking: true), closeTo(0.24, 1e-9));
      expect(sceneLoopGain(volume: 0.8, speaking: false), 0.8);
      expect(sceneLoopGain(volume: 0.8, speaking: false, visible: false), 0);
      expect(sceneLoopGain(volume: 4, speaking: false), 1);

      final s = _service();
      s.sound.update(
        tokens: _scene(WeatherCondition.fog),
        enabled: true,
        volume: 0.8,
      );
      await _settle(s.clock);
      s.sound.speaking = true;
      await s.clock.advance(const Duration(milliseconds: 120));
      expect(s.sound.gain, inExclusiveRange(0.24, 0.8), reason: 'a ramp');
      await _settle(s.clock);
      expect(s.sound.gain, closeTo(0.8 * kSceneDuck, 1e-9));
      expect(s.out.calls, ['loop audio/scene/fog.mp3'], reason: 'no swap');

      s.sound.speaking = false;
      await _settle(s.clock);
      expect(s.sound.gain, closeTo(0.8, 1e-9));
    });

    test('a hidden window holds the loop; showing it fades back', () async {
      final s = _service();
      s.sound.update(
        tokens: _scene(WeatherCondition.rain),
        enabled: true,
        volume: 0.7,
      );
      await _settle(s.clock);
      s.sound.visible = false;
      expect(s.sound.paused, isTrue);
      expect(s.sound.gain, 0);
      expect(s.out.calls.last, 'pause');
      // Generating is not a reason to stop; only the window is.
      s.sound.visible = true;
      expect(s.out.calls.last, 'resume');
      await _settle(s.clock);
      expect(s.sound.gain, closeTo(0.7, 1e-9));
      expect(s.sound.playing, SceneLoop.rain);
    });
  });

  test('a loop that will not start is not tried again', () async {
    final out = _ThrowingOutput();
    final clock = _Clock();
    final sound = SceneSoundService(
      output: () => out,
      timer: clock.once,
      ticker: clock.every,
    );
    sound.update(
      tokens: _scene(WeatherCondition.rain),
      enabled: true,
      volume: 0.5,
    );
    await _settle(clock);
    expect(out.loops, 1);
    expect(sound.failed, SceneLoop.rain);
    expect(sound.playing, isNull);
    // More updates, a voice, a ramp's worth of time: no second try.
    sound.update(
      tokens: _scene(WeatherCondition.rain),
      enabled: true,
      volume: 0.9,
    );
    sound.speaking = true;
    await _settle(clock);
    expect(out.loops, 1);
    expect(out.volumes, isEmpty);
    await sound.dispose();
  });
}

/// A player whose loop never starts.
class _ThrowingOutput extends _FakeOutput {
  int loops = 0;

  @override
  Future<void> loop(String? asset, double volume) async {
    loops++;
    throw StateError('no decoder');
  }
}
