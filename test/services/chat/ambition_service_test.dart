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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

void main() {
  group('AmbitionService.parseAdvance (forgiving verdict floor)', () {
    test('NONE / garbage / out-of-range → null', () {
      expect(AmbitionService.parseAdvance('NONE', 3), isNull);
      expect(AmbitionService.parseAdvance('none, nothing here', 3), isNull);
      expect(AmbitionService.parseAdvance(null, 3), isNull);
      expect(AmbitionService.parseAdvance('definitely!', 3), isNull);
      expect(AmbitionService.parseAdvance('7 solid', 3), isNull);
      expect(AmbitionService.parseAdvance('0 major', 3), isNull);
    });

    test('accepts the format with punctuation/case noise', () {
      expect(AmbitionService.parseAdvance('2 solid', 3), (2, 20));
      expect(AmbitionService.parseAdvance('1: MAJOR', 3), (1, 35));
      expect(AmbitionService.parseAdvance('3 - small.', 3), (3, 10));
      expect(
        AmbitionService.parseAdvance('Answer: 2 solid step forward', 3),
        (2, 20),
      );
    });
  });

  group('AmbitionService.stageWord', () {
    test('banded words only', () {
      expect(AmbitionService.stageWord(0), 'just beginning');
      expect(AmbitionService.stageWord(30), 'gaining ground');
      expect(AmbitionService.stageWord(55), 'halfway there');
      expect(AmbitionService.stageWord(80), 'nearly there');
      expect(AmbitionService.stageWord(100), 'achieved');
    });
  });

  group('AmbitionService.onQuestAchieved (in-memory DB round trip)', () {
    late AppDatabase db;
    late JournalStore journal;
    late GrowthStore growth;
    const sid = 's1';
    const cid = 'c1';

    setUp(() {
      db = AppDatabase.forTesting();
      journal = JournalStore(getDb: () => db);
      growth = GrowthStore(getDb: () => db);
    });
    tearDown(() async => db.close());

    AmbitionService svc(String? verdict, {void Function()? onWaypoint}) =>
        AmbitionService(
          journalStore: journal,
          growthStore: growth,
          fireEval: (_) async => verdict,
          getMaxCards: () => 30,
          onWaypoint: onWaypoint,
        );

    Future<Map<String, dynamic>> ambitionMeta() async {
      for (final card in await journal.cardsFor(sid, cid)) {
        final meta =
            jsonDecode(card.metadata ?? '{}') as Map<String, dynamic>;
        if (meta['kind'] == 'ambition') return meta;
      }
      return const {};
    }

    test('a solid advance creates the progress card at 20', () async {
      await svc('1 solid').onQuestAchieved(
        sessionId: sid,
        characterId: cid,
        characterName: 'Alice',
        objectiveText: 'saved enough for the oven',
        ambitions: const ['open my own bakery'],
      );
      final meta = await ambitionMeta();
      expect(meta['ambition'], 'open my own bakery');
      expect(meta['progress'], 20);
    });

    test('crossing 25 plants a waypoint milestone card + fires the kick',
        () async {
      var kicked = false;
      final s = svc('1 solid', onWaypoint: () => kicked = true);
      for (var i = 0; i < 2; i++) {
        await s.onQuestAchieved(
          sessionId: sid,
          characterId: cid,
          characterName: 'Alice',
          objectiveText: 'step $i',
          ambitions: const ['open my own bakery'],
        );
      }
      expect((await ambitionMeta())['progress'], 40);
      expect(kicked, isTrue);
      final kinds = [
        for (final c in await journal.cardsFor(sid, cid))
          (jsonDecode(c.metadata ?? '{}') as Map)['kind'],
      ];
      expect(kinds, contains('milestone'));
    });

    test('reaching 100 plants the growth ring + achieved card', () async {
      final s = svc('1 major');
      for (var i = 0; i < 3; i++) {
        await s.onQuestAchieved(
          sessionId: sid,
          characterId: cid,
          characterName: 'Alice',
          objectiveText: 'leap $i',
          ambitions: const ['open my own bakery'],
        );
      }
      expect((await ambitionMeta())['progress'], 100);
      final rings = await growth.ringsFor(sid, cid);
      expect(rings.map((r) => r.content).join(), contains('bakery'));
      // Achieved → excluded from further eval prompts (open list empty).
      await s.onQuestAchieved(
        sessionId: sid,
        characterId: cid,
        characterName: 'Alice',
        objectiveText: 'post-achievement quest',
        ambitions: const ['open my own bakery'],
      );
      expect((await ambitionMeta())['progress'], 100);
    });

    test('NONE verdict changes nothing', () async {
      await svc('NONE').onQuestAchieved(
        sessionId: sid,
        characterId: cid,
        characterName: 'Alice',
        objectiveText: 'unrelated errand',
        ambitions: const ['open my own bakery'],
      );
      expect(await ambitionMeta(), isEmpty);
    });
  });
}
