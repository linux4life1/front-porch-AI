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
// never takes focus or a Tab stop, carries the scene tokens into its tint
// component, swaps them without rebuilding the game, paints a static scene
// on change without running the engine loop, lets an animated one tick
// only while the app is visible, and records the tint once per scene and
// size rather than once per frame.

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Widget _app(SceneTokens tokens, {bool animated = false}) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: AmbientStage(tokens: tokens, animated: animated),
        ),
        const TextField(key: ValueKey('composer'), autofocus: true),
      ],
    ),
  ),
);

/// Counts the engine's update steps once it is mounted in the game.
class _TickCounter extends Component {
  int ticks = 0;

  @override
  void update(double dt) => ticks++;
}

Future<AmbientStageGame> _pump(
  WidgetTester tester,
  SceneTokens tokens, {
  bool animated = false,
}) async {
  await tester.pumpWidget(_app(tokens, animated: animated));
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
    final tint = game.children.whereType<SceneTintComponent>().single;
    expect(tint.tokens, game.tokens);
    // The composer keeps the keyboard; the stage never autofocuses.
    final stage = find.byType(GameWidget<AmbientStageGame>);
    expect(tester.widget<GameWidget<AmbientStageGame>>(stage).autofocus, false);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    // Nor is it a Tab stop: GameWidget brings its own Focus, so Tab from the
    // composer would land on the stage unless the stage excludes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
      find.descendant(
        of: stage,
        matching: find.byElementPredicate((e) => e == focused),
      ),
      findsNothing,
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('new tokens reach the tint without a new game', (tester) async {
    final game = await _pump(tester, _scene(WeatherCondition.rain));
    await tester.pumpWidget(_app(_scene(WeatherCondition.snow)));
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

  testWidgets('a static stage paints on change and never runs the loop', (
    tester,
  ) async {
    final game = await _pump(tester, _scene(WeatherCondition.rain));
    expect(game.paused, isTrue);
    // The first paint happened without the loop: the tint is mounted.
    final tint = game.children.whereType<SceneTintComponent>().single;
    expect(tint.isMounted, isTrue);
    expect(tint.tokens.condition, 'rain');

    // A component added now mounts only on the engine's next step, so a
    // second of frames that leaves it unmounted proves nothing ticked.
    final counter = _TickCounter();
    await game.add(counter);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(counter.isMounted, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);

    // A new scene steps the engine exactly once, still paused.
    await tester.pumpWidget(_app(_scene(WeatherCondition.snow)));
    expect(counter.ticks, 1);
    expect(tint.tokens.condition, 'snow');
    expect(game.paused, isTrue);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(counter.ticks, 1);
    // That one step is what repaints: between frames, a change marks the
    // stage for paint and the next frame paints it. The same tokens again
    // are a no-op.
    game.tokens = _scene(WeatherCondition.fog);
    expect(game.renderBox.debugNeedsPaint, isTrue);
    expect(counter.ticks, 2);
    await tester.pump();
    expect(game.renderBox.debugNeedsPaint, isFalse);
    game.tokens = _scene(WeatherCondition.fog);
    expect(game.renderBox.debugNeedsPaint, isFalse);
    expect(counter.ticks, 2);

    // The lifecycle never starts a static stage.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(game.paused, isTrue);
    expect(counter.ticks, 2);
  });

  testWidgets('an animated stage ticks only while the app is visible', (
    tester,
  ) async {
    final game = await _pump(
      tester,
      _scene(WeatherCondition.storm),
      animated: true,
    );
    expect(game.paused, isFalse);
    final counter = _TickCounter();
    await game.add(counter);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(counter.ticks, greaterThan(0), reason: 'resumed: ticking');
    // Flutter's lifecycle walks resumed → inactive → hidden and back.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(game.paused, isTrue, reason: 'inactive is not looking');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(game.paused, isTrue);
    final hidden = counter.ticks;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(counter.ticks, hidden, reason: 'hidden: no ticks');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(game.paused, isTrue, reason: 'inactive is not yet looking');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.paused, isFalse);
    expect(counter.ticks, greaterThan(hidden), reason: 'resumed: ticking');
  });

  testWidgets('the first frame the stage paints is already tinted', (
    tester,
  ) async {
    // Runs after the rendering pipeline's own frame callback, so after the
    // frame's paint and before its post-frame callbacks: what it sees on
    // the frame the stage first attaches is what that frame painted.
    AmbientStageGame? game;
    bool? tintAtFirstPaint;
    bool? paintedThatFrame;
    tester.binding.addPersistentFrameCallback((_) {
      if (tintAtFirstPaint != null) return;
      final found = find.byType(GameWidget<AmbientStageGame>).evaluate();
      if (found.isEmpty) return;
      game ??= (found.single.widget as GameWidget<AmbientStageGame>).game;
      final g = game!;
      if (!g.isAttached) return;
      paintedThatFrame = !g.renderBox.debugNeedsPaint;
      tintAtFirstPaint = g.children.whereType<SceneTintComponent>().any(
        (c) => c.isMounted,
      );
    });
    for (final animated in [false, true]) {
      game = null;
      tintAtFirstPaint = null;
      paintedThatFrame = null;
      await tester.pumpWidget(
        _app(_scene(WeatherCondition.rain), animated: animated),
      );
      for (var i = 0; i < 5 && tintAtFirstPaint == null; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(paintedThatFrame, isTrue, reason: 'animated: $animated');
      expect(tintAtFirstPaint, isTrue, reason: 'animated: $animated');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the tint is recorded once per scene and size, not per frame', (
    tester,
  ) async {
    final game = await _pump(
      tester,
      _scene(WeatherCondition.fog),
      animated: true,
    );
    expect(game.paused, isFalse);
    final tint = game.children.whereType<SceneTintComponent>().single;
    await tester.pump(const Duration(milliseconds: 16));
    final recorded = tint.debugRebuilds;
    expect(recorded, greaterThan(0));
    // An animated stage renders every frame; the washes do not change.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tint.debugRebuilds, recorded);
    // A new scene records once more, then holds again.
    await tester.pumpWidget(
      _app(_scene(WeatherCondition.rain), animated: true),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tint.debugRebuilds, recorded + 1);
    // So does a new stage size.
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tint.debugRebuilds, recorded + 2);
  });
}
