// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Distill is supposed to keep injecting the legacy personality blob until
// starter rings actually land. Review-first Apply with every add unchecked
// still threw the blob away. Injection then had neither blob nor rings.
//
// Proven red: with `if (owner.distilled)` (no adds > 0), the blob is gone.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  late AppDatabase db;
  late GrowthStore store;
  late GrowthReview review;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    store = GrowthStore(getDb: () => db);
    review = GrowthReview(
      store: store,
      getSessionId: () => 's1',
      getIsGroup: () => false,
      onApplied: () async {},
      onNotify: () {},
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 's1',
        evolvedPersonality: const Value('Wry, guarded, loyal.'),
      ),
    );
    await store.refresh('s1', charIds: ['mira'], activeCharId: 'mira');
  });

  tearDown(() async => db.close());

  test('rejecting every distill add keeps the legacy blob', () async {
    expect(store.legacyBlobFor('s1', 'mira'), isNotNull);
    final op = GrowthProposedOp(
      action: GrowthOpAction.add,
      text: 'She started leaving the porch light on.',
    )..accepted = false;
    await review.applyOwnerProposals(
      's1',
      GrowthOwnerProposals(
        ownerId: 'mira',
        ownerName: 'Mira',
        ops: [op],
        distilled: true,
      ),
    );
    expect(
      store.legacyBlobFor('s1', 'mira'),
      isNotNull,
      reason: 'no starter ring landed — keep injecting the blob',
    );
    expect(await store.ringsFor('s1', 'mira'), isEmpty);
  });

  test('accepting a distill add archives the blob', () async {
    await review.applyOwnerProposals(
      's1',
      GrowthOwnerProposals(
        ownerId: 'mira',
        ownerName: 'Mira',
        ops: [
          GrowthProposedOp(
            action: GrowthOpAction.add,
            text: 'She started leaving the porch light on.',
          ),
        ],
        distilled: true,
      ),
    );
    expect(store.legacyBlobFor('s1', 'mira'), isNull);
    expect(await store.ringsFor('s1', 'mira'), isNotEmpty);
  });
}
