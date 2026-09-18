// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The growth_rings E2E stamps bond_delta 13 and waits for a Growth pass.
// Journal still fires via hasSalientEvent on the message. Growth must NOT
// re-read that window (cooldown bypass) — it waits on eventKickPending.
// If pending-metadata writes skip _writePendingRealismMetadata, the flag
// stays false and growthPassRequests sits at 0 for eight minutes.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  group('JournalPhysics.metadataIsSalient', () {
    test('the canned E2E bond_delta 13 is salient; a +1 trust is not', () {
      expect(
        JournalPhysics.metadataIsSalient({'bond_delta': 13, 'trust_delta': 1}),
        isTrue,
        reason:
            'fake relationship eval pays 13 — that is the growth_rings kick',
      );
      expect(JournalPhysics.metadataIsSalient({'trust_delta': 1}), isFalse);
      expect(JournalPhysics.metadataIsSalient(const {}), isFalse);
      expect(JournalPhysics.metadataIsSalient(null), isFalse);
    });

    test('trust repair and Chance Time stay salient on the pending map', () {
      expect(
        JournalPhysics.metadataIsSalient({'trust_repair_verdict': 'accepted'}),
        isTrue,
      );
      expect(
        JournalPhysics.metadataIsSalient({
          'chance_time_event': 'A stranger arrives',
        }),
        isTrue,
      );
    });
  });
}
