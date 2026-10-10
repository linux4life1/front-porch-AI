// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Web Server must show a login the moment a phone creates it
// (and "No web login yet" the moment it is gone), not only after the page
// is reopened.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashlib/hashlib.dart' show Argon2Security;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/auth/password_hasher.dart';
import 'package:front_porch_ai/ui/settings/widgets/web_login_section.dart';

/// The real service, except its FIRST account read (made before the phone's
/// setup, so it truly finds no account) is held back until released — so a
/// stale read lands after the fresh one, deterministically.
class _SlowFirstRead extends AuthService {
  _SlowFirstRead(super.db, {super.passwordHasher});

  final firstReadDone = Completer<void>();
  final release = Completer<void>();
  var _reads = 0;

  @override
  Future<({String username, bool totpEnabled})?> accountInfo() async {
    final first = _reads++ == 0;
    final info = await super.accountInfo();
    if (first) {
      firstReadDone.complete();
      await release.future;
    }
    return info;
  }
}

void main() {
  late AppDatabase db;
  late AuthService auth;

  setUp(() {
    db = AppDatabase.forTesting();
    // Real Argon2id at its test cost (the app's cost is pinned elsewhere).
    auth = AuthService(
      db,
      passwordHasher: const PasswordHasher(security: Argon2Security.test),
    );
  });
  tearDown(() => db.close());

  /// Let the card's database reads finish on the real clock, then redraw,
  /// until [finder] shows (bounded generously for a busy runner).
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 500 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a login made from the phone shows without reopening, and a '
      'reset shows "No web login yet" again', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebLoginSection(auth: auth)),
      ),
    );
    final none = find.textContaining('No web login yet');
    await pumpUntil(tester, none);
    expect(none, findsOneWidget);

    // The phone's first-run setup, with the code the desktop shows.
    final status = await tester.runAsync(() async {
      final code = await auth.setupTokenForDesktop();
      return auth.setupAccount('porch', 'password123', setupToken: code);
    });
    expect(status, SetupStatus.success);

    final signedIn = find.textContaining('Signed-in user: porch');
    await pumpUntil(tester, signedIn);
    expect(signedIn, findsOneWidget);
    expect(none, findsNothing);

    // The inverse: the login goes away while the card is open.
    await tester.runAsync(auth.resetAccount);
    await pumpUntil(tester, none);
    expect(none, findsOneWidget);
    expect(signedIn, findsNothing);
  });

  testWidgets('a read from before the phone\'s login that lands late does '
      'not put "No web login yet" back', (tester) async {
    final slow = _SlowFirstRead(
      db,
      passwordHasher: const PasswordHasher(security: Argon2Security.test),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebLoginSection(auth: slow)),
      ),
    );
    // The opening read has seen "no account" and is now held.
    for (var i = 0; i < 500 && !slow.firstReadDone.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(slow.firstReadDone.isCompleted, isTrue);

    await tester.runAsync(() async {
      final code = await slow.setupTokenForDesktop();
      await slow.setupAccount('porch', 'password123', setupToken: code);
    });
    final signedIn = find.textContaining('Signed-in user: porch');
    await pumpUntil(tester, signedIn);
    expect(signedIn, findsOneWidget);

    // Now the stale "no account" read finishes, last.
    slow.release.complete();
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(signedIn, findsOneWidget);
    expect(find.textContaining('No web login yet'), findsNothing);
  });
}
