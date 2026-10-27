// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Setting place's picture behind the chat (SceneBackdropLayer): the
// first picture shows at once, a move to another place dissolves from the
// old picture to the new one (both on the stage while it runs, one after),
// a re-saved picture of the same place dissolves too, and reduce motion
// swaps at once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
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

Widget _app(SceneBackdrop backdrop, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Stack(children: [SceneBackdropLayer(backdrop: backdrop)]),
    ),
  ),
);

Finder _picture(String place) => find.byWidgetPredicate(
  (w) => w is Image && w.key.toString().contains('scene_backdrop_${place}_'),
);

void main() {
  final teaRooms = _cover(60);
  final square = _cover(180);

  testWidgets('the first picture shows at once and nothing takes a tap', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_at('tea', teaRooms)));
    expect(_picture('tea'), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
  });

  testWidgets('a move dissolves: both pictures mid-way, the new one after', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_at('tea', teaRooms)));
    await tester.pumpWidget(_app(_at('square', square)));
    await tester.pump(kSceneBackdropTransition ~/ 2);
    expect(_picture('tea'), findsOneWidget);
    expect(_picture('square'), findsOneWidget);
    final arriving = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: _picture('square'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(arriving.opacity.value, greaterThan(0));
    expect(arriving.opacity.value, lessThan(1));
    await tester.pump(kSceneBackdropTransition);
    expect(_picture('tea'), findsNothing);
    expect(_picture('square'), findsOneWidget);
  });

  testWidgets('a re-saved picture of the same place dissolves too', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_at('tea', teaRooms)));
    await tester.pumpWidget(_app(_at('tea', square)));
    await tester.pump(kSceneBackdropTransition ~/ 2);
    expect(_picture('tea'), findsNWidgets(2));
    await tester.pump(kSceneBackdropTransition);
    expect(_picture('tea'), findsOneWidget);
  });

  testWidgets('reduce motion swaps the picture at once', (tester) async {
    await tester.pumpWidget(_app(_at('tea', teaRooms), reduceMotion: true));
    await tester.pumpWidget(_app(_at('square', square), reduceMotion: true));
    await tester.pump();
    expect(_picture('tea'), findsNothing);
    expect(_picture('square'), findsOneWidget);
  });
}
