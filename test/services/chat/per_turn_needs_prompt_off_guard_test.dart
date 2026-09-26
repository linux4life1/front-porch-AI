// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A2 guard (/workspace/sow/rn-spec.md AMENDMENT 1): the per-turn (live) needs
// eval prompt leaves out the speaker's needsOff keys. Rawhide already does
// this (needs_impact_evaluator.dart:135 uses needsThatAreOn); the pin keeps
// the reprocess fix from regressing the live path it borrows from. Expected
// GREEN before and after the fix.

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
    'A2 guard: 1:1 with Hygiene+Fun off: the live eval asks only the 5 enabled '
    'needs',
    () async {
      await h.oneToOneWithStampedReply(
        needsCard('Mara', needsOff: ['hygiene', 'fun']),
      );
      final live = h.llm.liveNeedsPrompts.where(
        (p) => askedDeltaKeys(p).isNotEmpty,
      );
      expect(live, isNotEmpty);
      for (final p in live) {
        expect(askedDeltaKeys(p), {
          'hunger',
          'bladder',
          'energy',
          'social',
          'comfort',
        });
      }
    },
  );

  test(
    'A2 guard: group: Ayla (Social off) live prompt has no social, Bram\'s does',
    () async {
      await h.groupWithTwoReplies();
      final asked = h.llm.liveNeedsPrompts
          .map(askedDeltaKeys)
          .where((k) => k.isNotEmpty)
          .toList();
      expect(asked, hasLength(2));
      expect(asked[0], kAllNeeds.toSet().difference({'social'}));
      expect(asked[1], kAllNeeds.toSet());
    },
  );
}
