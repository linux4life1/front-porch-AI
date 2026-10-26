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

import 'package:flutter/foundation.dart' show debugPrint;

import 'scene_effects_sim.dart';
import 'scene_sound.dart';
import 'scene_tokens.dart';

/// Where the scene sound goes: one looping player and one for one-shots,
/// the way the story reader plays its ambience and page turn. The app's is
/// `AudioplayersSceneSoundOutput`; tests hand in a fake. Paths are
/// audioplayers asset paths ([sceneSoundAsset]).
abstract interface class SceneSoundOutput {
  /// Starts [asset] looping from its start at [volume], replacing whatever
  /// loop was playing; null stops the loop.
  Future<void> loop(String? asset, double volume);

  /// Sets the loop's volume, 0 to 1.
  Future<void> setLoopVolume(double volume);

  /// Holds the loop where it is, and carries on from there.
  Future<void> pauseLoop();
  Future<void> resumeLoop();

  /// Plays [asset] once at [volume] on the one-shot player.
  Future<void> oneShot(String asset, double volume);

  Future<void> dispose();
}

/// Makes a one-off timer; [Timer.new] in the app, a hand-cranked one in tests.
typedef SceneSoundTimer = Timer Function(Duration after, void Function() run);

/// Makes a repeating timer; [Timer.periodic] in the app.
typedef SceneSoundTicker =
    Timer Function(Duration every, void Function(Timer timer) tick);

/// Plays the Ambient Stage's scene sound from the scene the stage paints
/// (`docs/design/ambient-stage.md` §5). Plain Dart: the chat page's
/// `SceneSoundHost` feeds it the scene, the Scene sound setting, whether a
/// voice is speaking, whether the window can be seen, and the stage's
/// flashes; it decides what plays and how loud.
///
/// - The loop follows (condition, daypart) through [sceneLoopFor]; a change
///   of loop fades the old one out and the new one in on the one player.
/// - Nothing plays with Scene sound off or without a scene (Ambient scene
///   Off, or no weather), and nothing while the window is hidden or
///   minimised; generating does not stop it.
/// - A storm's flash is answered by one of three thunders after the
///   flash's own seeded gap ([thunderDelayFor], [thunderFor]).
/// - While a voice speaks the loop ramps down to [kSceneDuck] of its
///   volume and back up after.
///
/// The player is made the first time something has to play, so a chat with
/// Scene sound off never creates one.
class SceneSoundService {
  SceneSoundService({
    required SceneSoundOutput Function() output,
    SceneSoundTimer? timer,
    SceneSoundTicker? ticker,
  }) : _makeOutput = output,
       _timer = timer ?? Timer.new,
       _ticker = ticker ?? Timer.periodic;

  final SceneSoundOutput Function() _makeOutput;
  final SceneSoundTimer _timer;
  final SceneSoundTicker _ticker;
  SceneSoundOutput? _out;

  SceneTokens? _tokens;
  bool _enabled = false;
  double _volume = 0.5;
  bool _speaking = false;
  bool _visible = true;
  bool _disposed = false;

  SceneLoop? _current;
  double _gain = 0;
  bool _paused = false;
  bool _switching = false;
  Timer? _ramp;
  final Set<Timer> _thunders = {};

  SceneLoop? _failed;
  Object? _lastError;

  /// The loop that would not start, if one would not; it is not tried
  /// again (each try would fail and log the same way), so the chat stays
  /// quiet for that sky until the next chat.
  SceneLoop? get failed => _failed;

  /// Why [failed] would not start, for the host to show or log.
  Object? get lastError => _lastError;

  /// The loop the player holds now, or null for none.
  SceneLoop? get playing => _current;

  /// The loop's volume as last sent to the player.
  double get gain => _gain;

  /// Whether the loop is held for a hidden window.
  bool get paused => _paused;

  /// The loop the scene and the settings ask for now.
  SceneLoop? get wanted {
    final t = _tokens;
    if (!_enabled || t == null) return null;
    return sceneLoopFor(condition: t.condition, daypart: t.daypart);
  }

  /// The volume the loop is heading for.
  double get target =>
      sceneLoopGain(volume: _volume, speaking: _speaking, visible: _visible);

  /// The scene ([tokens], null for none) and the Scene sound setting.
  void update({
    required SceneTokens? tokens,
    required bool enabled,
    required double volume,
  }) {
    _tokens = tokens;
    _enabled = enabled;
    _volume = volume;
    if (!_thunderAllowed) _cancelThunder();
    _reconcile();
  }

  /// Whether a voice is speaking now; the loop ducks under it.
  set speaking(bool value) {
    if (_speaking == value) return;
    _speaking = value;
    _reconcile();
  }

  /// Whether the window can be seen; hidden or minimised holds the loop.
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    if (!value) _cancelThunder();
    _reconcile();
  }

  /// A storm flash on the stage: thunder follows after its gap.
  void onFlash(SceneFlash flash) {
    if (!_thunderAllowed) return;
    late final Timer t;
    t = _timer(thunderDelayFor(flash.rumbleDelay), () {
      _thunders.remove(t);
      if (!_thunderAllowed) return;
      final volume = sceneLoopGain(volume: _volume, speaking: _speaking);
      _guard(
        _output().oneShot(
          sceneSoundAsset(thunderFor(flash.rumbleDelay)),
          volume,
        ),
        'play thunder',
      );
    });
    _thunders.add(t);
  }

  /// Stops everything and lets the player go.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ramp?.cancel();
    _ramp = null;
    _cancelThunder();
    final out = _out;
    _out = null;
    if (out == null) return;
    try {
      await out.dispose();
    } catch (e, st) {
      debugPrint('SceneSound: could not release the players: $e\n$st');
    }
  }

  bool get _thunderAllowed =>
      !_disposed && _enabled && _visible && _tokens?.condition == 'storm';

  void _cancelThunder() {
    for (final t in _thunders) {
      t.cancel();
    }
    _thunders.clear();
  }

  SceneSoundOutput _output() => _out ??= _makeOutput();

  void _reconcile() {
    if (_disposed || _switching) return;
    final asked = wanted;
    final want = asked == _failed ? null : asked;
    if (!_visible) {
      // A loop nobody wants goes now; one that is wanted waits, held.
      if (want == null && _current != null) {
        unawaited(_swap(null));
      } else {
        _hold();
      }
      return;
    }
    if (_paused && want == _current) {
      _paused = false;
      _guard(_output().resumeLoop(), 'resume the loop');
    }
    if (want != _current) {
      _paused = false;
      if (_current == null || _gain <= 0) {
        unawaited(_swap(want));
      } else {
        _rampTo(0, then: () => unawaited(_swap(want)));
      }
      return;
    }
    if (_current != null) _rampTo(target);
  }

  void _hold() {
    _ramp?.cancel();
    _ramp = null;
    if (_current == null || _paused) return;
    _paused = true;
    _setGain(0);
    _guard(_output().pauseLoop(), 'pause the loop');
  }

  /// Loads [next] at silence (or stops the loop for null), then fades up.
  Future<void> _swap(SceneLoop? next) async {
    _ramp?.cancel();
    _ramp = null;
    _switching = true;
    var started = next;
    try {
      await _output().loop(next == null ? null : sceneSoundAsset(next.file), 0);
    } catch (e, st) {
      // Logged once: the failed loop is remembered and not asked for again.
      debugPrint(
        'SceneSound: could not start ${next?.file ?? 'silence'}: '
        '$e\n$st',
      );
      if (next != null) {
        _failed = next;
        _lastError = e;
        started = null;
      }
    }
    _current = started;
    _gain = 0;
    _paused = false;
    _switching = false;
    _reconcile();
  }

  /// Moves the loop's volume to [to] at [kSceneRampFull] for a full swing,
  /// one [kSceneRampStep] at a time, then runs [then].
  void _rampTo(double to, {void Function()? then}) {
    _ramp?.cancel();
    _ramp = null;
    final from = _gain;
    final length = sceneRampLength(from, to);
    if (length < kSceneRampStep) {
      if (from != to) _setGain(to);
      then?.call();
      return;
    }
    var elapsed = Duration.zero;
    _ramp = _ticker(kSceneRampStep, (timer) {
      elapsed += kSceneRampStep;
      _setGain(sceneRampAt(from: from, to: to, elapsed: elapsed));
      if (elapsed >= length) {
        timer.cancel();
        if (identical(_ramp, timer)) _ramp = null;
        then?.call();
      }
    });
  }

  void _setGain(double value) {
    _gain = value;
    _guard(_output().setLoopVolume(value), 'set the loop volume');
  }

  void _guard(Future<void> f, String what) {
    unawaited(
      f.catchError((Object e, StackTrace st) {
        debugPrint('SceneSound: could not $what: $e\n$st');
      }),
    );
  }
}
