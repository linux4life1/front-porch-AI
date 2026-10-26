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

// The Ambient Stage's moving weather (docs/design/ambient-stage.md, PR 2):
// the effect components mount at Tint and effects and never at Tint only,
// reduce motion makes the stage static with the weather held still where it
// is and the tint still up, and Pause effects while generating stops the
// engine for a reply only when it is on and only on a moving stage, and a
// scene change while it is stopped repaints without moving the weather.
// The layers stack as the web's canvas does: tint, clouds, fog, rain or
// snow, the flash.

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/ambient_stage.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/ambient_stage_game.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/scene_precipitation.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/scene_sky_layers.dart';

SceneTokens _scene(
  WeatherCondition c, {
  SceneLevel level = SceneLevel.effects,
  bool pause = true,
  TempBand temp = TempBand.cool,
}) => SceneSim.resolve(
  daypart: 'evening',
  condition: c,
  temp: temp,
  dark: true,
  level: level,
  seed: 99,
  pauseWhileGenerating: pause,
);

Widget _host(
  SceneTokens tokens, {
  bool generating = false,
  bool still = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: const Size(800, 600), disableAnimations: still),
    child: Scaffold(
      // The chat page's rule (ChatSurface): the stage moves only with
      // weather to move and motion allowed.
      body: Builder(
        builder: (context) => AmbientStage(
          tokens: tokens,
          animated:
              tokens.hasEffects && !MediaQuery.disableAnimationsOf(context),
          generating: generating,
        ),
      ),
    ),
  ),
);

Future<AmbientStageGame> _pump(
  WidgetTester tester,
  SceneTokens tokens, {
  bool generating = false,
  bool still = false,
}) async {
  await tester.pumpWidget(_host(tokens, generating: generating, still: still));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return tester
      .widget<GameWidget<AmbientStageGame>>(
        find.byType(GameWidget<AmbientStageGame>),
      )
      .game!;
}

List<Component> _effectLayers(AmbientStageGame g) => [
  ...g.children.whereType<SceneCloudLayer>(),
  ...g.children.whereType<SceneFogLayer>(),
  ...g.children.whereType<ScenePrecipitation>(),
  ...g.children.whereType<SceneLightningFlash>(),
];

List<double> _drops(AmbientStageGame g) => [
  for (final d in g.effects!.drops) ...[d.x, d.y],
];

void main() {
  testWidgets('effects mount at Tint and effects and leave at Tint only', (
    tester,
  ) async {
    final game = await _pump(tester, _scene(WeatherCondition.storm));
    expect(_effectLayers(game), hasLength(4));
    expect(game.effects, isNotNull);
    expect(game.effects!.drops, isNotEmpty);
    expect(game.effects!.clouds, hasLength(9));
    expect(game.children.whereType<SceneTintComponent>(), hasLength(1));

    await tester.pumpWidget(
      _host(_scene(WeatherCondition.storm, level: SceneLevel.tint)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(_effectLayers(game), isEmpty);
    expect(game.effects, isNull);
    expect(game.children.whereType<SceneTintComponent>(), hasLength(1));
  });

  testWidgets('Tint only never mounts the effects', (tester) async {
    final game = await _pump(
      tester,
      _scene(WeatherCondition.rain, level: SceneLevel.tint),
    );
    expect(_effectLayers(game), isEmpty);
    expect(game.effects, isNull);
  });

  testWidgets('the weather moves, and reduce motion holds it still', (
    tester,
  ) async {
    final moving = await _pump(tester, _scene(WeatherCondition.rain));
    final before = _drops(moving);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drops(moving), isNot(before));

    await tester.pumpWidget(const SizedBox());
    final still = await _pump(
      tester,
      _scene(WeatherCondition.rain),
      still: true,
    );
    expect(still.effectsFrozen, isTrue);
    expect(still.paused, isTrue, reason: 'static: paints on change only');
    expect(_effectLayers(still), hasLength(4), reason: 'drawn, held still');
    final held = _drops(still);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drops(still), held, reason: 'frozen where they are');

    // A new sky repaints once, scattered afresh and still held.
    await tester.pumpWidget(_host(_scene(WeatherCondition.storm), still: true));
    expect(still.paused, isTrue);
    final storm = _drops(still);
    expect(storm, isNot(held));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drops(still), storm);

    // Motion allowed again: the same stage starts moving.
    await tester.pumpWidget(_host(_scene(WeatherCondition.storm)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(still.paused, isFalse);
    expect(still.effectsFrozen, isFalse);
    expect(_drops(still), isNot(storm));
  });

  testWidgets('generating pauses the stage when the switch is on', (
    tester,
  ) async {
    final game = await _pump(tester, _scene(WeatherCondition.snow));
    expect(game.paused, isFalse);
    await tester.pumpWidget(
      _host(_scene(WeatherCondition.snow), generating: true),
    );
    await tester.pump();
    expect(game.paused, isTrue);
    await tester.pumpWidget(_host(_scene(WeatherCondition.snow)));
    await tester.pump();
    expect(game.paused, isFalse, reason: 'back when the reply is done');
  });

  testWidgets('generating leaves the stage running with the switch off', (
    tester,
  ) async {
    final game = await _pump(
      tester,
      _scene(WeatherCondition.snow, pause: false),
      generating: true,
    );
    expect(game.paused, isFalse);
    final before = _drops(game);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drops(game), isNot(before));
  });

  testWidgets('a static stage ignores generating', (tester) async {
    // Tint only, and the weather under reduce motion, never run the loop,
    // so a reply has nothing to pause or resume.
    for (final (level, still) in [
      (SceneLevel.tint, false),
      (SceneLevel.effects, true),
    ]) {
      final game = await _pump(
        tester,
        _scene(WeatherCondition.snow, level: level),
        still: still,
      );
      expect(game.paused, isTrue);
      await tester.pumpWidget(
        _host(
          _scene(WeatherCondition.snow, level: level),
          generating: true,
          still: still,
        ),
      );
      await tester.pump();
      expect(game.paused, isTrue);
      await tester.pumpWidget(
        _host(_scene(WeatherCondition.snow, level: level), still: still),
      );
      await tester.pump();
      expect(game.paused, isTrue, reason: 'still static after the reply');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'the layers stack as on the web: tint, clouds, fog, fall, flash',
    (tester) async {
      final game = await _pump(tester, _scene(WeatherCondition.storm));
      final order = game.children
          .where(
            (c) =>
                c is SceneTintComponent ||
                c is SceneCloudLayer ||
                c is SceneFogLayer ||
                c is ScenePrecipitation ||
                c is SceneLightningFlash,
          )
          .map((c) => c.runtimeType)
          .toList();
      expect(order, [
        SceneTintComponent,
        SceneCloudLayer,
        SceneFogLayer,
        ScenePrecipitation,
        SceneLightningFlash,
      ]);
    },
  );

  testWidgets('a new scene while paused for a reply repaints, moving nothing', (
    tester,
  ) async {
    final game = await _pump(tester, _scene(WeatherCondition.rain));
    await tester.pumpWidget(
      _host(_scene(WeatherCondition.rain), generating: true),
    );
    await tester.pump();
    expect(game.paused, isTrue);
    final sim = game.effects!;
    final held = _drops(game);
    final time = sim.time;
    // A colder cast is a new scene on the same seed and spec: the same
    // weather, repainted once (a zero-time engine step), and still where
    // the pause left it.
    await tester.pumpWidget(
      _host(
        _scene(WeatherCondition.rain, temp: TempBand.cold),
        generating: true,
      ),
    );
    expect(game.tokens.temp, TempBand.cold.name);
    expect(identical(game.effects, sim), isTrue);
    expect(_drops(game), held);
    expect(sim.time, time);
  });

  testWidgets('leaving the chat frees the fog\'s gradients', (tester) async {
    final game = await _pump(tester, _scene(WeatherCondition.fog));
    final fog = game.children.whereType<SceneFogLayer>().single;
    expect(fog.debugShaderCount, game.effects!.fogBlobs.length);
    await tester.pumpWidget(const SizedBox());
    expect(fog.isRemoved, isTrue);
    expect(fog.debugShaderCount, 0);
  });
}
