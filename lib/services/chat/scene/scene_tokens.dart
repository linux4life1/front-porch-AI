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
import 'scene_effects.dart';

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
    required this.dark,
    this.level = SceneLevel.tint,
    this.seed = 0,
    this.effects = SceneEffectSpec.none,
    this.pauseWhileGenerating = true,
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

  /// Whether these are the dark-mode washes (light mode scales them down).
  final bool dark;

  /// The wash alone, or the wash and the moving weather.
  final SceneLevel level;

  /// What the moving weather is scattered from (`sceneSeed`).
  final int seed;

  /// The condition's moving weather; painted only at [SceneLevel.effects].
  final SceneEffectSpec effects;

  /// Appearance → Pause effects while generating: the stage stops while a
  /// reply is on its way, so a local model has the GPU to itself.
  final bool pauseWhileGenerating;

  /// The colours the moving weather paints in, for this brightness.
  SceneEffectPaints get paints =>
      dark ? kSceneEffectPaintsDark : kSceneEffectPaintsLight;

  /// Whether the moving weather paints at all.
  bool get hasEffects => level == SceneLevel.effects && !effects.isEmpty;

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

  /// One brightness's washes and weather paints as CSS colour strings, so
  /// the PWA never works out a colour.
  Map<String, Object> toModeWire() => {
    'layers': [for (final l in layers) WebThemeTokens.css(l.paint)],
    'haze': haze,
    'hazeCentre': WebThemeTokens.css(
      kSceneHaze.withValues(alpha: hazeCentreAlpha),
    ),
    'hazeEdge': WebThemeTokens.css(kSceneHaze.withValues(alpha: hazeEdgeAlpha)),
    // Only at Tint and effects: a tint-only scene has nothing to paint
    // with them, and its mode map stays the four keys it shipped with.
    if (level == SceneLevel.effects)
      'paints': {
        'rain': WebThemeTokens.css(paints.rain),
        'snow': WebThemeTokens.css(paints.snow),
        'cloud': WebThemeTokens.css(paints.cloud),
        'fog': WebThemeTokens.css(paints.fog),
        // The fog's own hue at zero alpha, the far stop of each blob.
        'fogClear': WebThemeTokens.css(paints.fog.withValues(alpha: 0)),
        'flash': WebThemeTokens.css(paints.flash),
      },
  };

  /// The wire the web paints from: the scene's keys plus both brightnesses,
  /// because the PWA may run its own mode (like `webThemeWire` ships both
  /// token maps). [dark] and [light] are the same scene resolved twice.
  /// The web scatters the same weather from [seed] with the same generator;
  /// what moves is the same in both modes, only its paints differ.
  /// Additive; an older PWA ignores it.
  static Map<String, Object> wireOf({
    required SceneTokens dark,
    required SceneTokens light,
  }) => {
    'daypart': dark.daypart,
    'condition': dark.condition,
    'temp': dark.temp,
    'level': dark.level.key,
    'seed': dark.seed,
    'pauseWhileGenerating': dark.pauseWhileGenerating,
    'effects': dark.effects.toWire(),
    'dark': dark.toModeWire(),
    'light': light.toModeWire(),
  };

  @override
  bool operator ==(Object other) =>
      other is SceneTokens &&
      other.daypart == daypart &&
      other.condition == condition &&
      other.temp == temp &&
      other.haze == haze &&
      other.dark == dark &&
      other.level == level &&
      other.seed == seed &&
      other.effects == effects &&
      other.pauseWhileGenerating == pauseWhileGenerating &&
      _sameLayers(other.layers, layers);

  static bool _sameLayers(List<SceneLayer> a, List<SceneLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    daypart,
    condition,
    temp,
    haze,
    dark,
    layers.length,
    level,
    seed,
    effects,
  );
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
    SceneLevel level = SceneLevel.tint,
    int seed = 0,
    bool pauseWhileGenerating = true,
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
      dark: dark,
      level: level,
      seed: seed,
      effects: SceneEffectSpec.forCondition(condition.name),
      pauseWhileGenerating: pauseWhileGenerating,
    );
  }
}
