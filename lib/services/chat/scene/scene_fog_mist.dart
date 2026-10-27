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

/// How the stage draws fog: two layers of mist, a far one and a near one,
/// each a seeded texture of wispy value noise thickest toward the ground,
/// drifting sideways at its own speed and breathing slowly. Soft blobs
/// over a flat haze read as a grey background; mist that visibly streams
/// past is what reads as fog. Pure arithmetic over the scene's seed and
/// the sim's clock, so the sim and its shared vectors are untouched, and
/// the web (`web_ui/src/theme/sceneFogMist.ts`) builds the same texture
/// number for number.
///
/// The layers' shares of the fog paint sum to 0.5, the fog bound the
/// readability floor test composites, so even where both peak on the same
/// pixel the fog stays inside it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'scene_rng.dart';

/// The mist texture's size in pixels. It is drawn stretched over
/// [kSceneMistSpan] stage widths and the stage's height, and tiles
/// sideways, so it can stream forever.
const int kSceneMistWidth = 192;
const int kSceneMistHeight = 96;

/// Per layer, far then near.
const int kSceneMistLayers = 2;

/// Noise cells across one tile and down the stage at the coarsest octave:
/// the far layer's wisps are broad, the near one's finer.
const List<int> kSceneMistCellsX = [4, 8];
const List<int> kSceneMistCellsY = [4, 7];

/// Each layer's share of the fog paint at full density and full breath.
const List<double> kSceneMistShare = [0.2, 0.3];

/// A tile's width, in stage widths.
const double kSceneMistSpan = 1.5;

/// How fast each layer streams right, in stage widths a second.
const List<double> kSceneMistSpeed = [0.008, 0.02];

/// How much each layer thickens from the top of the stage to the ground.
const List<double> kSceneMistGround = [0.18, 0.3];

/// The noise value where each layer's mist starts and where it is full:
/// below the first is clear air, so the mist comes in wisps.
const List<double> kSceneMistFrom = [0.42, 0.5];
const List<double> kSceneMistFull = [0.78, 0.85];

const int _octaves = 5;
const int _lattice = 256;

/// Layer [layer]'s density, 0 to 1, for the scene [seed]: row by row,
/// [kSceneMistWidth] by [kSceneMistHeight]. Built once per scatter.
Float64List sceneMist(int seed, int layer) {
  final r = Mulberry32((seed ^ (0x9E3779B9 * (layer + 1))) & 0xFFFFFFFF);
  final lat = Float64List(_lattice * _lattice);
  for (var i = 0; i < lat.length; i++) {
    lat[i] = r.next();
  }
  final cellsX = kSceneMistCellsX[layer];
  final cellsY = kSceneMistCellsY[layer];
  final from = kSceneMistFrom[layer];
  final span = kSceneMistFull[layer] - from;
  final ground = kSceneMistGround[layer];
  final out = Float64List(kSceneMistWidth * kSceneMistHeight);
  for (var y = 0; y < kSceneMistHeight; y++) {
    final v = (y + 0.5) / kSceneMistHeight;
    final lift = ground * v * v;
    for (var x = 0; x < kSceneMistWidth; x++) {
      final u = (x + 0.5) / kSceneMistWidth;
      var sum = 0.0;
      var amp = 0.5;
      var norm = 0.0;
      var period = cellsX;
      for (var o = 0; o < _octaves; o++) {
        sum += amp * _noise(lat, u * period, v * cellsY * (1 << o), period);
        norm += amp;
        amp *= 0.5;
        period *= 2;
      }
      final t = ((sum / norm + lift - from) / span).clamp(0.0, 1.0);
      out[y * kSceneMistWidth + x] = t * t * (3 - 2 * t);
    }
  }
  return out;
}

/// Smoothed value noise at ([x], [y]) on the lattice, wrapping sideways
/// every [period] cells so a tile meets itself.
double _noise(Float64List lat, double x, double y, int period) {
  final xi = x.floor();
  final yi = y.floor();
  final fx = x - xi;
  final fy = y - yi;
  final i0 = xi % period;
  final i1 = (xi + 1) % period;
  final j0 = (yi % _lattice) * _lattice;
  final j1 = ((yi + 1) % _lattice) * _lattice;
  final u = fx * fx * (3 - 2 * fx);
  final w = fy * fy * (3 - 2 * fy);
  final top = lat[j0 + i0] + (lat[j0 + i1] - lat[j0 + i0]) * u;
  final bottom = lat[j1 + i0] + (lat[j1 + i1] - lat[j1 + i0]) * u;
  return top + (bottom - top) * w;
}

/// How much of layer [layer]'s share shows at [time]: each layer thickens
/// and thins on its own slow phase between 0.6 and 1.
double mistBreath(int layer, double time) =>
    0.8 + 0.2 * math.sin(time * 0.21 + layer * 2.1);

/// How far layer [layer]'s tiles have streamed right at [time] on a stage
/// [width] wide, in pixels, within one tile: draw a tile there and one a
/// tile's width to its left.
double mistShift(int layer, double time, double width) =>
    (time * kSceneMistSpeed[layer] * width) % (width * kSceneMistSpan);
