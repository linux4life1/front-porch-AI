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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/scene_palette.dart';
import 'package:front_porch_ai/ui/theme/web_theme_tokens.dart';
import '../weather_engine.dart';

/// One translucent layer the stage paints, in paint order.
@immutable
class SceneLayer {
  const SceneLayer(this.color, this.alpha);
  final Color color;
  final double alpha;

  /// The layer as one translucent colour.
  Color get paint => color.withValues(alpha: alpha);

  @override
  bool operator ==(Object other) =>
      other is SceneLayer && other.color == color && other.alpha == alpha;

  @override
  int get hashCode => Object.hash(color, alpha);
}

/// The resolved scene for one chat at one moment: what the desktop stage
/// paints and exactly what the web paints from the same wire. Value type.
@immutable
class SceneTokens {
  const SceneTokens({
    required this.daypart,
    required this.condition,
    required this.temp,
    required this.layers,
    required this.haze,
  });

  /// The story clock's period key, the condition and band names.
  final String daypart;
  final String condition;
  final String temp;

  /// Shade, part of day, condition, temperature: in paint order, with the
  /// zero-alpha ones already dropped.
  final List<SceneLayer> layers;

  /// Haze strength, 0 to 1; the stage draws it as a radial wash of
  /// [kSceneHaze] thin at the centre and thicker at the edges.
  final double haze;

  /// Every layer composited over [ground], for contrast checks and tests.
  Color compositeOver(Color ground) {
    var c = ground;
    for (final l in layers) {
      c = Color.alphaBlend(l.paint, c);
    }
    if (haze > 0) {
      c = Color.alphaBlend(kSceneHaze.withValues(alpha: hazeEdgeAlpha), c);
    }
    return c;
  }

  /// The haze alpha at the centre and at the edge of the stage.
  double get hazeCentreAlpha => haze * 0.08;
  double get hazeEdgeAlpha => haze * 0.25;

  /// The wire the web paints from: CSS colour strings only, so the PWA
  /// never works out a colour. Additive; an older PWA ignores it.
  Map<String, Object> toWire() => {
    'daypart': daypart,
    'condition': condition,
    'temp': temp,
    'layers': [for (final l in layers) WebThemeTokens.css(l.paint)],
    'haze': haze,
    'hazeCentre': WebThemeTokens.css(
      kSceneHaze.withValues(alpha: hazeCentreAlpha),
    ),
    'hazeEdge': WebThemeTokens.css(kSceneHaze.withValues(alpha: hazeEdgeAlpha)),
  };

  @override
  bool operator ==(Object other) =>
      other is SceneTokens &&
      other.daypart == daypart &&
      other.condition == condition &&
      other.temp == temp &&
      other.haze == haze &&
      _sameLayers(other.layers, layers);

  static bool _sameLayers(List<SceneLayer> a, List<SceneLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(daypart, condition, temp, haze, layers.length);
}

/// Turns the story's weather and clock into [SceneTokens]. Plain Dart with
/// no engine in it, so the mapping is unit tested cell by cell and the web
/// reproduces it from the wire. Unknown keys fall back to no wash, never to
/// a throw: a biome may name a period or band this build does not know.
class SceneSim {
  SceneSim._();

  static SceneTokens resolve({
    required String daypart,
    required WeatherCondition condition,
    required TempBand temp,
    required bool dark,
  }) {
    final scale = dark ? 1.0 : kSceneLightModeScale;
    final day = kSceneDaypartWash[daypart] ?? SceneWash.none;
    final cond =
        kSceneConditionWash[condition.name] ?? kSceneConditionWash['clear']!;
    final cast = kSceneTempCast[temp.name] ?? SceneWash.none;
    final layers = <SceneLayer>[
      SceneLayer(kSceneShade, cond.darken * scale),
      SceneLayer(day.color, day.alpha * scale),
      SceneLayer(cond.wash.color, cond.wash.alpha * scale),
      SceneLayer(cast.color, cast.alpha * scale),
    ];
    return SceneTokens(
      daypart: daypart,
      condition: condition.name,
      temp: temp.name,
      layers: [
        for (final l in layers)
          if (l.alpha > 0) l,
      ],
      haze: cond.haze * scale,
    );
  }
}
