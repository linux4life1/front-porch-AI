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

// U7's wire-format contract: the typed wrapper must be INVISIBLE on disk.
//
// GroupMemberRealism replaced the untyped per-member map, and it ships with
// NO data migration on purpose: three persistence paths (the sessions
// column's perChar, the group's defaultMemberRealismState, Group Card
// exports) all keep the exact legacy JSON, so old builds read new data and a
// rollback reads it too. That promise only holds while three properties do:
//
//   1. fromJson → toJson is IDENTITY on a full live slot — including the
//      ~22 config/seed keys the wrapper has no typed accessor for. (The
//      wiring E2E captured a real 41-key slot; the fixture below is that
//      shape.)
//   2. ABSENT keys stay absent. Key presence is meaning in this format —
//      a `needs` map appearing in a slot is precisely what flags Needs
//      enabled for the whole group on the next load. A wrapper that emitted
//      defaults would silently switch features on.
//   3. Legacy-tolerant coercion matches the old call sites: JSON numbers
//      (always doubles off some encoders) still read as ints, nested maps
//      re-type cleanly, and garbage shapes read as null rather than throw.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/group_member_realism.dart';

/// The shape the wiring E2E observed on a real scored slot (values varied).
const _fullSlot = <String, dynamic>{
  'affection': 26,
  'longTermScore': 4,
  'trust': 2,
  'fixation': '',
  'fixationLifespan': 0,
  'spatialStance': 'standing',
  'relationshipTier': 2,
  'longTermTier': 0,
  'turnsSinceLongTermCheck': 1,
  'shortTermDeltasSummary': 26,
  'turnsSinceDecayCheck': 2,
  'arousal': 0,
  'nsfwCooldownEnabled': false,
  'cooldownTurnsRemaining': 0,
  'cooldownTurnsTotal': 0,
  'emotion': 'happy',
  'emotionIntensity': 'moderate',
  'needs': {
    'hunger': 72,
    'bladder': 74,
    'energy': 76,
    'social': 90,
    'fun': 91,
    'hygiene': 80,
    'comfort': 84,
  },
  'relationships': {'member_1': 0},
  // The config/seed keys the wrapper has no accessors for — pass-through.
  'timeOfDay': 'morning',
  'dayCount': 1,
  'enjoysLowHygiene': false,
  'needsDirectorAuthority': false,
  'needsPace': 'normal',
  'verificationEnabled': false,
  'verificationMaxReprocesses': 1,
  'verificationStrictness': 1,
  'needsBaselineHunger': 80,
  'needsBaselineBladder': 80,
  'needsBaselineEnergy': 80,
  'needsBaselineSocial': 80,
  'needsBaselineFun': 80,
  'needsBaselineHygiene': 80,
  'needsBaselineComfort': 80,
};

void main() {
  group('the typed wrapper is invisible on disk', () {
    test('fromJson -> toJson is identity on a full 41-key live slot', () {
      // Through a REAL encode/decode cycle, not object equality games.
      final decoded = jsonDecode(jsonEncode(_fullSlot)) as Map;
      final roundTripped = jsonDecode(
        jsonEncode(GroupMemberRealism.fromJson(decoded)),
      );
      expect(
        roundTripped,
        jsonDecode(jsonEncode(_fullSlot)),
        reason:
            'any key or value the wrapper drops or reshapes here is data '
            'loss in all three persistence paths at once',
      );
    });

    test('absent keys stay absent — presence is meaning in this format', () {
      final sparse = GroupMemberRealism.fromJson(const {'affection': 10});
      final out = sparse.toJson();
      expect(out.keys.toList(), ['affection']);
      expect(
        out.containsKey('needs'),
        isFalse,
        reason:
            'a needs key appearing from nowhere would flag Needs as '
            'enabled for the whole group on the next load',
      );

      // And writing through a typed setter creates exactly that one key.
      sparse.trust = 5;
      expect(sparse.toJson().keys.toSet(), {'affection', 'trust'});
    });

    test('JSON doubles read as ints, exactly like the old call-site casts', () {
      final m = GroupMemberRealism.fromJson(const {
        'affection': 26.0,
        'trust': 2.0,
        'needs': {'hunger': 72.0},
      });
      expect(m.affection, 26);
      expect(m.trust, 2);
      expect(m.needs, {'hunger': 72});
    });

    test('garbage shapes read as null, never throw', () {
      final m = GroupMemberRealism.fromJson(const {
        'affection': 'not a number',
        'needs': 'not a map',
        'relationships': 7,
        'nsfwCooldownEnabled': 'true',
      });
      expect(m.affection, isNull);
      expect(m.needs, isNull);
      expect(m.relationships, isNull);
      expect(m.nsfwCooldownEnabled, isNull);
    });

    test('the generic bridge only accepts known runtime keys', () {
      final m = GroupMemberRealism();
      expect(
        () => m.setValue('brand_new_key', 1),
        throwsA(isA<AssertionError>()),
        reason:
            'stringly access creeping back in is exactly what U7 removed; '
            'new keys get named in GroupRealismKeys first',
      );
      m.setValue(GroupRealismKeys.turnsSinceDecayCheck, 7);
      expect(m.valueFor(GroupRealismKeys.turnsSinceDecayCheck), 7);
    });

    test('the REAL encode site shape: jsonEncode sees through the wrapper', () {
      // The sessions save writes jsonEncode({'perChar': _groupRealism, ...})
      // and relies on jsonEncode calling toJson() implicitly — a path the
      // analyzer cannot type-check. Grok's review flagged that the round-trip
      // test above never exercised it; this does, wrapper-in-map and all.
      final wrapped = {
        'perChar': {'member_0': GroupMemberRealism.fromJson(_fullSlot)},
      };
      final decoded = jsonDecode(jsonEncode(wrapped)) as Map<String, dynamic>;
      expect(
        (decoded['perChar'] as Map)['member_0'],
        jsonDecode(jsonEncode(_fullSlot)),
        reason: 'the sessions column would silently store the wrong shape',
      );
    });

    test('deep unknown maps do not alias the decoder output either', () {
      // Known slots nest one level (needs/relationships), but pass-through
      // keys from imports may nest deeper. Grok's review proved the old
      // one-level copy left depth>=2 aliased; fromJson now copies recursively.
      final source =
          jsonDecode('{"importedConfig": {"outer": {"inner": 1}}}') as Map;
      final m = GroupMemberRealism.fromJson(source);
      ((m.toJson()['importedConfig'] as Map)['outer'] as Map)['inner'] = 999;
      expect(
        ((source['importedConfig'] as Map)['outer'] as Map)['inner'],
        1,
        reason: 'a depth-2 write leaked back into the decoded JSON',
      );
    });

    test('fromJson deep-copies: mutating the wrapper never aliases the '
        'decoder output', () {
      final source = jsonDecode(jsonEncode(_fullSlot)) as Map;
      final m = GroupMemberRealism.fromJson(source);
      m.affection = 999;
      expect(
        source['affection'],
        26,
        reason:
            'the wrapper must own its data — writes leaking back into '
            'the decoded JSON would corrupt sibling readers',
      );
    });
  });
}
