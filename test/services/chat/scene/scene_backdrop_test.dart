// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The picture behind the chat (docs/design/ambient-stage.md, Backgrounds):
// the Setting place's own cover wins, a place without one shows its nearest
// ancestor's, a chain with none leaves the chat its chosen background, and
// the web wire names the place and a versioned URL to fetch it from.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
import 'package:front_porch_ai/utils/world_cover.dart';
import 'package:image/image.dart' as img;

String _cover(int shade) => encodeWorldCoverDataUrl(
  img.encodePng(
    img.Image(width: 4, height: 4)..clear(img.ColorRgb8(shade, shade, shade)),
  ),
)!;

World _place(String id, {String? cover, String? parent}) => World(
  id: id,
  name: id,
  lorebook: Lorebook(entries: const []),
  coverImage: cover,
  parentWorldId: parent,
);

void main() {
  final townCover = _cover(40);
  final roomCover = _cover(200);

  test('the Setting place with a picture is the backdrop', () {
    final chain = [
      _place('room', cover: roomCover, parent: 'town'),
      _place('town', cover: townCover),
    ];
    final backdrop = sceneBackdropOf(chain);
    expect(backdrop?.placeId, 'room');
    expect(backdrop?.placeName, 'room');
    expect(backdrop?.cover, roomCover);
  });

  test('a place without a picture shows its nearest ancestor with one', () {
    final chain = [
      _place('room', parent: 'house'),
      _place('house', cover: '', parent: 'town'),
      _place('town', cover: townCover),
    ];
    expect(sceneBackdropOf(chain)?.placeId, 'town');
  });

  test('a chain with no picture leaves the chat its chosen background', () {
    expect(sceneBackdropOf([_place('town')]), isNull);
    expect(sceneBackdropOf(const []), isNull);
  });

  test('a cover that is a path, not a data URL, counts as none', () {
    final chain = [
      _place('room', cover: '/pictures/room.png', parent: 'town'),
      _place('town', cover: townCover),
    ];
    expect(sceneBackdropOf(chain)?.placeId, 'town');
  });

  test('the wire names the place and a URL that changes with the picture', () {
    final before = sceneBackdropOf([_place('town', cover: townCover)])!;
    final after = sceneBackdropOf([_place('town', cover: roomCover)])!;
    final wire = sceneBackdropWire(before);
    expect(wire['placeId'], 'town');
    expect(wire['placeName'], 'town');
    expect(wire['url'], '$kSceneBackdropRoute?id=town&v=${before.version}');
    expect(before, isNot(equals(after)));
    expect(sceneBackdropWire(after)['url'], isNot(wire['url']));
    // The same picture read twice is the same scene: no dissolve, no refetch.
    expect(before, sceneBackdropOf([_place('town', cover: townCover)]));
  });

  test('the bytes come with the media type the data URL declares', () {
    final jpeg = sceneBackdropBytes(townCover)!;
    expect(jpeg.contentType, 'image/jpeg');
    expect(jpeg.bytes, decodeWorldCoverBytes(townCover));
    final png = sceneBackdropBytes(
      'data:image/png;base64,${townCover.split('base64,').last}',
    )!;
    expect(png.contentType, 'image/png');
    final svg = sceneBackdropBytes(
      'data:image/svg+xml;base64,${townCover.split('base64,').last}',
    )!;
    expect(svg.contentType, 'image/jpeg', reason: 'never a scriptable type');
    expect(sceneBackdropBytes('not a picture'), isNull);
  });
}
