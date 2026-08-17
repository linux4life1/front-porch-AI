// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Widget tests that PUMP the real Discussion block.

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";

import "package:front_porch_ai/providers/auth_state.dart";
import "package:front_porch_ai/services/backporch/backporch.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_card_comments.dart";
import "package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart";

final _now = DateTime.utc(2026, 8, 17, 12);

BackporchUser _user({
  bool verified = true,
  bool known = true,
  String id = "u1",
  String name = "Tester",
  String? pendingEmail,
}) => BackporchUser(
  id: id,
  email: "a@b.c",
  displayName: name,
  role: "USER",
  ageVerified: true,
  emailVerified: verified,
  emailVerifiedKnown: known,
  nsfwEnabled: false,
  acceptedPolicyVersion: "1.0",
  twoFactorEnabled: false,
  pendingEmail: pendingEmail,
);

StoopComment _comment({
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

StoopCommentReply _reply({
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

Future<void> _pump(
  WidgetTester tester, {
  BackporchUser? user,
  MemoryStoopCommentsClient? client,
  String? cardOwnerId,
  bool canModerate = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StoopCardComments(
            cardId: "card1",
            cardOwnerId: cardOwnerId,
            user: user,
            client: client ?? MemoryStoopCommentsClient(now: () => _now),
            canModerate: canModerate,
            now: () => _now,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpHost(
  WidgetTester tester, {
  BackporchUser? user,
  MemoryStoopCommentsClient? client,
  String? cardOwnerId,
  bool commentsEnabled = false,
  StoopCommentsOptIn? store,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StoopCardDiscussionSection(
            cardId: "card1",
            cardOwnerId: cardOwnerId,
            user: user,
            client: client ?? MemoryStoopCommentsClient(now: () => _now),
            commentsEnabled: commentsEnabled,
            optInStore: store ?? StoopCommentsOptIn(),
            now: () => _now,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("1. guest: Sign in to comment, no TextField / Post", (
    tester,
  ) async {
    await _pump(tester, user: null);
    expect(find.text("Sign in to comment."), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("Post"), findsNothing);
    expect(find.text("Confirm email to comment."), findsNothing);
    expect(find.text("Discussion"), findsOneWidget);
  });

  testWidgets("2a. unverified false: Confirm email, no composer", (
    tester,
  ) async {
    await _pump(tester, user: _user(verified: false));
    expect(find.text("Confirm email to comment."), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("Post"), findsNothing);
  });

  testWidgets("2b. omitted emailVerified: Confirm email, no composer", (
    tester,
  ) async {
    final omitted = BackporchUser.fromJson({
      "id": "u1",
      "email": "a@b.c",
      "displayName": "Tester",
      "role": "USER",
      "ageVerified": true,
      "nsfwEnabled": false,
      "acceptedPolicyVersion": "1.0",
      "twoFactorEnabled": false,
    });
    await _pump(tester, user: omitted);
    expect(find.text("Confirm email to comment."), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("Post"), findsNothing);
  });

  testWidgets("3. verified: composer + Post present", (tester) async {
    await _pump(tester, user: _user());
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text("Post"), findsOneWidget);
    expect(find.text("Sign in to comment."), findsNothing);
    expect(find.text("Confirm email to comment."), findsNothing);
  });

  testWidgets("4. 1000-char cap on the field", (tester) async {
    await _pump(tester, user: _user());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 1000);
    expect(find.text("0/1000"), findsNothing);
    await tester.enterText(find.byType(TextField), "x" * 1005);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      1000,
    );
    expect(find.text("1000/1000"), findsOneWidget);
  });

  testWidgets("4b. counter hidden until last 100 chars", (tester) async {
    await _pump(tester, user: _user());
    expect(find.text("0/1000"), findsNothing);
    await tester.enterText(find.byType(TextField), "x" * 899);
    await tester.pump();
    expect(find.text("899/1000"), findsNothing);
    await tester.enterText(find.byType(TextField), "x" * 900);
    await tester.pump();
    expect(find.text("900/1000"), findsOneWidget);
  });

  testWidgets("5. newest-first list order", (tester) async {
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "old",
          authorId: "a",
          name: "oldie",
          body: "older body",
          createdAt: _now.subtract(const Duration(hours: 2)),
        ),
        _comment(
          id: "new",
          authorId: "b",
          name: "newbie",
          body: "newer body",
          createdAt: _now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    await _pump(tester, user: _user(), client: client);
    final newer = tester.getTopLeft(find.text("newer body"));
    final older = tester.getTopLeft(find.text("older body"));
    expect(newer.dy, lessThan(older.dy));
  });

  testWidgets("6. 409 duplicate keeps draft in the composer", (tester) async {
    final client = MemoryStoopCommentsClient(now: () => _now)
      ..nextCreateError = const BackporchApiException(409, "duplicate_comment");
    await _pump(tester, user: _user(), client: client);
    await tester.enterText(find.byType(TextField), "hello porch");
    await tester.pump();
    await tester.tap(find.text("Post"));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      "hello porch",
    );
    expect(find.text("You already posted that."), findsOneWidget);
  });

  testWidgets("7. rate-limit keeps draft", (tester) async {
    final client = MemoryStoopCommentsClient(now: () => _now)
      ..nextCreateError = const BackporchApiException(429, "too_many_comments");
    await _pump(tester, user: _user(), client: client);
    await tester.enterText(find.byType(TextField), "keep me");
    await tester.pump();
    await tester.tap(find.text("Post"));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      "keep me",
    );
    expect(find.textContaining("commenting too fast"), findsOneWidget);
  });

  testWidgets("8. delete to tombstone row still present, body gone", (
    tester,
  ) async {
    final me = _user();
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "mine",
          authorId: me.id,
          name: me.displayName,
          body: "please remove this",
          createdAt: _now.subtract(const Duration(minutes: 2)),
        ),
      ],
    );
    await _pump(tester, user: me, client: client);
    expect(find.text("please remove this"), findsOneWidget);
    await tester.tap(find.byKey(const Key("stoop-comment-delete-mine")));
    await tester.pumpAndSettle();
    expect(find.text("Delete comment?"), findsOneWidget);
    await tester.tap(find.byKey(const Key("stoop-comment-delete-confirm")));
    await tester.pumpAndSettle();
    expect(find.text("please remove this"), findsNothing);
    expect(find.text("deleted"), findsOneWidget);
    expect(find.text("@Tester"), findsOneWidget);
  });

  testWidgets("9. Report hidden on own comment (Delete shown instead)", (
    tester,
  ) async {
    final me = _user();
    final other = _comment(
      id: "theirs",
      authorId: "u2",
      name: "Other",
      body: "not mine",
      createdAt: _now.subtract(const Duration(minutes: 3)),
    );
    final mine = _comment(
      id: "mine",
      authorId: me.id,
      name: me.displayName,
      body: "my row",
      createdAt: _now.subtract(const Duration(minutes: 1)),
    );
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [other, mine],
    );
    await _pump(tester, user: me, client: client);
    expect(find.byKey(const Key("stoop-comment-delete-mine")), findsOneWidget);
    expect(find.byKey(const Key("stoop-comment-report-mine")), findsNothing);
    expect(
      find.byKey(const Key("stoop-comment-report-theirs")),
      findsOneWidget,
    );
    expect(find.byKey(const Key("stoop-comment-delete-theirs")), findsNothing);
  });

  testWidgets("10. no stars / no comment vote chrome", (tester) async {
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "c1",
          authorId: "u2",
          name: "Other",
          body: "a thought",
          createdAt: _now.subtract(const Duration(minutes: 4)),
        ),
      ],
    );
    await _pump(tester, user: _user(), client: client);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
    expect(find.byIcon(Icons.star_rate), findsNothing);
    expect(find.byIcon(Icons.thumb_up), findsNothing);
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.textContaining("vote"), findsNothing);
    expect(find.textContaining("Vote"), findsNothing);
  });

  testWidgets("11. no teaser on stoop_card_tile", (tester) async {
    final card = StoopCard(
      id: "card1",
      name: "Misty",
      summary: "A meteorologist.",
      type: "SOLO",
      nsfw: false,
      score: 4,
      downloadCount: 12,
      modPick: false,
      creator: const StoopCreatorRef(id: "c", displayName: "author"),
      primaryAssetId: null,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>(
        create: (_) => AuthState(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 320,
              child: StoopCardTile(card: card, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Discussion"), findsNothing);
    expect(find.textContaining("comment"), findsNothing);
    expect(find.textContaining("Comment"), findsNothing);
  });

  testWidgets("empty list shows No comments yet.", (tester) async {
    await _pump(tester, user: _user());
    expect(find.text("No comments yet."), findsOneWidget);
  });

  testWidgets("guest Sign in CTA opens Account snackbar", (tester) async {
    await _pump(tester, user: null);
    await tester.tap(find.text("Sign in to comment."));
    await tester.pumpAndSettle();
    expect(find.text("Sign in from Account to comment."), findsOneWidget);
  });

  testWidgets("default off: no Discussion block", (tester) async {
    await _pumpHost(tester, user: _user(), commentsEnabled: false);
    expect(find.text("Discussion"), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("Sign in to comment."), findsNothing);
    expect(find.text("No comments yet."), findsNothing);
    expect(find.byType(StoopCardComments), findsNothing);
  });

  testWidgets("opted-in: Discussion block shows", (tester) async {
    await _pumpHost(tester, user: _user(), commentsEnabled: true);
    expect(find.text("Discussion"), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text("No comments yet."), findsOneWidget);
  });

  testWidgets("GROUP without opt-in: no Discussion block", (tester) async {
    await _pumpHost(tester, user: _user(), commentsEnabled: false);
    expect(find.text("Discussion"), findsNothing);
    expect(find.byType(StoopCardComments), findsNothing);
  });

  testWidgets("WORLD without opt-in: no Discussion block", (tester) async {
    await _pumpHost(tester, user: _user(), commentsEnabled: false);
    expect(find.text("Discussion"), findsNothing);
    expect(find.byType(StoopCardComments), findsNothing);
  });

  testWidgets("GROUP opted-in: Discussion block shows", (tester) async {
    await _pumpHost(tester, user: _user(), commentsEnabled: true);
    expect(find.text("Discussion"), findsOneWidget);
  });

  testWidgets(
    "owner kill switch hides block but keeps comments in the fake store",
    (tester) async {
      final me = _user();
      final store = StoopCommentsOptIn()..setPublished("card1", true);
      final kept = _comment(
        id: "keep",
        authorId: "u2",
        name: "Ada",
        body: "please keep me",
        createdAt: _now.subtract(const Duration(minutes: 2)),
      );
      final client = MemoryStoopCommentsClient(now: () => _now, seed: [kept]);
      await _pumpHost(
        tester,
        user: me,
        cardOwnerId: me.id,
        commentsEnabled: true,
        store: store,
        client: client,
      );
      expect(find.text("Discussion"), findsOneWidget);
      expect(find.text("please keep me"), findsOneWidget);
      expect(
        find.byKey(const Key("stoop-comments-kill-switch")),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key("stoop-comments-kill-switch")));
      await tester.pumpAndSettle();
      expect(find.text("Discussion"), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text("please keep me"), findsNothing);
      expect(client.items, hasLength(1));
      expect(client.items.single.body, "please keep me");
      expect(store.live("card1", fromCard: true), isFalse);
      expect(store.published("card1", fromCard: true), isTrue);
    },
  );

  testWidgets("visitor never sees the owner kill switch", (tester) async {
    await _pumpHost(
      tester,
      user: _user(),
      cardOwnerId: "someone-else",
      commentsEnabled: true,
    );
    expect(find.byKey(const Key("stoop-comments-kill-switch")), findsNothing);
    expect(find.text("Discussion"), findsOneWidget);
  });

  testWidgets("403 email_not_verified closes composer", (tester) async {
    final client = MemoryStoopCommentsClient(
      now: () => _now,
    )..nextCreateError = const BackporchApiException(403, "email_not_verified");
    await _pump(tester, user: _user(), client: client);
    await tester.enterText(find.byType(TextField), "should not send cleanly");
    await tester.pump();
    await tester.tap(find.text("Post"));
    await tester.pumpAndSettle();
    expect(find.text("Confirm email to comment."), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets("R1. owner can reply to someone else's comment", (tester) async {
    final owner = _user(id: "owner", name: "Tester");
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "theirs",
          authorId: "ada",
          name: "Ada",
          body: "Love this card.",
          createdAt: _now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    await _pump(tester, user: owner, cardOwnerId: owner.id, client: client);
    expect(find.byKey(const Key("stoop-comment-reply-theirs")), findsOneWidget);
    await tester.tap(find.byKey(const Key("stoop-comment-reply-theirs")));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key("stoop-comment-reply-field-theirs")),
      "Thank you Ada",
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key("stoop-comment-reply-post-theirs")));
    await tester.pumpAndSettle();
    expect(find.text("Thank you Ada"), findsOneWidget);
    expect(find.text("Creator"), findsOneWidget);
    expect(find.byKey(const Key("stoop-comment-reply-theirs")), findsNothing);
    expect(
      find.byKey(const Key("stoop-comment-reply-row-theirs")),
      findsOneWidget,
    );
    final parent = tester.getTopLeft(find.text("Love this card."));
    final reply = tester.getTopLeft(find.text("Thank you Ada"));
    expect(reply.dx, greaterThan(parent.dx));
    expect(reply.dy, greaterThan(parent.dy));
  });

  testWidgets("R2. visitor cannot reply", (tester) async {
    final visitor = _user(id: "vis", name: "Visitor");
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "theirs",
          authorId: "ada",
          name: "Ada",
          body: "Love this card.",
          createdAt: _now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    await _pump(tester, user: visitor, cardOwnerId: "owner", client: client);
    expect(find.text("Reply"), findsNothing);
    expect(find.byKey(const Key("stoop-comment-reply-theirs")), findsNothing);
  });

  testWidgets("R3. one reply max; second create is 409", (tester) async {
    final owner = _user(id: "owner", name: "Tester");
    final existing = _comment(
      id: "theirs",
      authorId: "ada",
      name: "Ada",
      body: "Love this card.",
      createdAt: _now.subtract(const Duration(minutes: 5)),
      reply: _reply(
        authorId: owner.id,
        name: owner.displayName,
        body: "Already replied",
        createdAt: _now.subtract(const Duration(minutes: 1)),
      ),
    );
    final full = MemoryStoopCommentsClient(now: () => _now, seed: [existing]);
    await _pump(tester, user: owner, cardOwnerId: owner.id, client: full);
    expect(find.text("Already replied"), findsOneWidget);
    expect(find.text("Creator"), findsOneWidget);
    expect(find.text("Reply"), findsNothing);
    await expectLater(
      full.createReply(
        cardId: "card1",
        commentId: "theirs",
        body: "second try",
        author: owner,
        cardOwnerId: owner.id,
      ),
      throwsA(
        isA<BackporchApiException>()
            .having((e) => e.statusCode, "status", 409)
            .having((e) => e.code, "code", "reply_exists"),
      ),
    );
  });

  testWidgets("R3b. 409 and 429 keep the reply draft", (tester) async {
    final owner = _user(id: "owner", name: "Tester");
    final open = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "open",
          authorId: "ada",
          name: "Ada",
          body: "Need a reply",
          createdAt: _now.subtract(const Duration(minutes: 4)),
        ),
      ],
    )..nextReplyError = const BackporchApiException(409, "duplicate_comment");
    await _pump(tester, user: owner, cardOwnerId: owner.id, client: open);
    await tester.tap(find.byKey(const Key("stoop-comment-reply-open")));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key("stoop-comment-reply-field-open")),
      "keep this draft",
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key("stoop-comment-reply-post-open")));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key("stoop-comment-reply-field-open")),
          )
          .controller!
          .text,
      "keep this draft",
    );
    expect(find.text("You already posted that."), findsOneWidget);

    open.nextReplyError = const BackporchApiException(429, "too_many_comments");
    await tester.tap(find.byKey(const Key("stoop-comment-reply-post-open")));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key("stoop-comment-reply-field-open")),
          )
          .controller!
          .text,
      "keep this draft",
    );
    expect(find.textContaining("commenting too fast"), findsOneWidget);
  });

  testWidgets("R4. deleted reply shows tombstone, row remains", (tester) async {
    final owner = _user(id: "owner", name: "Tester");
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "theirs",
          authorId: "ada",
          name: "Ada",
          body: "Love this card.",
          createdAt: _now.subtract(const Duration(minutes: 5)),
          reply: _reply(
            authorId: owner.id,
            name: owner.displayName,
            body: "Thank you Ada",
            createdAt: _now.subtract(const Duration(minutes: 1)),
          ),
        ),
      ],
    );
    await _pump(tester, user: owner, cardOwnerId: owner.id, client: client);
    expect(find.text("Thank you Ada"), findsOneWidget);
    await tester.tap(
      find.byKey(const Key("stoop-comment-reply-delete-theirs")),
    );
    await tester.pumpAndSettle();
    expect(find.text("Delete reply?"), findsOneWidget);
    await tester.tap(find.byKey(const Key("stoop-comment-delete-confirm")));
    await tester.pumpAndSettle();
    expect(find.text("Thank you Ada"), findsNothing);
    expect(find.text("deleted"), findsOneWidget);
    expect(find.text("Love this card."), findsOneWidget);
    expect(
      find.byKey(const Key("stoop-comment-reply-row-theirs")),
      findsOneWidget,
    );
    expect(find.text("Creator"), findsOneWidget);
    expect(find.byKey(const Key("stoop-comment-reply-theirs")), findsOneWidget);
  });

  testWidgets(
    "R4b. owner sees Reply on a tombstone; after post Reply is gone; 409 on second live",
    (tester) async {
      final owner = _user(id: "owner", name: "Tester");
      final client = MemoryStoopCommentsClient(
        now: () => _now,
        seed: [
          _comment(
            id: "theirs",
            authorId: "ada",
            name: "Ada",
            body: "Love this card.",
            createdAt: _now.subtract(const Duration(minutes: 5)),
            reply: _reply(
              authorId: owner.id,
              name: owner.displayName,
              body: "old",
              createdAt: _now.subtract(const Duration(minutes: 1)),
              deleted: true,
            ),
          ),
        ],
      );
      await _pump(tester, user: owner, cardOwnerId: owner.id, client: client);
      expect(find.text("deleted"), findsOneWidget);
      expect(
        find.byKey(const Key("stoop-comment-reply-row-theirs")),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key("stoop-comment-reply-theirs")),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key("stoop-comment-reply-theirs")));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key("stoop-comment-reply-field-theirs")),
        "New reply after hide",
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key("stoop-comment-reply-post-theirs")),
      );
      await tester.pumpAndSettle();
      expect(find.text("New reply after hide"), findsOneWidget);
      expect(find.text("deleted"), findsNothing);
      expect(find.byKey(const Key("stoop-comment-reply-theirs")), findsNothing);
      expect(find.text("Reply"), findsNothing);
      await expectLater(
        client.createReply(
          cardId: "card1",
          commentId: "theirs",
          body: "second live",
          author: owner,
          cardOwnerId: owner.id,
        ),
        throwsA(
          isA<BackporchApiException>()
              .having((e) => e.statusCode, "status", 409)
              .having((e) => e.code, "code", "reply_exists"),
        ),
      );
    },
  );

  testWidgets("R5. Report hidden on own reply; visitor can report it", (
    tester,
  ) async {
    final owner = _user(id: "owner", name: "Tester");
    final visitor = _user(id: "vis", name: "Visitor");
    final seed = [
      _comment(
        id: "theirs",
        authorId: "ada",
        name: "Ada",
        body: "Love this card.",
        createdAt: _now.subtract(const Duration(minutes: 5)),
        reply: _reply(
          authorId: owner.id,
          name: owner.displayName,
          body: "Thank you Ada",
          createdAt: _now.subtract(const Duration(minutes: 1)),
        ),
      ),
    ];
    await _pump(
      tester,
      user: owner,
      cardOwnerId: owner.id,
      client: MemoryStoopCommentsClient(now: () => _now, seed: seed),
    );
    expect(
      find.byKey(const Key("stoop-comment-reply-delete-theirs")),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key("stoop-comment-reply-report-theirs")),
      findsNothing,
    );

    await _pump(
      tester,
      user: visitor,
      cardOwnerId: owner.id,
      client: MemoryStoopCommentsClient(now: () => _now, seed: seed),
    );
    expect(
      find.byKey(const Key("stoop-comment-reply-report-theirs")),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key("stoop-comment-reply-delete-theirs")),
      findsNothing,
    );
    expect(find.text("Reply"), findsNothing);
  });

  testWidgets("R6. top-level author who is not the owner cannot reply", (
    tester,
  ) async {
    final author = _user(id: "ada", name: "Ada");
    final client = MemoryStoopCommentsClient(
      now: () => _now,
      seed: [
        _comment(
          id: "mine",
          authorId: author.id,
          name: author.displayName,
          body: "Love this card.",
          createdAt: _now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    await _pump(tester, user: author, cardOwnerId: "owner", client: client);
    expect(find.text("Reply"), findsNothing);
    expect(find.byKey(const Key("stoop-comment-reply-mine")), findsNothing);
    expect(find.text("Love this card."), findsOneWidget);
  });
}
