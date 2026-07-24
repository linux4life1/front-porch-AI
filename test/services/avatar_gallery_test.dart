// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the pure avatar-gallery ("looks") logic — filtering,
// plain-chat display resolution, and chevron flipping. Storage-agnostic (the
// per-chat selection is an input), so no DB/session dependency.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';

AvatarImage _look(String id, {int order = 0}) => AvatarImage(
  id: id,
  characterId: 'c1',
  filename: '$id.png',
  label: AvatarImage.lookLabel,
  displayOrder: order,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

AvatarImage _expr(String id, String emotion, {int order = 0}) => AvatarImage(
  id: id,
  characterId: 'c1',
  filename: '$id.png',
  label: emotion,
  displayOrder: order,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  group('AvatarImage look tagging + folder resolution', () {
    test('isLook + subfolder distinguish looks from expressions', () {
      expect(_look('a').isLook, isTrue);
      expect(_look('a').subfolder, 'looks');
      expect(_expr('b', 'joy').isLook, isFalse);
      expect(_expr('b', 'joy').subfolder, 'avatars');
      // A null-label (legacy) avatar is NOT a look — the sentinel is required.
      final legacy = AvatarImage(
        id: 'x',
        characterId: 'c1',
        filename: 'x.png',
        displayOrder: 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(legacy.isLook, isFalse);
      expect(legacy.subfolder, 'avatars');
    });

    test('resolveFile picks looks/ vs avatars/ off the character base folder', () {
      expect(
        _look('a').resolveFile('/chars/Carly').path,
        '/chars/Carly/looks/a.png',
      );
      expect(
        _expr('b', 'joy').resolveFile('/chars/Carly').path,
        '/chars/Carly/avatars/b.png',
      );
    });
  });

  group('looksFrom / expressionsFrom partitioning', () {
    final mixed = [
      _expr('e1', 'joy', order: 0),
      _look('l2', order: 2),
      _expr('e2', 'anger', order: 1),
      _look('l1', order: 1),
    ];

    test('looksFrom keeps only looks, ordered by displayOrder', () {
      final looks = looksFrom(mixed);
      expect(looks.map((l) => l.id), ['l1', 'l2']);
    });

    test('expressionsFrom keeps only expressions (looks partitioned out)', () {
      final exprs = expressionsFrom(mixed);
      expect(exprs.map((e) => e.id).toSet(), {'e1', 'e2'});
      expect(exprs.every((e) => !e.isLook), isTrue);
    });

    test('null list → empty', () {
      expect(looksFrom(null), isEmpty);
      expect(expressionsFrom(null), isEmpty);
    });
  });

  group('buildFaceRing (plain-chat face ring order)', () {
    final looks = [_look('l1', order: 0), _look('l2', order: 1)];

    test('portrait leads, then looks, when no favorite', () {
      final ring = buildFaceRing(
        looks: looks,
        hasImagePath: true,
        favorite: null,
      );
      expect(ring, [kPortraitFaceId, 'l1', 'l2']);
    });

    test('no imagePath → just the looks', () {
      final ring = buildFaceRing(
        looks: looks,
        hasImagePath: false,
        favorite: null,
      );
      expect(ring, ['l1', 'l2']);
    });

    test('favorite look leads, deduped, portrait next', () {
      final ring = buildFaceRing(
        looks: looks,
        hasImagePath: true,
        favorite: _look('l2', order: 1),
      );
      expect(ring, ['l2', kPortraitFaceId, 'l1']);
    });

    test('favorite EXPRESSION joins the ring at slot 0 (reachable + default)', () {
      final ring = buildFaceRing(
        looks: looks,
        hasImagePath: true,
        favorite: _expr('joy1', 'joy'),
      );
      expect(ring, ['joy1', kPortraitFaceId, 'l1', 'l2']);
    });

    test('single look + portrait → ring of 2', () {
      final ring = buildFaceRing(
        looks: [_look('only')],
        hasImagePath: true,
        favorite: null,
      );
      expect(ring, [kPortraitFaceId, 'only']);
    });

    test('single look, no portrait, no favorite → ring of 1', () {
      final ring = buildFaceRing(
        looks: [_look('only')],
        hasImagePath: false,
        favorite: null,
      );
      expect(ring, ['only']);
    });
  });

  group('resolveFaceDisplay (plain-chat face resolution)', () {
    final looks = [_look('l1', order: 0), _look('l2', order: 1)];
    final ring = buildFaceRing(looks: looks, hasImagePath: true, favorite: null);
    // ring == [portrait, l1, l2]

    test('valid selection → that image; chevrons when ring > 1', () {
      final d = resolveFaceDisplay(
        ring: ring,
        allImages: looks,
        selectedFaceId: 'l2',
      );
      expect(d.image?.id, 'l2');
      expect(d.position, 3);
      expect(d.total, 3);
      expect(d.showChevrons, isTrue);
    });

    test('portrait sentinel → null image (caller shows imagePath)', () {
      final d = resolveFaceDisplay(
        ring: ring,
        allImages: looks,
        selectedFaceId: kPortraitFaceId,
      );
      expect(d.image, isNull);
      expect(d.position, 1);
    });

    test('null / stale selection → ring.first (default), not blank', () {
      final d = resolveFaceDisplay(
        ring: ring,
        allImages: looks,
        selectedFaceId: 'deleted-id',
      );
      expect(d.image, isNull); // ring.first is the portrait
      expect(d.position, 1);
    });

    test('resolves a starred EXPRESSION face too', () {
      final joy = _expr('joy1', 'joy');
      final exprRing = buildFaceRing(
        looks: looks,
        hasImagePath: true,
        favorite: joy,
      );
      final d = resolveFaceDisplay(
        ring: exprRing,
        allImages: [joy, ...looks],
        selectedFaceId: null, // default → the star (slot 0)
      );
      expect(d.image?.id, 'joy1');
      expect(d.position, 1);
    });

    test('empty ring → empty display', () {
      final d = resolveFaceDisplay(ring: const [], allImages: looks);
      expect(d, FaceDisplay.empty);
      expect(d.showChevrons, isFalse);
    });
  });

  group('decodeSelectedLooks / encodeSelectedLooks (per-chat map codec)', () {
    test('round-trips a multi-character (group) map', () {
      const map = {'charA': 'look1', 'charB': 'look2'};
      final encoded = encodeSelectedLooks(map);
      expect(decodeSelectedLooks(encoded), map);
    });

    test('1:1 is just a one-entry map', () {
      final encoded = encodeSelectedLooks({'charA': 'look1'});
      expect(decodeSelectedLooks(encoded), {'charA': 'look1'});
    });

    test('empty map encodes to null (clears the column)', () {
      expect(encodeSelectedLooks(const {}), isNull);
    });

    test('null / empty / garbage / non-map all decode to empty, never throw', () {
      expect(decodeSelectedLooks(null), isEmpty);
      expect(decodeSelectedLooks(''), isEmpty);
      expect(decodeSelectedLooks('not json at all'), isEmpty);
      expect(decodeSelectedLooks('["a","b"]'), isEmpty); // a list, not a map
      expect(decodeSelectedLooks('"bare-string"'), isEmpty);
      expect(decodeSelectedLooks('42'), isEmpty);
    });

    test('drops malformed entries (non-string / empty keys or values)', () {
      // Mixed value types + empty strings — only the clean entry survives.
      expect(
        decodeSelectedLooks('{"charA":"look1","charB":5,"":"x","charC":""}'),
        {'charA': 'look1'},
      );
    });
  });

  group('flipFace (chevron navigation over the face ring)', () {
    final ring = [kPortraitFaceId, 'a', 'b', 'c'];

    test('next / prev / wrap', () {
      expect(flipFace(ring, kPortraitFaceId, 1), 'a');
      expect(flipFace(ring, 'a', 1), 'b');
      expect(flipFace(ring, 'c', 1), kPortraitFaceId); // wrap forward
      expect(flipFace(ring, kPortraitFaceId, -1), 'c'); // wrap backward
    });

    test('can always cycle back to the portrait sentinel', () {
      expect(flipFace(ring, 'a', -1), kPortraitFaceId);
    });

    test('stale current id → steps in from the appropriate end', () {
      expect(flipFace(ring, 'deleted', 1), kPortraitFaceId); // forward → first
      expect(flipFace(ring, 'deleted', -1), 'c'); // backward → last
      expect(flipFace(ring, null, 1), kPortraitFaceId);
    });

    test('empty ring → null', () {
      expect(flipFace(const [], 'x', 1), isNull);
    });
  });
}
