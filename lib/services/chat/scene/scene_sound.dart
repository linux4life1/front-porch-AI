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

/// The Ambient Stage's scene sound as plain numbers and names
/// (`docs/design/ambient-stage.md` §5): which loop a scene plays, which
/// thunder answers a flash, and how loud. The web twin
/// (`web_ui/src/theme/sceneSound.ts`) keeps the same table and the same
/// numbers. The files are synthesised by `tools/gen_scene_sounds.py` and
/// live under `assets/audio/scene/` (CC0; see the LICENSE.md there).
library;

/// A scene's ambience loop, by its file's base name.
enum SceneLoop {
  rain('rain'),
  stormRain('storm_rain'),
  wind('wind'),
  birds('birds'),
  crickets('crickets'),
  fog('fog');

  const SceneLoop(this.file);

  /// The file's base name under `assets/audio/scene/`.
  final String file;
}

/// The bundled format: MP3, the one compressed format every desktop's
/// audioplayers backend and every browser plays.
const String kSceneSoundExt = 'mp3';

/// The asset path audioplayers' `AssetSource` takes (it adds `assets/`).
String sceneSoundAsset(String file) => 'audio/scene/$file.$kSceneSoundExt';

/// The scene wire's `sound`: Appearance → Scene sound and its volume, for
/// the web chat page. Additive; an older PWA ignores it.
Map<String, Object> sceneSoundWire({
  required bool on,
  required double volume,
}) => {'on': on, 'volume': volume.isNaN ? 0.0 : volume.clamp(0.0, 1.0)};

/// The thunder one-shots, by file base name.
const List<String> kSceneThunder = ['thunder_1', 'thunder_2', 'thunder_3'];

/// The parts of the day that hear birds; the rest of the story clock's six
/// (evening, night) hear crickets.
const Set<String> kSceneDayparts = {
  'dawn',
  'morning',
  'late_morning',
  'afternoon',
};
const Set<String> kSceneNightparts = {'evening', 'night'};

/// The loop for a scene's weather [condition] (a `WeatherCondition.name`)
/// at [daypart] (the story clock's period key), or null for none: cloudy
/// and overcast skies are quiet, and so is an unknown key.
SceneLoop? sceneLoopFor({required String condition, required String daypart}) =>
    switch (condition) {
      'rain' => SceneLoop.rain,
      'storm' => SceneLoop.stormRain,
      'snow' => SceneLoop.wind,
      'fog' => SceneLoop.fog,
      'clear' when kSceneDayparts.contains(daypart) => SceneLoop.birds,
      'clear' when kSceneNightparts.contains(daypart) => SceneLoop.crickets,
      _ => null,
    };

/// The flash-to-rumble gap's bounds, in seconds. The stage's sim draws the
/// gap from the scene's seeded generator (`SceneFlash.rumbleDelay`); the
/// sound clamps it here so a bad value never makes thunder wait for ever.
const double kThunderDelayMin = 0.4;
const double kThunderDelayMax = 1.8;

/// The gap to wait after a flash with [rumbleDelay], clamped to the bounds.
Duration thunderDelayFor(double rumbleDelay) {
  final s = rumbleDelay.isNaN
      ? kThunderDelayMin
      : rumbleDelay.clamp(kThunderDelayMin, kThunderDelayMax);
  return Duration(milliseconds: (s * 1000).round());
}

/// Which thunder answers a flash: the gap picks it, so a near strike (a
/// short gap) gets the shortest roll and a far one the longest, and both
/// surfaces pick the same one for the same flash.
String thunderFor(double rumbleDelay) {
  const span = kThunderDelayMax - kThunderDelayMin;
  final t = rumbleDelay.isNaN
      ? 0.0
      : ((rumbleDelay - kThunderDelayMin) / span).clamp(0.0, 1.0);
  final i = (t * kSceneThunder.length).floor();
  return kSceneThunder[i.clamp(0, kSceneThunder.length - 1)];
}

/// While a voice speaks the ambience sits at this share of its volume.
const double kSceneDuck = 0.3;

/// The loop's level for the user's [volume] (0 to 1): ducked while a voice
/// is [speaking], silent while the window is not [visible].
double sceneLoopGain({
  required double volume,
  required bool speaking,
  bool visible = true,
}) {
  if (!visible) return 0;
  final v = volume.isNaN ? 0.0 : volume.clamp(0.0, 1.0);
  return speaking ? v * kSceneDuck : v;
}

/// How long a full 0-to-1 volume ramp takes; a shorter move takes its
/// share of it, so a duck and a crossfade move at the same speed.
const Duration kSceneRampFull = Duration(milliseconds: 600);

/// How often a ramp steps the volume.
const Duration kSceneRampStep = Duration(milliseconds: 40);

/// How long a ramp from [from] to [to] takes.
Duration sceneRampLength(double from, double to) {
  final d = (to - from).abs().clamp(0.0, 1.0);
  return Duration(microseconds: (kSceneRampFull.inMicroseconds * d).round());
}

/// The volume [elapsed] into a ramp from [from] to [to]: linear, held at
/// the two ends, and never outside 0..1.
double sceneRampAt({
  required double from,
  required double to,
  required Duration elapsed,
}) {
  final total = sceneRampLength(from, to);
  if (total == Duration.zero || elapsed >= total) return to.clamp(0.0, 1.0);
  final t = elapsed.isNegative
      ? 0.0
      : elapsed.inMicroseconds / total.inMicroseconds;
  return (from + (to - from) * t).clamp(0.0, 1.0);
}
