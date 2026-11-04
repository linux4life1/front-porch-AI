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
import 'package:path/path.dart' as p;

import 'scene_effects_sim.dart';
import 'scene_sound.dart';
import 'scene_tokens.dart';

/// Where the scene sound goes: one looping player and one for one-shots,
/// the way the story reader plays its ambience and page turn. The app's is
/// `AudioplayersSceneSoundOutput`; tests hand in a fake. Paths are
/// audioplayers asset paths ([sceneSoundAsset]) or a user device file.
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

/// One loop channel of the layered ambience: its own player, its own ramp,
/// pause and failure state. The service holds two — the place identity loop
/// (`base`) and the weather overlay on top of it (`overlay`) — and the
/// shared duck/visibility/thunder state stays on the service.
class _SceneSoundChannel {
  _SceneSoundChannel(this.makeOutput, this.ticker, this.audioRootPath);

  final SceneSoundOutput Function() makeOutput;
  final SceneSoundTicker ticker;
  final String? audioRootPath;

  /// Runs after a swap settles, so the service re-reconciles and the new
  /// loop fades up from silence to the target. The old single-channel
  /// `_swap` ended with `_reconcile()`; without this the loop would load
  /// at volume 0 and stay there.
  void Function()? onSettled;
  SceneSoundOutput? _out;

  SceneSoundSource? current;
  double gain = 0;
  bool paused = false;
  bool switching = false;
  Timer? ramp;
  SceneLoop? failedLoop;
  SceneSoundSource? failed;
  bool disposed = false;

  SceneSoundOutput output() => _out ??= makeOutput();

  void _guard(Future<void> f, String what) {
    unawaited(
      f.catchError((Object e, StackTrace st) {
        debugPrint('SceneSound: could not $what: $e\n$st');
      }),
    );
  }

  void reconcile({
    required SceneSoundSource? want,
    required double target,
    required bool visible,
  }) {
    if (disposed || switching) return;
    final asked = want;
    final ask = asked == failed ? null : asked;
    if (!visible) {
      // A loop nobody wants goes now; one that is wanted waits, held.
      if (ask == null && current != null) {
        unawaited(swap(null));
      } else {
        hold();
      }
      return;
    }
    if (paused && ask == current) {
      paused = false;
      _guard(output().resumeLoop(), 'resume the loop');
    }
    if (ask != current) {
      paused = false;
      if (current == null || gain <= 0) {
        unawaited(swap(ask));
      } else {
        rampTo(0, then: () => unawaited(swap(ask)));
      }
      return;
    }
    if (current != null) rampTo(target);
  }

  void hold() {
    ramp?.cancel();
    ramp = null;
    if (current == null || paused) return;
    paused = true;
    setGain(0);
    _guard(output().pauseLoop(), 'pause the loop');
  }

  /// Loads [next] at silence (or stops the loop for null), then fades up.
  Future<void> swap(SceneSoundSource? next) async {
    ramp?.cancel();
    ramp = null;
    switching = true;
    var started = next;
    try {
      await output().loop(next == null ? null : _pathFor(next), 0);
    } catch (e, st) {
      // Logged once: the failed loop is remembered and not asked for again.
      debugPrint(
        'SceneSound: could not start ${next?.file ?? 'silence'}: '
        '$e\n$st',
      );
      if (next != null) {
        failed = next;
        failedLoop = next.bundledLoop;
        started = null;
      }
    }
    current = started;
    gain = 0;
    paused = false;
    switching = false;
    onSettled?.call();
  }

  /// Moves the loop's volume to [to] at [kSceneRampFull] for a full swing,
  /// one [kSceneRampStep] at a time, then runs [then].
  void rampTo(double to, {void Function()? then}) {
    ramp?.cancel();
    ramp = null;
    final from = gain;
    final length = sceneRampLength(from, to);
    if (length < kSceneRampStep) {
      if (from != to) setGain(to);
      then?.call();
      return;
    }
    var elapsed = Duration.zero;
    ramp = ticker(kSceneRampStep, (timer) {
      elapsed += kSceneRampStep;
      setGain(sceneRampAt(from: from, to: to, elapsed: elapsed));
      if (elapsed >= length) {
        timer.cancel();
        if (identical(ramp, timer)) ramp = null;
        then?.call();
      }
    });
  }

  void setGain(double value) {
    gain = value;
    _guard(output().setLoopVolume(value), 'set the loop volume');
  }

  /// The path the output receives: bundled assets keep their `audio/scene/`
  /// path, URLs keep theirs, and a device file's bare name is resolved
  /// against the live `$rootPath/audio/` at play time.
  String? _pathFor(SceneSoundSource? source) {
    if (source == null) return null;
    if (source.kind == SceneSoundSourceKind.device &&
        audioRootPath != null &&
        audioRootPath!.isNotEmpty) {
      return p.join(audioRootPath!, 'audio', source.file);
    }
    return sceneSoundSourcePath(source);
  }

  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    ramp?.cancel();
    ramp = null;
    final out = _out;
    _out = null;
    if (out == null) return;
    try {
      await out.dispose();
    } catch (e, st) {
      debugPrint('SceneSound: could not release the players: $e\n$st');
    }
  }
}

/// Plays the Ambient Stage's scene sound from the scene the stage paints
/// (`docs/design/ambient-stage.md` §5). Plain Dart: the chat page's
/// `SceneSoundHost` feeds it the scene, the Scene sound setting, whether a
/// voice is speaking, whether the window can be seen, and the stage's
/// flashes; it decides what plays and how loud.
///
/// - The base loop follows the layered resolver's answer on the tokens
///   (`base` = the place's identity loop or the weather-only fallback,
///   `overlay` = the weather loop over a place). A change of loop fades the
///   old one out and the new one in on that channel's player.
/// - Nothing plays with Scene sound off or without a scene (Ambient scene
///   Off, or no weather), and nothing while the window is hidden or
///   minimised; generating does not stop it.
/// - A storm's flash is answered by one of three thunders after the
///   flash's own seeded gap ([thunderDelayFor], [thunderFor]).
/// - While a voice speaks both channels ramp down to [kSceneDuck] of their
///   volume and back up after.
///
/// The player is made the first time something has to play, so a chat with
/// Scene sound off never creates one. The overlay runs on a second
/// [SceneSoundOutput] instance when [overlayOutput] is given; the interface
/// itself is unchanged, so existing fakes keep working.
class SceneSoundService {
  SceneSoundService({
    required SceneSoundOutput Function() output,
    SceneSoundOutput Function()? overlayOutput,
    SceneSoundTimer? timer,
    SceneSoundTicker? ticker,
    String? audioRootPath,
  }) : _timer = timer ?? Timer.new,
       _base = _SceneSoundChannel(
         output,
         ticker ?? Timer.periodic,
         audioRootPath,
       ),
       _overlay = overlayOutput == null
           ? null
           : _SceneSoundChannel(
               overlayOutput,
               ticker ?? Timer.periodic,
               audioRootPath,
             ) {
    // The old single-channel `_swap` ended with `_reconcile()`; each
    // channel now calls back so a fresh loop fades up from silence.
    _base.onSettled = _reconcile;
    _overlay?.onSettled = _reconcile;
  }

  final SceneSoundTimer _timer;
  final _SceneSoundChannel _base;

  final _SceneSoundChannel? _overlay;

  SceneTokens? _tokens;
  bool _enabled = false;
  double _volume = 0.5;
  bool _speaking = false;
  bool _visible = true;
  bool _disposed = false;
  final Set<Timer> _thunders = {};

  /// The base loop that would not start, if one would not; it is not tried
  /// again (each try would fail and log the same way), so the chat stays
  /// quiet for that sky until the next chat.
  SceneLoop? get failed => _base.failedLoop ?? _overlay?.failedLoop;

  /// The base loop the player holds now, or null for none.
  SceneLoop? get playing => _base.current?.bundledLoop;

  /// The base loop's volume as last sent to the player.
  double get gain => _base.gain;

  /// Whether the base loop is held for a hidden window.
  bool get paused => _base.paused;

  /// The base loop the scene and the settings ask for now.
  SceneLoop? get wanted {
    final t = _tokens;
    if (!_enabled || t == null) return null;
    final src = t.base;
    if (src != null) return src.bundledLoop;
    return sceneLoopFor(condition: t.condition, daypart: t.daypart);
  }

  /// The volume the loops are heading for.
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

  /// Whether a voice is speaking now; the loops duck under it.
  set speaking(bool value) {
    if (_speaking == value) return;
    _speaking = value;
    _reconcile();
  }

  /// Whether the window can be seen; hidden or minimised holds the loops.
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
        _base.output().oneShot(
          sceneSoundAsset(thunderFor(flash.rumbleDelay)),
          volume,
        ),
        'play thunder',
      );
    });
    _thunders.add(t);
  }

  /// Stops everything and lets the players go.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelThunder();
    await _base.dispose();
    await _overlay?.dispose();
  }

  bool get _thunderAllowed =>
      !_disposed && _enabled && _visible && _tokens?.condition == 'storm';

  void _cancelThunder() {
    for (final t in _thunders) {
      t.cancel();
    }
    _thunders.clear();
  }

  void _guard(Future<void> f, String what) {
    unawaited(
      f.catchError((Object e, StackTrace st) {
        debugPrint('SceneSound: could not $what: $e\n$st');
      }),
    );
  }

  SceneSoundSource? get _wantedBase {
    final t = _tokens;
    if (!_enabled || t == null) return null;
    final src = t.base;
    if (src != null) return src;
    final fallback = sceneLoopFor(condition: t.condition, daypart: t.daypart);
    return fallback == null ? null : SceneSoundSource.bundled(fallback.file);
  }

  SceneSoundSource? get _wantedOverlay {
    final t = _tokens;
    if (!_enabled || t == null || _overlay == null) return null;
    return t.overlay;
  }

  void _reconcile() {
    if (_disposed) return;
    _base.reconcile(want: _wantedBase, target: target, visible: _visible);
    _overlay?.reconcile(
      want: _wantedOverlay,
      target: target,
      visible: _visible,
    );
  }
}
