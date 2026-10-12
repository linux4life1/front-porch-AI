// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

/// Her persona is baked into the serve at start. An edited card or a new
/// day must reach the next turn, not wait for an app restart.
void main() {
  const backend = OpenCodePorchBackend(
    baseUrl: 'http://127.0.0.1:5001/v1',
    apiKey: 'x',
    modelId: 'local',
  );

  WaifuSession sessionFor(String personality) => WaifuSession(
    folderRoot: '.',
    coworker: CharacterCard(name: 'Mira', personality: personality),
  );

  test('a card edit makes the next turn reseat', () {
    final session = sessionFor('dry and exact');
    final seat = WaifuOpenCodeSeat(session: session, backend: backend);
    expect(seat.needsReseat, isFalse);
    final live = CharacterCard(name: 'Mira', personality: 'warm, teasing');
    expect(waifuAdoptCoworker(session, live), isTrue);
    expect(session.coworker, same(live));
    expect(seat.needsReseat, isTrue);
  });

  test('the same card is not adopted and does not reseat', () {
    final session = sessionFor('dry and exact');
    final seat = WaifuOpenCodeSeat(session: session, backend: backend);
    final copy = CharacterCard(name: 'Mira', personality: 'dry and exact');
    expect(waifuAdoptCoworker(session, copy), isFalse);
    expect(seat.needsReseat, isFalse);
  });

  test('a new day makes the next turn reseat with today\'s date', () {
    var now = DateTime(2026, 10, 11, 23, 59);
    final seat = WaifuOpenCodeSeat(
      session: sessionFor('dry'),
      backend: backend,
      clock: () => now,
    );
    expect(seat.needsReseat, isFalse);
    now = DateTime(2026, 10, 12, 0, 1);
    expect(seat.needsReseat, isTrue);
  });

  test('a saved session keeps the card id to find it after a rename', () async {
    final root = await Directory.systemTemp.createTemp('waifu_persona_');
    addTearDown(() => root.delete(recursive: true));
    final store = WaifuStore(p.join(root.path, 'store'));
    final folder = p.join(root.path, 'porch');
    await store.saveLast(
      WaifuSession(
        folderRoot: folder,
        coworker: CharacterCard(name: 'Mira', dbId: 'card-1'),
      ),
    );
    expect((await store.loadSession(folder))!.coworker.dbId, 'card-1');
  });

  group('a session follows its own library card', () {
    final miraA = CharacterCard(name: 'Mira', personality: 'A')..dbId = 'a';
    final miraB = CharacterCard(name: 'Mira', personality: 'B')..dbId = 'b';

    test('two cards with the same name: the id picks the right one', () {
      final saved = CharacterCard(name: 'Mira')..dbId = 'b';
      expect(waifuFindCard([miraA, miraB], saved), same(miraB));
    });

    test('a renamed card is still found by its id', () {
      final renamed = CharacterCard(name: 'Mira Two')..dbId = 'a';
      final saved = CharacterCard(name: 'Mira')..dbId = 'a';
      expect(waifuFindCard([miraB, renamed], saved), same(renamed));
    });

    test('a deleted card does not fall back to a namesake', () {
      final saved = CharacterCard(name: 'Mira')..dbId = 'gone';
      expect(waifuFindCard([miraA, miraB], saved), isNull);
    });

    test('a session saved before ids still matches by name', () {
      expect(waifuFindCard([miraA], CharacterCard(name: 'Mira')), same(miraA));
    });

    test('the wizard highlights only the picked card', () {
      expect(waifuSameCard(miraA, miraB), isFalse);
      expect(
        waifuSameCard(miraA, CharacterCard(name: 'Mira')..dbId = 'a'),
        isTrue,
      );
      expect(waifuSameCard(miraA, CharacterCard(name: 'Mira')), isTrue);
    });
  });
}
