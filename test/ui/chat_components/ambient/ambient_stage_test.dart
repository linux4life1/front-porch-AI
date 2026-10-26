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

// The Ambient Stage (docs/design/ambient-stage.md): mounts a Flame game that
// never takes focus, carries the scene tokens into its tint component,
// swaps them without rebuilding the game, and stops ticking while the app
// is hidden or inactive.

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/ambient_stage.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/ambient_stage_game.dart';

SceneTokens _scene(WeatherCondition c) => SceneSim.resolve(
  daypart: 'evening',
  condition: c,
  temp: TempBand.cool,
  dark: true,
);

Future<AmbientStageGame> _pump(WidgetTester tester, SceneTokens tokens) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: AmbientStage(tokens: tokens)),
            const TextField(key: ValueKey('composer'), autofocus: true),
          ],
        ),
      ),
    ),
  );
  // Flame loads the game and mounts its components over the next frames.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  final widget = tester.widget<GameWidget<AmbientStageGame>>(
    find.byType(GameWidget<AmbientStageGame>),
  );
  return widget.game!;
}

void main() {
  testWidgets('mounts the stage with the scene and leaves focus alone', (
    tester,
  ) async {
    final game = await _pump(tester, _scene(WeatherCondition.rain));
    expect(game.tokens.condition, 'rain');
    expect(game.paused, isFalse);
    final tint = game.children.whereType<SceneTintComponent>().single;
    expect(tint.tokens, game.tokens);
    // The composer keeps the keyboard; the stage never autofocuses.
    expect(
      tester
          .widget<GameWidget<AmbientStageGame>>(
            find.byType(GameWidget<AmbientStageGame>),
          )
          .autofocus,
      isFalse,
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('new tokens reach the tint without a new game', (tester) async {
    final game = await _pump(tester, _scene(WeatherCondition.rain));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: AmbientStage(tokens: _scene(WeatherCondition.snow)),
              ),
              const TextField(key: ValueKey('composer'), autofocus: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final again = tester
        .widget<GameWidget<AmbientStageGame>>(
          find.byType(GameWidget<AmbientStageGame>),
        )
        .game!;
    expect(identical(again, game), isTrue);
    expect(game.tokens.condition, 'snow');
    expect(
      game.children.whereType<SceneTintComponent>().single.tokens.condition,
      'snow',
    );
  });

  testWidgets('a hidden app pauses the engine and a resumed one restarts it', (
    tester,
  ) async {
    final game = await _pump(tester, _scene(WeatherCondition.storm));
    expect(game.paused, isFalse);
    // Flutter's lifecycle walks resumed → inactive → hidden and back.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(game.paused, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(game.paused, isTrue, reason: 'inactive is not yet looking');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(game.paused, isFalse);
  });
}
