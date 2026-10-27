// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Setting place's picture behind the chat (SceneBackdropLayer over
// SceneBackdropGame): the first picture shows at once on a game that does
// not tick; a move to another place runs the weather's move on the game
// with the old picture kept until it ends and the place's name on a card;
// a re-saved picture of the same place moves too; reduce motion swaps at
// once and still names the place.
//
// Rewritten with the Flame backdrop (the earlier layer was an
// AnimatedSwitcher of Image widgets; the pictures are now drawn by the
// game, so the assertions read the game, not the widget tree).

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop_transition.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/scene_backdrop_game.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/scene_backdrop_layer.dart';
import 'package:front_porch_ai/utils/world_cover.dart';
import 'package:image/image.dart' as img;

String _cover(int shade) => encodeWorldCoverDataUrl(
  img.encodePng(
    img.Image(width: 4, height: 4)..clear(img.ColorRgb8(shade, shade, shade)),
  ),
)!;

SceneBackdrop _at(String place, String cover) =>
    SceneBackdrop(placeId: place, placeName: place, cover: cover);

Widget _app(
  SceneBackdrop backdrop, {
  bool reduceMotion = false,
  String? condition,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      disableAnimations: reduceMotion,
    ),
    child: Scaffold(
      body: Stack(
        children: [
          SceneBackdropLayer(backdrop: backdrop, conditionOf: () => condition),
          const TextField(key: ValueKey('composer'), autofocus: true),
        ],
      ),
    ),
  ),
);

SceneBackdropGame _game(WidgetTester tester) => tester
    .widget<GameWidget<SceneBackdropGame>>(
      find.byType(GameWidget<SceneBackdropGame>),
    )
    .game!;

/// Pumps the widget and lets the picture decode (real async work, so
/// under runAsync) and the game mount and take it.
Future<SceneBackdropGame> _show(
  WidgetTester tester,
  SceneBackdrop backdrop, {
  bool reduceMotion = false,
  String? condition,
}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      _app(backdrop, reduceMotion: reduceMotion, condition: condition),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return _game(tester);
}

void main() {
  final teaRooms = _cover(60);
  final square = _cover(180);

  testWidgets('the first picture shows at once on a game that does not tick', (
    tester,
  ) async {
    final game = await _show(tester, _at('tea', teaRooms));
    expect(game.debugCurrent, isNotNull);
    expect(game.debugPrevious, isNull);
    expect(game.moving, isFalse);
    expect(game.paused, isTrue, reason: 'a still picture costs no frames');
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel ?? '',
      isNot(contains('GameWidget')),
    );
    expect(find.text('tea'), findsNothing, reason: 'no card on the first');
  });

  testWidgets(
    'a move runs the weather\'s move, keeps the old picture, names the place',
    (tester) async {
      var game = await _show(tester, _at('tea', teaRooms));
      final first = game.debugCurrent;
      game = await _show(tester, _at('square', square), condition: 'rain');
      expect(game.moving, isTrue);
      expect(game.kind, SceneMoveKind.travel);
      expect(game.paused, isFalse, reason: 'ticks while the move runs');
      expect(identical(game.debugPrevious, first), isTrue);
      expect(game.debugCurrent, isNot(same(first)));
      expect(find.text('square'), findsOneWidget, reason: 'the title card');
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(const Duration(milliseconds: 20));
      expect(game.moving, isFalse);
      expect(game.debugPrevious, isNull, reason: 'the old picture is let go');
      expect(game.paused, isTrue, reason: 'still again');
      expect(find.text('square'), findsNothing);
    },
  );

  testWidgets('fog rolls and a storm cuts', (tester) async {
    await _show(tester, _at('tea', teaRooms));
    var game = await _show(tester, _at('square', square), condition: 'fog');
    expect(game.kind, SceneMoveKind.fogRoll);
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 20));
    game = await _show(tester, _at('tea', teaRooms), condition: 'storm');
    expect(game.kind, SceneMoveKind.lightningCut);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 20));
    expect(game.moving, isFalse);
  });

  testWidgets('a re-saved picture of the same place moves too', (tester) async {
    await _show(tester, _at('tea', teaRooms));
    final game = await _show(tester, _at('tea', square));
    expect(game.moving, isTrue);
    expect(game.debugPrevious, isNotNull);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 20));
    expect(game.moving, isFalse);
  });

  testWidgets('reduce motion swaps the picture at once and still names it', (
    tester,
  ) async {
    await _show(tester, _at('tea', teaRooms), reduceMotion: true);
    final game = await _show(
      tester,
      _at('square', square),
      reduceMotion: true,
      condition: 'storm',
    );
    expect(game.moving, isFalse);
    expect(game.debugPrevious, isNull);
    expect(game.paused, isTrue);
    expect(find.text('square'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text('square'), findsNothing);
  });
}
