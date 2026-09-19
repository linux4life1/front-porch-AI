// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

@Tags(['live', 'stoop_live'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/repository.dart';

/// flutter_test stubs HttpClient to 400. An un-overridden HttpOverrides
/// restores the real client so this suite can talk to the live hub.
class _RealHttpOverrides extends HttpOverrides {}

String? _env(String key) {
  final v = Platform.environment[key]?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Live hub (or the team's real droplet). Never a toy / FakeStoopServer.
///
///   STOOP_TEST_EMAIL=… STOOP_TEST_PASSWORD=… \
///     flutter test --tags stoop_live test/ui/pages/repository/stoop_nsfw_refresh_test.dart
///
/// Optional: STOOP_LIVE_URL (defaults to the live hub), STOOP_TEST_TOTP.
///
/// Red-proved: commenting out the nsfw watch in
/// StoopBrowseView.didChangeDependencies leaves the SFW-only grid after
/// the toggle (the bug in #264).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final email = _env('STOOP_TEST_EMAIL');
  final password = _env('STOOP_TEST_PASSWORD');
  final totp = _env('STOOP_TEST_TOTP');
  final liveUrl = _env('STOOP_LIVE_URL') ?? BackporchApi.defaultBaseUrl;

  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = _RealHttpOverrides());
  tearDown(() => HttpOverrides.global = savedOverrides);

  testWidgets('toggling Show NSFW content reloads the live browse grid', (
    tester,
  ) async {
    final loginEmail = email;
    final loginPassword = password;
    if (loginEmail == null || loginPassword == null) {
      return markTestSkipped(
        'STOOP_TEST_EMAIL / STOOP_TEST_PASSWORD not set — '
        'live Stoop pin skipped, not stubbed',
      );
    }
    SharedPreferences.setMockInitialValues({});
    BackporchApi.overrideBaseUrl = liveUrl;
    addTearDown(() => BackporchApi.overrideBaseUrl = null);

    final auth = AuthState(api: BackporchApi(), store: BackporchAuthStore());
    addTearDown(auth.dispose);

    await tester.runAsync(() async {
      HttpOverrides.global = _RealHttpOverrides();
      await auth.login(email: loginEmail, password: loginPassword, totp: totp);
      if (auth.needsPolicyAcceptance) await auth.acceptPolicy();
    });
    expect(auth.isLoggedIn, isTrue, reason: 'live Stoop login must succeed');

    final originalNsfw = auth.user!.nsfwEnabled;
    addTearDown(() async {
      HttpOverrides.global = _RealHttpOverrides();
      try {
        await auth.setNsfwEnabled(originalNsfw);
      } catch (_) {}
    });

    if (originalNsfw) {
      await tester.runAsync(() async {
        HttpOverrides.global = _RealHttpOverrides();
        await auth.setNsfwEnabled(false);
      });
    }
    expect(auth.user?.nsfwEnabled, isFalse);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      HttpOverrides.global = _RealHttpOverrides();
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthState>.value(
          value: auth,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  actions: [
                    IconButton(
                      tooltip: 'Account',
                      icon: const Icon(Icons.account_circle_outlined),
                      onPressed: () => showStoopAccountSheet(context),
                    ),
                  ],
                ),
                body: const StoopBrowseView(),
              ),
            ),
          ),
        ),
      );
      await _pumpUntilTiles(tester);
    });
    await tester.pumpAndSettle();

    final before = _tileNames(tester);
    expect(
      before,
      isNotEmpty,
      reason: 'live SFW catalog must render at least one card',
    );

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Show NSFW content'), findsOneWidget);

    await tester.runAsync(() async {
      HttpOverrides.global = _RealHttpOverrides();
      await tester.tap(find.text('Show NSFW content'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _pumpUntilTiles(tester);
    });
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    expect(auth.user?.nsfwEnabled, isTrue);
    final after = _tileNames(tester);
    expect(
      after,
      isNot(equals(before)),
      reason:
          'live catalog must change when NSFW turns on '
          '(needs at least one approved NSFW card on the hub)',
    );
  });
}

Set<String> _tileNames(WidgetTester tester) {
  return tester
      .widgetList<StoopCardTile>(find.byType(StoopCardTile))
      .map((t) => t.card.name)
      .toSet();
}

Future<void> _pumpUntilTiles(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    if (find.byType(StoopCardTile).evaluate().isNotEmpty) return;
    if (find.textContaining('Couldn’t load').evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
}
