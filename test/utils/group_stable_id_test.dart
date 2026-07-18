// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/utils/group_stable_id.dart';

void main() {
  group('embed/read group stable id — the backend contract', () {
    test('embeds at extensions.front_porch.realism_engine.stable_id '
        '(the exact path the Stoop backend reads)', () {
      final ext = embedGroupStableId(null, 'grp-123');
      // This literal path mirrors backend cardStableId(): card.extensions
      // .front_porch.realism_engine.stable_id — must not drift.
      final fp = ext['front_porch'] as Map;
      final re = fp['realism_engine'] as Map;
      expect(re['stable_id'], 'grp-123');
    });

    test('preserves existing extension keys (realism_state) + prior front_porch',
        () {
      final ext = embedGroupStableId({
        'realism_state': {'alice': 1},
        'front_porch': {'other': true},
      }, 'grp-9');
      expect((ext['realism_state'] as Map)['alice'], 1);
      expect((ext['front_porch'] as Map)['other'], true);
      expect(
        ((ext['front_porch'] as Map)['realism_engine'] as Map)['stable_id'],
        'grp-9',
      );
    });

    test('read is the inverse of embed', () {
      expect(readGroupStableIdFromExtensions(embedGroupStableId(null, 'x')), 'x');
    });

    test('null / blank id is a no-op (nothing embedded, read returns null)', () {
      expect(readGroupStableIdFromExtensions(embedGroupStableId(null, null)),
          isNull);
      expect(readGroupStableIdFromExtensions(embedGroupStableId(null, '  ')),
          isNull);
    });

    test('read tolerates absent / malformed extensions', () {
      expect(readGroupStableIdFromExtensions(null), isNull);
      expect(readGroupStableIdFromExtensions({}), isNull);
      expect(readGroupStableIdFromExtensions({'front_porch': 'nope'}), isNull);
      expect(
        readGroupStableIdFromExtensions({
          'front_porch': {'realism_engine': {}},
        }),
        isNull,
      );
    });

    test('embed does not mutate the caller\'s extensions map', () {
      final original = <String, dynamic>{'realism_state': {}};
      embedGroupStableId(original, 'y');
      expect(original.containsKey('front_porch'), isFalse);
    });
  });

  group('Group Card round-trip (the real export→import transport)', () {
    test('stable id survives GroupCard.toJson → fromJson and is recoverable '
        'at the backend path', () {
      // A card as the exporter builds it: extensions carry the group stable id
      // (embedded exactly as _buildExtensions does).
      final card = GroupCard(
        name: 'The Crew',
        turnOrder: 'roundRobin',
        members: [
          CharacterCard(name: 'Alice'),
          CharacterCard(name: 'Bob'),
        ],
        extensions: embedGroupStableId(
          {'realism_state': {'seed': 1}},
          'group-stable-abc',
        ),
      );

      // Transport: serialize (upload/export) → deserialize (import).
      final json = card.toJson();

      // What the Stoop backend receives as `card.extensions...stable_id`.
      final ext = json['extensions'] as Map<String, dynamic>;
      expect(readGroupStableIdFromExtensions(ext), 'group-stable-abc');

      // What the importer sees after parsing the card back.
      final parsed = GroupCard.fromJson(json);
      expect(
        readGroupStableIdFromExtensions(parsed.extensions),
        'group-stable-abc',
      );
    });

    test('GroupChat model carries stableId through its own toJson/fromJson', () {
      final g = GroupChat(id: 'group_1', name: 'X', stableId: 'sid-1');
      final back = GroupChat.fromJson(g.toJson());
      expect(back.stableId, 'sid-1');

      // Absent stable id stays null (older groups / cards).
      final noId = GroupChat.fromJson(
        GroupChat(id: 'group_2', name: 'Y').toJson(),
      );
      expect(noId.stableId, isNull);
    });
  });
}
