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

/// The move from one place's picture to the next, as a timeline the
/// desktop's `SceneBackdropGame` and the web's SceneBackdrop both play
/// (`web_ui/src/theme/sceneBackdropTransition.ts`): the same frame at the
/// same share of the move, so a move looks the same on both. Which move
/// plays is the story's weather's call ([sceneMoveKindFor]): fog rolls in
/// and clears on the new place, a storm cuts there on a strike, and
/// anything else travels, the old place drifting off under a sweep of
/// light while the new one settles. Nothing here draws; it hands out
/// numbers.
library;

import 'dart:math' as math;

import 'scene_effects_render.dart' show flashShape;

/// The three moves.
enum SceneMoveKind { travel, fogRoll, lightningCut }

/// The weather picks the move: fog rolls, a storm strikes, the rest travel.
SceneMoveKind sceneMoveKindFor(String? condition) => switch (condition) {
  'fog' => SceneMoveKind.fogRoll,
  'storm' => SceneMoveKind.lightningCut,
  _ => SceneMoveKind.travel,
};

/// How long each move runs, in seconds.
double sceneMoveDuration(SceneMoveKind kind) => switch (kind) {
  SceneMoveKind.travel => 1.6,
  SceneMoveKind.fogRoll => 2.0,
  SceneMoveKind.lightningCut => 0.9,
};

/// The share of the move at which the place name shows, so the card can
/// read before the move is over.
const double kSceneMoveTitleIn = 0.25;
const double kSceneMoveTitleOut = 0.8;

/// How long the name shows on a still swap (reduce motion), in seconds.
const double kSceneMoveStillTitle = 1.6;

/// One frame of a move. Alphas are 0 to 1; scales are about 1; `dx` is a
/// share of the stage's width; [sweep] is the light band's position across
/// the stage (0 at the left edge, 1 at the right, negative for none) and
/// [sweepAlpha] its strength; [cover] is how far the fog has closed over
/// the stage; [flash] the strike's strength; [dip] how dark the stage
/// dips; [title] the place name's alpha.
typedef SceneMoveFrame = ({
  double outAlpha,
  double outScale,
  double outDx,
  double inAlpha,
  double inScale,
  double inDx,
  double sweep,
  double sweepAlpha,
  double cover,
  double flash,
  double dip,
  double title,
});

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Where [p] sits between [a] and [b], clamped to 0..1.
double sceneMoveSpan(double p, double a, double b) =>
    _clamp01((p - a) / (b - a));

double easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double easeInCubic(double t) => t * t * t;
double easeInOutCubic(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

/// The name's alpha at [p]: in by [kSceneMoveTitleIn], out from
/// [kSceneMoveTitleOut].
double sceneMoveTitle(double p) {
  if (p < kSceneMoveTitleIn) {
    return easeOutCubic(sceneMoveSpan(p, 0.1, kSceneMoveTitleIn));
  }
  if (p > kSceneMoveTitleOut) {
    return 1 - easeInCubic(sceneMoveSpan(p, kSceneMoveTitleOut, 1));
  }
  return 1;
}

/// The frame of [kind] at [p], the share of the move run so far (0 to 1).
SceneMoveFrame sceneMoveFrame(SceneMoveKind kind, double p) {
  final t = _clamp01(p);
  final title = sceneMoveTitle(t);
  switch (kind) {
    case SceneMoveKind.travel:
      final out = easeInCubic(sceneMoveSpan(t, 0.15, 0.75));
      final inn = easeOutCubic(sceneMoveSpan(t, 0.2, 0.8));
      final s = sceneMoveSpan(t, 0.25, 0.85);
      return (
        outAlpha: 1 - out,
        outScale: 1 + 0.06 * easeInOutCubic(t),
        outDx: -0.02 * easeInOutCubic(t),
        inAlpha: inn,
        inScale: 1.08 - 0.08 * inn,
        inDx: 0.02 * (1 - inn),
        sweep: t < 0.25 || t > 0.85 ? -1 : s,
        sweepAlpha: 0.35 * math.sin(math.pi * s),
        cover: 0,
        flash: 0,
        dip: 0.2 * math.sin(math.pi * t),
        title: title,
      );
    case SceneMoveKind.fogRoll:
      final closing = easeInOutCubic(sceneMoveSpan(t, 0, 0.45));
      final opening = easeInOutCubic(sceneMoveSpan(t, 0.55, 1));
      final cover = t < 0.5 ? closing : 1 - opening;
      final swapped = t >= 0.5;
      final settle = easeOutCubic(sceneMoveSpan(t, 0.5, 1));
      return (
        outAlpha: swapped ? 0 : 1,
        outScale: 1 + 0.03 * closing,
        outDx: 0,
        inAlpha: swapped ? 1 : 0,
        inScale: 1.04 - 0.04 * settle,
        inDx: 0,
        sweep: -1,
        sweepAlpha: 0,
        cover: cover,
        flash: 0,
        dip: 0,
        title: title,
      );
    case SceneMoveKind.lightningCut:
      final swapped = t >= 0.12;
      final flash = t < 0.6 ? flashShape(1 - t / 0.6) : 0.0;
      final after = swapped ? 0.25 * (1 - sceneMoveSpan(t, 0.12, 0.5)) : 1.0;
      final settle = easeOutCubic(sceneMoveSpan(t, 0.12, 1));
      return (
        outAlpha: after,
        outScale: 1,
        outDx: 0,
        inAlpha: swapped ? 1 : 0,
        inScale: 1.03 - 0.03 * settle,
        inDx: 0,
        sweep: -1,
        sweepAlpha: 0,
        cover: 0,
        flash: flash,
        dip: 0,
        title: title,
      );
  }
}

/// A fog bank for the roll: which side it comes from, its height and
/// size as shares of the stage, fixed per place so the same move rolls
/// the same banks on both surfaces.
typedef SceneFogBank = ({bool left, double y, double r});

/// The banks for a place, from its seeded generator: three a side.
List<SceneFogBank> sceneFogBanks(double Function() r) => [
  for (var i = 0; i < 6; i++)
    (left: i.isEven, y: 0.1 + r() * 0.8, r: 0.35 + r() * 0.25),
];

/// A bank's centre x as a share of the stage's width at [cover]: it
/// starts just off its edge and meets the others past the middle.
double sceneFogBankX(SceneFogBank bank, double cover) => bank.left
    ? -bank.r + cover * (0.4 + bank.r)
    : 1 + bank.r - cover * (0.4 + bank.r);

/// The full fog wash under the banks at [cover].
double sceneFogWash(double cover) => 0.9 * cover * cover;
