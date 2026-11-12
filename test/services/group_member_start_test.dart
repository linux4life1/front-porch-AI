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

// A group's new chats start each member from the member's own copy
// (docs/design/group-editor.md A5). An older group's stored start was moved
// onto the copies once, by the v67 upgrade; after that only the copy counts.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/doors/entry/group_start_seeds.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A group whose new chats start Ana (with a seed) and not Bo (none).
final _blob = buildGroupRealismBlobs(
  seeds: {
    'ana': {
      ...defaultGroupMemberRealismSeed(),
      'affection': 61,
      'longTermScore': 70,
      'trust': 40,
      'emotion': 'joyful',
    },
  },
  needsEnabled: true,
  timeOfDay: 'morning',
  dayCount: 1,
);

FrontPorchExtensions _ext(String? json) => json == null
    ? FrontPorchExtensions()
    : FrontPorchExtensions.fromJson(jsonDecode(json) as Map<String, dynamic>);

void main() {
  group('the upgrade moves a stored start onto the member copy', () {
    test('a member with a seed keeps Realism and their start; one the blob '
        'does not name starts from the default seed with Realism on, as a '
        'group with any seed ran its whole cast', () {
      final ana = memberCopyFromGroupSeed(
        FrontPorchExtensions(),
        _blob.defaultMemberJson,
        'ana',
      );
      expect(ana.realismEnabled, isTrue);
      expect((ana.shortTermBond, ana.longTermBond), (61, 70));
      expect(ana.characterEmotion, 'joyful');
      final bo = memberCopyFromGroupSeed(
        FrontPorchExtensions(realismEnabled: true),
        _blob.defaultMemberJson,
        'bo',
      );
      expect(
        bo.realismEnabled,
        isTrue,
        reason: 'a group storing any seed switched Realism on for every member',
      );
      expect(
        (bo.shortTermBond, bo.longTermBond),
        isNot((61, 70)),
        reason: 'Bo does not take Ana\'s start',
      );
    });

    test('a member keyed by their avatar basename (older libraries) keeps '
        'their start', () {
      final legacy = buildGroupRealismBlobs(
        seeds: {
          'Ana': {...defaultGroupMemberRealismSeed(), 'affection': 35},
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      final ana = memberCopyFromGroupSeed(
        FrontPorchExtensions(),
        legacy.defaultMemberJson,
        'mem-ana',
        legacyId: 'Ana',
      );
      expect((ana.realismEnabled, ana.shortTermBond), (true, 35));
    });

    test('a group that started without Realism leaves every member off', () {
      final ext = memberCopyFromGroupSeed(
        FrontPorchExtensions(realismEnabled: true),
        '{}',
        'ana',
      );
      expect(ext.realismEnabled, isFalse);
    });

    test('the group-wide Afterglow and Pockets defaults, when off, land on '
        'the copy', () {
      final json = jsonEncode({
        ...jsonDecode(_blob.defaultMemberJson) as Map,
        kGroupAfterglowKey: false,
        kGroupPocketsKey: false,
      });
      final ana = memberCopyFromGroupSeed(FrontPorchExtensions(), json, 'ana');
      expect((ana.afterglowEnabled, ana.pocketsEnabled), (false, false));
    });

    test('it runs once over a real library and running it again changes '
        'nothing', () async {
      final db = AppDatabase.forTesting(sameIsolate: true);
      addTearDown(db.close);
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'g',
          name: 'Pair',
          defaultMemberRealismState: Value(_blob.defaultMemberJson),
        ),
      );
      for (final id in ['ana', 'bo']) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: id,
            groupId: 'g',
            name: id,
            frontPorchExtensions: Value(
              jsonEncode(FrontPorchExtensions(realismEnabled: true).toJson()),
            ),
          ),
        );
      }
      Future<List<String?>> read() async => [
        for (final r in await db.getGroupMembers('g')) r.frontPorchExtensions,
      ];
      await migrateGroupSeedsToMemberCopies(db);
      final once = await read();
      expect(_ext(once[0]).realismEnabled, isTrue);
      expect(_ext(once[1]).realismEnabled, isTrue);
      expect(_ext(once[0]).shortTermBond, 61);
      await migrateGroupSeedsToMemberCopies(db);
      expect(await read(), once);
    });
  });

  group('a new chat starts members from their copies only', () {
    GroupChat group() => GroupChat(
      id: 'g',
      name: 'Pair',
      defaultMemberRealismState: _blob.defaultMemberJson,
    );

    CharacterCard card(String id, FrontPorchExtensions ext) =>
        CharacterCard(name: id)
          ..dbId = id
          ..frontPorchExtensions = ext;

    test('Realism on or off, bond and Needs come from the copy', () {
      final seeds = groupStartSeeds(group(), [
        card(
          'ana',
          FrontPorchExtensions(
            realismEnabled: true,
            shortTermBond: 12,
            needsSimEnabled: false,
          ),
        ),
        card('bo', FrontPorchExtensions()),
      ], groupMemberStoreId);
      expect(seeds.keys, ['ana'], reason: 'Bo has Realism off');
      expect(seeds['ana']!['affection'], 12);
      expect(seeds['ana']!.containsKey('needs'), isFalse);
    });

    test('a member edited back to the defaults stays at the defaults, '
        'whatever the old stored seed says', () {
      final seeds = groupStartSeeds(group(), [
        card('ana', FrontPorchExtensions(realismEnabled: true)),
      ], groupMemberStoreId);
      expect(seeds['ana']!['affection'], FrontPorchExtensions().shortTermBond);
      expect(seeds['ana']!['emotion'], isNot('joyful'));
    });

    test('every place that seeds a chat reads the copies', () {
      for (final f in [
        'lib/services/chat/doors/entry/group_entry.dart',
        'lib/services/chat/doors/session/new_chat.dart',
        'lib/services/chat/doors/session/session_seed.dart',
        'lib/services/chat/doors/session/walk_back.dart',
        'lib/services/chat/doors/cast/greeting_picker.dart',
      ]) {
        expect(
          File(f).readAsStringSync(),
          anyOf(contains('groupStartMembers('), contains('groupStartSeeds(')),
          reason: '$f seeds a group chat',
        );
      }
    });
  });
}
