// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-turn group Needs chip filters by the SENDER's card
// (/workspace/sow/rn-spec.md AMENDMENT 2 item 9, CoS ruling 15:15 PT; capped
// at chat_service_group_realism_helpers.dart:408-412). On Rawhide that block
// strips the chip with _activeCharacter's needsOff, so a member with Social ON
// loses the social chip whenever the active character has Social OFF.
// Exactly one pin, by scope. Real ChatService + drift DB + scripted model.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/reprocess_needs_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
  });
  tearDown(() => h.dispose());

  test(
    'group: Bram (Social on) moved social in a normal turn while Ayla '
    '(active, Social off): Bram\'s per-turn needs_deltas chip keeps social',
    () async {
      final (_, b) = await h.groupWithTwoReplies(aOff: ['social'], bOff: []);
      expect(
        h.chat.activeCharacter?.name,
        'Ayla',
        reason: 'precondition: the active character is the Social-off one',
      );
      final md = h.chat.messages[b].activeMetadata!;
      final pre = Map<String, dynamic>.from(md['needs_pre_turn_vector'] as Map);
      final vec = Map<String, dynamic>.from(
        ((md['realism_state'] as Map)['needs'] as Map)['vector'] as Map,
      );
      expect(
        vec['social'],
        isNot(pre['social']),
        reason: 'precondition: Bram\'s social value moved this turn',
      );
      final chip = (md['needs_deltas'] as Map).keys.map((k) => '$k').toSet();
      expect(chip, contains('social'));
    },
  );
}
