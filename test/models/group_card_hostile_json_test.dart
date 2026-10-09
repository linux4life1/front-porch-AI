// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// GroupCard.fromJson against a HOSTILE card.
//
// Both Stoop download paths — stoop_card_detail_page and the web facade's
// stoop relay — hand a stranger's downloaded card straight to this factory.
// Every `as` cast in it is therefore a crash waiting for one wrong-typed
// field: `"turn_order": []` threw
//   type 'List<dynamic>' is not a subtype of type 'String'
// out of the factory and took the whole download down with it, on a card the
// user had merely tapped "Add to my library" on.
//
// The rule these guard: ONE BAD FIELD COSTS THAT FIELD. Never the download.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';

void main() {
  Map<String, dynamic> card(Map<String, dynamic> overrides) => {
    'name': 'The Tuesday Club',
    'members': [
      {'name': 'Rosalie'},
    ],
    'turn_order': 'random',
    ...overrides,
  };

  group('GroupCard.fromJson survives wrong-typed fields', () {
    test('a well-formed card still parses exactly as before', () {
      final g = GroupCard.fromJson(card(const {}));
      expect(g.name, 'The Tuesday Club');
      expect(g.turnOrder, 'random');
      expect(g.members.single.name, 'Rosalie');
    });

    test('a list turn_order falls back instead of throwing', () {
      // The reported crash, verbatim.
      final g = GroupCard.fromJson(card(const {'turn_order': []}));
      expect(g.turnOrder, 'roundRobin');
    });

    test('turn_order of any other wrong type falls back too', () {
      for (final bad in <Object>[
        42,
        true,
        <String, dynamic>{'a': 'b'},
      ]) {
        expect(
          GroupCard.fromJson(card({'turn_order': bad})).turnOrder,
          'roundRobin',
          reason: 'turn_order: $bad',
        );
      }
    });

    test('the other text fields on that same call are just as exposed', () {
      final g = GroupCard.fromJson(
        card(const {
          'name': ['not', 'a', 'name'],
          'first_message': 7,
          'scenario': {'nested': true},
          'system_prompt': false,
        }),
      );
      expect(g.name, 'Group');
      expect(g.firstMessage, '');
      expect(g.scenario, '');
      expect(g.systemPrompt, '');
    });

    test('wrong-typed switches fall back to their defaults', () {
      final g = GroupCard.fromJson(
        card(const {
          'auto_advance': 'yes',
          'director_mode': 1,
          'inherit_character_lorebooks': 'no',
          'chaos_mode_enabled': [],
          'chaos_nsfw_enabled': 'true',
        }),
      );
      expect(g.autoAdvance, isFalse);
      expect(g.directorMode, isFalse);
      expect(g.inheritCharacterLorebooks, isFalse, reason: 'default is off');
      expect(g.chaosModeEnabled, isFalse);
      expect(g.chaosNsfwEnabled, isFalse);
    });

    test('wrong-typed list fields yield empty lists, not a crash', () {
      final g = GroupCard.fromJson(
        card(const {
          'members': 'not a list',
          'raw_member_data': {'not': 'a list'},
          'world_ids': 'nope',
          'world_names': 42,
        }),
      );
      expect(g.members, isEmpty);
      expect(g.rawMemberData, isEmpty);
      expect(g.worldIds, isEmpty);
      expect(g.worldNames, isEmpty);
    });

    test('a member whose nested data block is wrong-typed is still named', () {
      final g = GroupCard.fromJson(
        card(const {
          'members': [
            {'data': 'not a map'},
            {
              'name': ['not a name'],
            },
            {'name': 'Edwin'},
          ],
        }),
      );
      expect(g.members.map((m) => m.name), ['Unknown', 'Unknown', 'Edwin']);
    });

    test('a malformed member_objectives blob costs only the objectives', () {
      final g = GroupCard.fromJson(
        card(const {
          'member_objectives': {
            'char_a': 'not a list',
            'char_b': [
              'not a map',
              {'objective': 'water the ferns'},
            ],
          },
        }),
      );
      expect(g.memberObjectives['char_a'], isEmpty);
      expect(g.memberObjectives['char_b'], [
        {'objective': 'water the ferns'},
      ]);
      expect(g.name, 'The Tuesday Club', reason: 'the rest of the card lived');
    });
  });
}
