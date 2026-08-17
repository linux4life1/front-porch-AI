// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import "package:flutter_test/flutter_test.dart";

import "package:front_porch_ai/services/backporch/backporch.dart";

BackporchUser _user({
  bool verified = true,
  bool known = true,
  String? pendingEmail,
  String role = "USER",
  String id = "u1",
}) => BackporchUser(
  id: id,
  email: "a@b.c",
  displayName: "Tester",
  role: role,
  ageVerified: true,
  emailVerified: verified,
  emailVerifiedKnown: known,
  nsfwEnabled: false,
  acceptedPolicyVersion: "1.0",
  twoFactorEnabled: false,
  pendingEmail: pendingEmail,
);

void main() {
  test("guest cannot comment", () {
    expect(stoopCanComment(null), isFalse);
  });

  test("explicit false cannot comment", () {
    expect(stoopCanComment(_user(verified: false)), isFalse);
  });

  test("omitted emailVerified cannot comment (unlike report)", () {
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
    expect(omitted.emailVerified, isTrue);
    expect(omitted.emailVerifiedKnown, isFalse);
    expect(stoopCanComment(omitted), isFalse);
    expect(stoopCanReport(omitted), isTrue);
  });

  test("pending change-email is not verified", () {
    expect(stoopCanComment(_user(pendingEmail: "new@b.c")), isFalse);
  });

  test("accepting the AUP is not a substitute for emailVerified", () {
    expect(stoopCanComment(_user(verified: false)), isFalse);
    expect(stoopCanComment(_user(verified: true)), isTrue);
  });

  test("explicit true can comment", () {
    expect(stoopCanComment(_user()), isTrue);
  });

  test("comment JSON never carries email or verification", () {
    final c = StoopComment(
      id: "c1",
      cardId: "card1",
      authorId: "u1",
      displayName: "Tester",
      createdAt: DateTime.utc(2026, 8, 17, 12),
      body: "hello",
    );
    final json = c.toJson();
    expect(json.containsKey("email"), isFalse);
    expect(json.containsKey("emailVerified"), isFalse);
    expect(
      json.keys,
      containsAll([
        "id",
        "authorId",
        "displayName",
        "createdAt",
        "body",
        "deleted",
      ]),
    );
  });

  test("commentsEnabled defaults off and is fail-closed", () {
    final omitted = StoopCardDetail.fromJson({
      "id": "c1",
      "name": "Misty",
      "summary": "x",
      "type": "SOLO",
    });
    expect(omitted.commentsEnabled, isFalse);
    final on = StoopCardDetail.fromJson({
      "id": "c1",
      "name": "Misty",
      "summary": "x",
      "type": "GROUP",
      "commentsEnabled": true,
    });
    expect(on.commentsEnabled, isTrue);
    final world = StoopCardDetail.fromJson({
      "id": "w1",
      "name": "Place",
      "summary": "x",
      "type": "WORLD",
    });
    expect(world.commentsEnabled, isFalse);
  });

  test("reply JSON never carries email or verification", () {
    final c = StoopComment(
      id: "c1",
      cardId: "card1",
      authorId: "u2",
      displayName: "Ada",
      createdAt: DateTime.utc(2026, 8, 17, 12),
      body: "hello",
      reply: StoopCommentReply(
        authorId: "u1",
        displayName: "Owner",
        createdAt: DateTime.utc(2026, 8, 17, 12, 1),
        body: "thanks",
      ),
    );
    final json = c.toJson();
    expect(json.containsKey("email"), isFalse);
    expect(json.containsKey("emailVerified"), isFalse);
    final reply = json["reply"] as Map<String, dynamic>;
    expect(reply.containsKey("email"), isFalse);
    expect(reply.containsKey("emailVerified"), isFalse);
    expect(
      reply.keys,
      containsAll(["authorId", "displayName", "createdAt", "body", "deleted"]),
    );
  });

  test("stoopCanReplyToComment is owner-only and one-level", () {
    final owner = _user(id: "owner");
    final visitor = _user(id: "vis");
    final author = _user(id: "ada");
    final unverified = _user(id: "owner", verified: false);
    final parent = StoopComment(
      id: "c1",
      cardId: "card1",
      authorId: author.id,
      displayName: "Ada",
      createdAt: DateTime.utc(2026, 8, 17, 12),
      body: "hello",
    );
    expect(
      stoopCanReplyToComment(
        comment: parent,
        user: owner,
        cardOwnerId: owner.id,
      ),
      isTrue,
    );
    expect(
      stoopCanReplyToComment(
        comment: parent,
        user: visitor,
        cardOwnerId: owner.id,
      ),
      isFalse,
    );
    expect(
      stoopCanReplyToComment(
        comment: parent,
        user: author,
        cardOwnerId: owner.id,
      ),
      isFalse,
    );
    expect(
      stoopCanReplyToComment(
        comment: parent,
        user: unverified,
        cardOwnerId: owner.id,
      ),
      isFalse,
    );
    expect(
      stoopCanReplyToComment(
        comment: parent.copyWith(
          reply: StoopCommentReply(
            authorId: "owner",
            displayName: "Owner",
            createdAt: DateTime.utc(2026, 8, 17, 12, 1),
            body: "thanks",
          ),
        ),
        user: owner,
        cardOwnerId: owner.id,
      ),
      isFalse,
    );
    expect(
      stoopCanReplyToComment(
        comment: parent.copyWith(
          reply: StoopCommentReply(
            authorId: "owner",
            displayName: "Owner",
            createdAt: DateTime.utc(2026, 8, 17, 12, 1),
            body: "",
            deleted: true,
          ),
        ),
        user: owner,
        cardOwnerId: owner.id,
      ),
      isTrue,
    );
    final ownTop = StoopComment(
      id: "mine",
      cardId: "card1",
      authorId: owner.id,
      displayName: "Owner",
      createdAt: DateTime.utc(2026, 8, 17, 12),
      body: "my row",
    );
    expect(
      stoopCanReplyToComment(
        comment: ownTop,
        user: owner,
        cardOwnerId: owner.id,
      ),
      isFalse,
    );
    expect(
      stoopCanReplyToComment(
        comment: parent.copyWith(deleted: true, body: ""),
        user: owner,
        cardOwnerId: owner.id,
      ),
      isFalse,
    );
  });

  test(
    "createReply fail-closed: unverified 403, non-owner 403, one reply 409",
    () async {
      final owner = _user(id: "owner");
      final visitor = _user(id: "vis");
      final unverified = _user(id: "owner", verified: false);
      final parent = StoopComment(
        id: "c1",
        cardId: "card1",
        authorId: "ada",
        displayName: "Ada",
        createdAt: DateTime.utc(2026, 8, 17, 11),
        body: "hello",
      );
      final client = MemoryStoopCommentsClient(
        seed: [parent],
        now: () => DateTime.utc(2026, 8, 17, 12),
      );

      try {
        await client.createReply(
          cardId: "card1",
          commentId: "c1",
          body: "thanks",
          author: unverified,
          cardOwnerId: owner.id,
        );
        fail("expected 403");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, "email_not_verified");
      }

      try {
        await client.createReply(
          cardId: "card1",
          commentId: "c1",
          body: "thanks",
          author: visitor,
          cardOwnerId: owner.id,
        );
        fail("expected 403");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, "not_card_owner");
      }

      final created = await client.createReply(
        cardId: "card1",
        commentId: "c1",
        body: "thanks",
        author: owner,
        cardOwnerId: owner.id,
      );
      expect(created.reply?.body, "thanks");
      expect(created.reply?.authorId, owner.id);

      try {
        await client.createReply(
          cardId: "card1",
          commentId: "c1",
          body: "second",
          author: owner,
          cardOwnerId: owner.id,
        );
        fail("expected 409");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.code, "reply_exists");
      }
    },
  );

  test(
    "createReply rejects links and reports cannot target own reply",
    () async {
      final owner = _user(id: "owner");
      final visitor = _user(id: "vis");
      final parent = StoopComment(
        id: "c1",
        cardId: "card1",
        authorId: "ada",
        displayName: "Ada",
        createdAt: DateTime.utc(2026, 8, 17, 11),
        body: "hello",
      );
      final client = MemoryStoopCommentsClient(
        seed: [parent],
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.createReply(
          cardId: "card1",
          commentId: "c1",
          body: "see https://example.com",
          author: owner,
          cardOwnerId: owner.id,
        );
        fail("expected 400");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 400);
        expect(e.code, "no_links");
      }
      await client.createReply(
        cardId: "card1",
        commentId: "c1",
        body: "thanks",
        author: owner,
        cardOwnerId: owner.id,
      );
      try {
        await client.reportReply(
          cardId: "card1",
          commentId: "c1",
          actor: owner,
          category: "OTHER",
          reason: "nope",
        );
        fail("expected 403");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, "cannot_report_own");
      }
      await client.reportReply(
        cardId: "card1",
        commentId: "c1",
        actor: visitor,
        category: "OTHER",
        reason: "spam",
      );
    },
  );

  test(
    "create payload has no asOwner/role/isCreator/parentId; createReply is separate",
    () async {
      final author = _user(id: "ada");
      final owner = _user(id: "owner");
      final client = MemoryStoopCommentsClient(
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      await client.create(cardId: "card1", body: "hello porch", author: author);
      final create = client.lastCreatePayload!;
      for (final banned in ["asOwner", "role", "isCreator", "parentId"]) {
        expect(create.containsKey(banned), isFalse, reason: banned);
      }
      expect(create["cardId"], "card1");
      expect(create["body"], "hello porch");
      expect(create["authorId"], author.id);
      expect(client.lastCreateReplyPayload, isNull);

      final created = client.items.single;
      await client.createReply(
        cardId: "card1",
        commentId: created.id,
        body: "thanks Ada",
        author: owner,
        cardOwnerId: owner.id,
      );
      expect(client.lastCreateReplyPayload, isNotNull);
      final reply = client.lastCreateReplyPayload!;
      for (final banned in ["asOwner", "role", "isCreator", "parentId"]) {
        expect(reply.containsKey(banned), isFalse, reason: banned);
      }
      expect(reply["commentId"], created.id);
      expect(reply["body"], "thanks Ada");
      expect(reply["authorId"], owner.id);
      // create() was not reused — reply is a nested field, not a parentId create.
      expect(client.items, hasLength(1));
      expect(client.items.single.reply?.body, "thanks Ada");
    },
  );

  test(
    "createReply after soft-delete replaces the tombstone (no PATCH)",
    () async {
      final owner = _user(id: "owner");
      final parent = StoopComment(
        id: "c1",
        cardId: "card1",
        authorId: "ada",
        displayName: "Ada",
        createdAt: DateTime.utc(2026, 8, 17, 11),
        body: "hello",
        reply: StoopCommentReply(
          authorId: "owner",
          displayName: "Owner",
          createdAt: DateTime.utc(2026, 8, 17, 11, 30),
          body: "",
          deleted: true,
        ),
      );
      final client = MemoryStoopCommentsClient(
        seed: [parent],
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      final updated = await client.createReply(
        cardId: "card1",
        commentId: "c1",
        body: "new reply",
        author: owner,
        cardOwnerId: owner.id,
      );
      expect(updated.reply?.deleted, isFalse);
      expect(updated.reply?.body, "new reply");
    },
  );

  test(
    "createReply on deleted parent is 403 comment_deleted, no reply glued on",
    () async {
      final owner = _user(id: "owner");
      final parent = StoopComment(
        id: "c1",
        cardId: "card1",
        authorId: "ada",
        displayName: "Ada",
        createdAt: DateTime.utc(2026, 8, 17, 11),
        body: "",
        deleted: true,
      );
      final client = MemoryStoopCommentsClient(
        seed: [parent],
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.createReply(
          cardId: "card1",
          commentId: "c1",
          body: "thanks",
          author: owner,
          cardOwnerId: owner.id,
        );
        fail("expected 403");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, "comment_deleted");
        expect(e.code, isNot("email_not_verified"));
      }
      expect(client.items, hasLength(1));
      expect(client.items.single.deleted, isTrue);
      expect(client.items.single.reply, isNull);
    },
  );

  test("rejects https link", () {
    expect(stoopCommentBodyHasLink("see https://example.com"), isTrue);
  });

  test("rejects http link", () {
    expect(stoopCommentBodyHasLink("see http://example.com"), isTrue);
  });

  test("rejects www link", () {
    expect(stoopCommentBodyHasLink("see www.example.com"), isTrue);
  });

  test("rejects bare domain path", () {
    expect(stoopCommentBodyHasLink("see example.com/x"), isTrue);
  });

  test("rejects bare example.com host", () {
    expect(stoopCommentBodyHasLink("go to example.com"), isTrue);
  });

  test("rejects discord.gg invite", () {
    expect(stoopCommentBodyHasLink("join discord.gg/abc"), isTrue);
  });

  test("rejects bare discord.gg host", () {
    expect(stoopCommentBodyHasLink("join discord.gg"), isTrue);
  });

  test("rejects mailto", () {
    expect(stoopCommentBodyHasLink("mail me mailto:evil@x.com"), isTrue);
  });

  test("rejects protocol-relative url", () {
    expect(stoopCommentBodyHasLink("img //cdn.evil.com/x"), isTrue);
  });

  test("rejects bare t.me host", () {
    expect(stoopCommentBodyHasLink("join t.me"), isTrue);
  });

  test("rejects bare bit.ly host", () {
    expect(stoopCommentBodyHasLink("go to bit.ly"), isTrue);
  });

  test("rejects https with ZWSP", () {
    expect(stoopCommentBodyHasLink("see https:\u200b//example.com"), isTrue);
  });

  test("rejects dotted IPv4 host", () {
    expect(stoopCommentBodyHasLink("go to 203.0.113.9"), isTrue);
  });

  test("rejects dotted IPv4 with path", () {
    expect(stoopCommentBodyHasLink("203.0.113.9/invite"), isTrue);
  });

  test("rejects compressed IPv6 in prose", () {
    expect(stoopCommentBodyHasLink("meet at 2001:db8::1"), isTrue);
  });

  test("rejects bare compressed IPv6", () {
    expect(stoopCommentBodyHasLink("2001:db8::1"), isTrue);
  });

  test("rejects loopback IPv6", () {
    expect(stoopCommentBodyHasLink("::1"), isTrue);
  });

  test("rejects bracketed IPv6 with path", () {
    expect(stoopCommentBodyHasLink("see [2001:db8::1]/x"), isTrue);
  });

  test("rejects bracketed IPv6 invite path", () {
    expect(stoopCommentBodyHasLink("[2001:db8::1]/invite"), isTrue);
  });

  test("rejects ftp bracketed IPv6", () {
    expect(stoopCommentBodyHasLink("ftp://[2001:db8::1]/"), isTrue);
  });

  test("rejects ftp bracketed IPv6 invite", () {
    expect(stoopCommentBodyHasLink("ftp://[2001:db8::1]/invite"), isTrue);
  });

  test("rejects https bracketed IPv6 invite", () {
    expect(stoopCommentBodyHasLink("https://[2001:db8::1]/invite"), isTrue);
  });

  test("rejects ws bracketed IPv6", () {
    expect(stoopCommentBodyHasLink("ws://[2001:db8::1]/chat"), isTrue);
  });

  test("rejects ideographic-dot host", () {
    expect(stoopCommentBodyHasLink("go to example\u3002com"), isTrue);
  });

  test("rejects halfwidth-ideographic-dot host", () {
    expect(stoopCommentBodyHasLink("example\uff61com"), isTrue);
  });

  test("rejects fullwidth-dot host", () {
    expect(stoopCommentBodyHasLink("go to example\uff0ecom"), isTrue);
  });

  test("rejects Cyrillic IDN host", () {
    expect(stoopCommentBodyHasLink("see пример.рф"), isTrue);
  });

  test("rejects whatsapp scheme", () {
    expect(stoopCommentBodyHasLink("whatsapp://send?phone=15551212"), isTrue);
  });

  test("rejects hex IPv4", () {
    expect(stoopCommentBodyHasLink("0xCB007109"), isTrue);
  });

  test("rejects short IPv4", () {
    expect(stoopCommentBodyHasLink("127.1"), isTrue);
  });

  test("rejects small-full-stop host (U+FE52)", () {
    expect(stoopCommentBodyHasLink("go to example\ufe52com"), isTrue);
  });

  test("rejects katakana-middle-dot host (U+30FB)", () {
    expect(stoopCommentBodyHasLink("go to example\u30fbcom"), isTrue);
  });

  test("rejects middle-dot host (U+00B7)", () {
    expect(stoopCommentBodyHasLink("go to example\u00b7com"), isTrue);
  });

  test("rejects tel scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("tel:+15551212"), isTrue);
  });

  test("rejects sms scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("sms:5551234"), isTrue);
  });

  test("rejects magnet scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("magnet:?dn=hello"), isTrue);
  });

  test("rejects skype scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("skype:user99"), isTrue);
  });

  test("rejects bitcoin scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("bitcoin:1"), isTrue);
  });

  test("rejects geo scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("geo:1,2"), isTrue);
  });

  test("prose see: and note: are not schemes", () {
    expect(stoopCommentBodyHasLink("see: the porch"), isFalse);
    expect(stoopCommentBodyHasLink("note: bring chairs"), isFalse);
  });

  test("clock time is not IPv6", () {
    expect(stoopCommentBodyHasLink("meet at 10:30:45"), isFalse);
  });

  test("rejects file scheme", () {
    expect(stoopCommentBodyHasLink("open file:///tmp/x"), isTrue);
  });

  test("rejects javascript scheme", () {
    expect(stoopCommentBodyHasLink("javascript:alert(1)"), isTrue);
  });

  test("rejects data scheme", () {
    expect(stoopCommentBodyHasLink("data:text/html,hi"), isTrue);
  });

  test("rejects tg scheme", () {
    expect(stoopCommentBodyHasLink("open tg://resolve?domain=x"), isTrue);
  });

  test("rejects localhost", () {
    expect(stoopCommentBodyHasLink("see localhost/invite"), isTrue);
  });

  test("rejects percent-encoded dot host", () {
    expect(stoopCommentBodyHasLink("go to example%2ecom"), isTrue);
  });

  test("rejects percent-encoded uppercase-dot host", () {
    expect(stoopCommentBodyHasLink("example%2Ecom"), isTrue);
  });

  test("rejects percent-encoded-dot host with path", () {
    expect(stoopCommentBodyHasLink("example%2ecom/invite"), isTrue);
  });

  test("rejects double-encoded percent-dot host", () {
    expect(stoopCommentBodyHasLink("go to example%252ecom"), isTrue);
  });

  test("rejects triple-encoded percent-dot host", () {
    expect(stoopCommentBodyHasLink("go to example%25252ecom"), isTrue);
  });

  test("rejects four-round nested percent-dot host", () {
    expect(stoopCommentBodyHasLink("go to example%2525252ecom"), isTrue);
  });

  test("rejects bare four-round nested percent-dot host", () {
    expect(stoopCommentBodyHasLink("example%2525252ecom"), isTrue);
  });

  test("rejects four-round nested percent-dot host with path", () {
    expect(stoopCommentBodyHasLink("example%2525252ecom/invite"), isTrue);
  });

  test("rejects percent-null-byte host (decode then Cc)", () {
    expect(stoopCommentBodyHasLink("example%00.com"), isTrue);
  });

  test("rejects html decimal-period entity host", () {
    expect(stoopCommentBodyHasLink("go to example&#46;com"), isTrue);
  });

  test("rejects html named-period entity host", () {
    expect(stoopCommentBodyHasLink("go to example&period;com"), isTrue);
  });

  test("rejects html entity leading-zero / no-semi / named-dot hosts", () {
    const holds = [
      "example&#046;com",
      "example&#00046;com",
      "example&#x02e;com",
      "example&#x0002E;com",
      "example&#46com",
      "example&periodcom",
      "example&Dot;com",
      "example&#x3002;com",
      r"example\.com",
      "maps:q=x",
    ];
    for (final body in holds) {
      expect(stoopCommentBodyHasLink(body), isTrue, reason: body);
    }
  });

  test("rejects maps: and line: schemes", () {
    expect(stoopCommentBodyHasLink("maps:q=x"), isTrue);
    expect(stoopCommentBodyHasLink("line:msg"), isTrue);
  });

  test("rejects percent-u-dot host", () {
    expect(stoopCommentBodyHasLink("go to example%u002ecom"), isTrue);
  });

  test("rejects dot-above host (U+02D9 before NFKC)", () {
    expect(stoopCommentBodyHasLink("go to example\u02d9com"), isTrue);
  });

  test("rejects null-byte host (Cc)", () {
    expect(stoopCommentBodyHasLink("example\u0000.com"), isTrue);
  });

  test("rejects callto scheme without slash-slash", () {
    expect(stoopCommentBodyHasLink("callto:user"), isTrue);
  });

  test("rejects slash-less whatsapp scheme", () {
    expect(stoopCommentBodyHasLink("whatsapp:send"), isTrue);
  });

  test("plain text is not a link", () {
    expect(
      stoopCommentBodyHasLink("just a thought about 3.14 and ok."),
      isFalse,
    );
  });

  test("1000 cap is unchanged", () {
    expect(kStoopCommentMaxLength, 1000);
  });

  test("create rejects IPv6 body with no_links", () async {
    final author = _user(id: "ada");
    final client = MemoryStoopCommentsClient(
      now: () => DateTime.utc(2026, 8, 17, 12),
    );
    try {
      await client.create(
        cardId: "card1",
        body: "meet at 2001:db8::1",
        author: author,
      );
      fail("expected 400");
    } on BackporchApiException catch (e) {
      expect(e.statusCode, 400);
      expect(e.code, "no_links");
    }
    expect(client.items, isEmpty);
  });

  test("create rejects IPv6 / unicode-dot / IDN holds with no_links", () async {
    final author = _user(id: "ada");
    const holds = [
      "[2001:db8::1]/invite",
      "ftp://[2001:db8::1]/invite",
      "2001:db8::1",
      "::1",
      "ws://[2001:db8::1]/chat",
      "see пример.рф",
      "go to example\uff0ecom",
      "meet at 2001:db8::1",
      "see [2001:db8::1]/x",
      "ftp://[2001:db8::1]/",
      "go to example\u3002com",
      "example\uff61com",
    ];
    for (final body in holds) {
      final client = MemoryStoopCommentsClient(
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.create(cardId: "card1", body: body, author: author);
        fail("expected 400 for $body");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 400, reason: body);
        expect(e.code, "no_links", reason: body);
      }
      expect(client.items, isEmpty, reason: body);
    }
  });

  test("create rejects FE52/30FB/00B7 hosts and slash-less schemes", () async {
    final author = _user(id: "ada");
    const holds = [
      "go to example\ufe52com",
      "go to example\u30fbcom",
      "go to example\u00b7com",
      "tel:+15551212",
      "sms:5551234",
      "magnet:?dn=hello",
      "skype:user99",
      "bitcoin:1",
      "geo:1,2",
    ];
    for (final body in holds) {
      final client = MemoryStoopCommentsClient(
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.create(cardId: "card1", body: body, author: author);
        fail("expected 400 for $body");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 400, reason: body);
        expect(e.code, "no_links", reason: body);
      }
      expect(client.items, isEmpty, reason: body);
    }
  });

  test("create rejects percent-dot / Cc / slash-less scheme holds", () async {
    final author = _user(id: "ada");
    const holds = [
      "go to example%2ecom",
      "example%2Ecom",
      "example%2ecom/invite",
      "go to example%252ecom",
      "go to example%25252ecom",
      "example\u0000.com",
      "callto:user",
      "whatsapp:send",
    ];
    for (final body in holds) {
      final client = MemoryStoopCommentsClient(
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.create(cardId: "card1", body: body, author: author);
        fail("expected 400 for $body");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 400, reason: body);
        expect(e.code, "no_links", reason: body);
      }
      expect(client.items, isEmpty, reason: body);
    }
  });

  test("create rejects nested-percent / entity / %u / U+02D9 holds", () async {
    final author = _user(id: "ada");
    const holds = [
      "go to example%2525252ecom",
      "example%2525252ecom",
      "example%2525252ecom/invite",
      "example%00.com",
      "go to example&#46;com",
      "go to example&period;com",
      "go to example%u002ecom",
      "go to example\u02d9com",
    ];
    for (final body in holds) {
      final client = MemoryStoopCommentsClient(
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.create(cardId: "card1", body: body, author: author);
        fail("expected 400 for $body");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 400, reason: body);
        expect(e.code, "no_links", reason: body);
      }
      expect(client.items, isEmpty, reason: body);
    }
  });

  test("create rejects html-entity / backslash-dot / maps: holds", () async {
    final author = _user(id: "ada");
    const holds = [
      "example&#046;com",
      "example&#00046;com",
      "example&#x02e;com",
      "example&#x0002E;com",
      "example&#46com",
      "example&periodcom",
      "example&Dot;com",
      "example&#x3002;com",
      r"example\.com",
      "maps:q=x",
    ];
    for (final body in holds) {
      final client = MemoryStoopCommentsClient(
        now: () => DateTime.utc(2026, 8, 17, 12),
      );
      try {
        await client.create(cardId: "card1", body: body, author: author);
        fail("expected 400 for $body");
      } on BackporchApiException catch (e) {
        expect(e.statusCode, 400, reason: body);
        expect(e.code, "no_links", reason: body);
      }
      expect(client.items, isEmpty, reason: body);
    }
  });

  test("create allows decimal and clock-time prose", () async {
    final author = _user(id: "ada");
    final client = MemoryStoopCommentsClient(
      now: () => DateTime.utc(2026, 8, 17, 12),
    );
    await client.create(
      cardId: "card1",
      body: "just a thought about 3.14 and ok.",
      author: author,
    );
    await client.create(
      cardId: "card1",
      body: "meet at 10:30:45",
      author: author,
    );
    await client.create(
      cardId: "card1",
      body: "see: the porch",
      author: author,
    );
    await client.create(
      cardId: "card1",
      body: "note: bring chairs",
      author: author,
    );
    expect(client.items, hasLength(4));
  });

  test("create refuses when commentsEnabled is omitted", () async {
    final author = _user(id: "ada");
    final client = MemoryStoopCommentsClient(
      commentsEnabled: const {},
      now: () => DateTime.utc(2026, 8, 17, 12),
    );
    try {
      await client.create(cardId: "card1", body: "hello porch", author: author);
      fail("expected 403");
    } on BackporchApiException catch (e) {
      expect(e.statusCode, 403);
      expect(e.code, "comments_disabled");
    }
    expect(client.items, isEmpty);
  });

  test("create refuses when commentsEnabled is false", () async {
    final author = _user(id: "ada");
    final client = MemoryStoopCommentsClient(
      commentsEnabled: const {"card1": false},
      now: () => DateTime.utc(2026, 8, 17, 12),
    );
    try {
      await client.create(cardId: "card1", body: "hello porch", author: author);
      fail("expected 403");
    } on BackporchApiException catch (e) {
      expect(e.statusCode, 403);
      expect(e.code, "comments_disabled");
    }
    expect(client.items, isEmpty);
  });

  test("createReply refuses when live kill-switch is off", () async {
    final owner = _user(id: "owner");
    final store = StoopCommentsOptIn()
      ..setPublished("card1", true)
      ..setLive("card1", false);
    final parent = StoopComment(
      id: "c1",
      cardId: "card1",
      authorId: "ada",
      displayName: "Ada",
      createdAt: DateTime.utc(2026, 8, 17, 11),
      body: "hello",
    );
    final client = MemoryStoopCommentsClient(
      seed: [parent],
      optIn: store,
      commentsEnabled: const {"card1": true},
      now: () => DateTime.utc(2026, 8, 17, 12),
    );
    try {
      await client.createReply(
        cardId: "card1",
        commentId: "c1",
        body: "thanks",
        author: owner,
        cardOwnerId: owner.id,
      );
      fail("expected 403");
    } on BackporchApiException catch (e) {
      expect(e.statusCode, 403);
      expect(e.code, "comments_disabled");
    }
    expect(client.items.single.reply, isNull);
  });

  test(
    "report on deleted comment does not 403 for being a tombstone",
    () async {
      final visitor = _user(id: "vis");
      final parent = StoopComment(
        id: "c1",
        cardId: "card1",
        authorId: "ada",
        displayName: "Ada",
        createdAt: DateTime.utc(2026, 8, 17, 11),
        body: "",
        deleted: true,
      );
      final client = MemoryStoopCommentsClient(seed: [parent]);
      await client.report(
        cardId: "card1",
        commentId: "c1",
        actor: visitor,
        category: "OTHER",
        reason: "still spam",
      );
    },
  );

  test(
    "reportReply on deleted reply does not 403 for being a tombstone",
    () async {
      final visitor = _user(id: "vis");
      final parent = StoopComment(
        id: "c1",
        cardId: "card1",
        authorId: "ada",
        displayName: "Ada",
        createdAt: DateTime.utc(2026, 8, 17, 11),
        body: "hello",
        reply: StoopCommentReply(
          authorId: "owner",
          displayName: "Owner",
          createdAt: DateTime.utc(2026, 8, 17, 11, 30),
          body: "",
          deleted: true,
        ),
      );
      final client = MemoryStoopCommentsClient(seed: [parent]);
      await client.reportReply(
        cardId: "card1",
        commentId: "c1",
        actor: visitor,
        category: "OTHER",
        reason: "still spam",
      );
    },
  );
}
