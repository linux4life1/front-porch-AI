// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

@Tags(["golden"])
@TestOn("linux")
library;

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:front_porch_ai/services/backporch/backporch.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_card_comments.dart";

import "../support/golden_app.dart";

final _now = DateTime.utc(2026, 8, 17, 12);

BackporchUser _user({bool verified = true, bool known = true}) => BackporchUser(
  id: "u1",
  email: "a@b.c",
  displayName: "Tester",
  role: "USER",
  ageVerified: true,
  emailVerified: verified,
  emailVerifiedKnown: known,
  nsfwEnabled: false,
  acceptedPolicyVersion: "1.0",
  twoFactorEnabled: false,
);

StoopComment _c({
  required String id,
  required String authorId,
  required String name,
  required String body,
  required DateTime createdAt,
  bool deleted = false,
  StoopCommentReply? reply,
}) => StoopComment(
  id: id,
  cardId: "card1",
  authorId: authorId,
  displayName: name,
  createdAt: createdAt,
  body: deleted ? "" : body,
  deleted: deleted,
  reply: reply,
);

StoopCommentReply _r({
  required String authorId,
  required String name,
  required String body,
  required DateTime createdAt,
  bool deleted = false,
}) => StoopCommentReply(
  authorId: authorId,
  displayName: name,
  createdAt: createdAt,
  body: deleted ? "" : body,
  deleted: deleted,
);

Widget _block({
  BackporchUser? user,
  List<StoopComment> seed = const [],
  String? cardOwnerId,
}) => SizedBox(
  width: 400,
  child: StoopCardComments(
    cardId: "card1",
    cardOwnerId: cardOwnerId,
    user: user,
    client: MemoryStoopCommentsClient(seed: seed, now: () => _now),
    now: () => _now,
  ),
);

void main() {
  testWidgets("Discussion — guest", (tester) async {
    await expectThemedGoldens(
      tester,
      child: _block(user: null),
      group: "discussion",
      name: "guest",
      surface: const Size(440, 220),
    );
  });

  testWidgets("Discussion — unverified", (tester) async {
    await expectThemedGoldens(
      tester,
      child: _block(user: _user(verified: false)),
      group: "discussion",
      name: "unverified",
      surface: const Size(440, 220),
    );
  });

  testWidgets("Discussion — verified empty list", (tester) async {
    await expectThemedGoldens(
      tester,
      child: _block(user: _user()),
      group: "discussion",
      name: "verified_empty",
      surface: const Size(440, 280),
      settle: false,
    );
  });

  testWidgets("Discussion — verified list with tombstone", (tester) async {
    await expectThemedGoldens(
      tester,
      child: _block(
        user: _user(),
        seed: [
          _c(
            id: "c1",
            authorId: "u2",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 5)),
          ),
          _c(
            id: "c2",
            authorId: "u3",
            name: "Bess",
            body: "gone",
            createdAt: _now.subtract(const Duration(hours: 2)),
            deleted: true,
          ),
        ],
      ),
      group: "discussion",
      name: "verified_list",
      surface: const Size(440, 360),
      settle: false,
    );
  });

  testWidgets("Discussion — owner thread (delete others, no report on own)", (
    tester,
  ) async {
    final owner = _user();
    await expectThemedGoldens(
      tester,
      child: _block(
        user: owner,
        cardOwnerId: owner.id,
        seed: [
          _c(
            id: "theirs",
            authorId: "u2",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 5)),
          ),
          _c(
            id: "mine",
            authorId: owner.id,
            name: owner.displayName,
            body: "Thanks Ada!",
            createdAt: _now.subtract(const Duration(minutes: 2)),
          ),
        ],
      ),
      group: "discussion",
      name: "owner_thread",
      surface: const Size(440, 460),
      settle: false,
    );
  });

  testWidgets("Discussion — owner can reply", (tester) async {
    final owner = _user();
    await expectThemedGoldens(
      tester,
      child: _block(
        user: owner,
        cardOwnerId: owner.id,
        seed: [
          _c(
            id: "theirs",
            authorId: "u2",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      group: "discussion",
      name: "owner_can_reply",
      surface: const Size(440, 360),
      settle: false,
    );
  });

  testWidgets("Discussion — visitor cannot reply", (tester) async {
    await expectThemedGoldens(
      tester,
      child: _block(
        user: _user(),
        cardOwnerId: "someone-else",
        seed: [
          _c(
            id: "theirs",
            authorId: "u2",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      group: "discussion",
      name: "visitor_cannot_reply",
      surface: const Size(440, 340),
      settle: false,
    );
  });

  testWidgets("Discussion — one reply max, glued under parent", (tester) async {
    final owner = _user();
    await expectThemedGoldens(
      tester,
      child: _block(
        user: owner,
        cardOwnerId: owner.id,
        seed: [
          _c(
            id: "newer",
            authorId: "u3",
            name: "Bess",
            body: "Nice work.",
            createdAt: _now.subtract(const Duration(minutes: 1)),
          ),
          _c(
            id: "older",
            authorId: "u2",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 10)),
            reply: _r(
              authorId: owner.id,
              name: owner.displayName,
              body: "Thank you!",
              createdAt: _now.subtract(const Duration(seconds: 20)),
            ),
          ),
        ],
      ),
      group: "discussion",
      name: "one_reply_max",
      surface: const Size(440, 480),
      settle: false,
    );
  });

  testWidgets("Discussion — deleted reply tombstone", (tester) async {
    final owner = _user();
    await expectThemedGoldens(
      tester,
      child: _block(
        user: owner,
        cardOwnerId: owner.id,
        seed: [
          _c(
            id: "theirs",
            authorId: "u2",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 5)),
            reply: _r(
              authorId: owner.id,
              name: owner.displayName,
              body: "gone",
              createdAt: _now.subtract(const Duration(minutes: 1)),
              deleted: true,
            ),
          ),
        ],
      ),
      group: "discussion",
      name: "deleted_reply_tombstone",
      surface: const Size(440, 400),
      settle: false,
    );
  });
}
