// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/repository.dart';

/// The account-sheet NSFW switch must refetch the mounted browse grid.
///
/// Red-proved: commenting out the nsfw watch in StoopBrowseView.didChangeDependencies
/// leaves "Porch Neighbor" on screen after the toggle (the bug in #264).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late AuthState auth;
  var cardName = 'Porch Neighbor';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cardName = 'Porch Neighbor';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/characters') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'total': 1,
              'page': 0,
              'items': [
                {
                  'id': 'card-1',
                  'name': cardName,
                  'summary': 'A neighbor on the porch.',
                  'type': 'SOLO',
                  'nsfw': cardName != 'Porch Neighbor',
                  'score': 0,
                  'downloadCount': 0,
                  'modPick': false,
                },
              ],
            }),
          );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    BackporchApi.overrideBaseUrl = 'http://127.0.0.1:${server.port}';

    auth = AuthState(api: _AuthApi(), store: BackporchAuthStore());
    await auth.login(email: 'a@b.c', password: 'secret');
  });

  tearDown(() async {
    BackporchApi.overrideBaseUrl = null;
    auth.dispose();
    await server.close(force: true);
  });

  testWidgets('toggling Show NSFW content reloads the browse grid', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    await tester.pumpAndSettle();
    expect(find.text('Porch Neighbor'), findsWidgets);

    cardName = 'Adult Neighbor';
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Show NSFW content'), findsOneWidget);

    await tester.tap(find.text('Show NSFW content'));
    await tester.pumpAndSettle();

    expect(auth.user?.nsfwEnabled, isTrue);
    expect(find.text('Adult Neighbor'), findsWidgets);
    expect(find.text('Porch Neighbor'), findsNothing);
  });
}

class _AuthApi extends BackporchApi {
  bool nsfw = false;

  BackporchUser _user() => BackporchUser(
    id: 'u1',
    email: 'a@b.c',
    displayName: 'Tester',
    role: 'USER',
    ageVerified: true,
    nsfwEnabled: nsfw,
    acceptedPolicyVersion: '1',
    twoFactorEnabled: false,
  );

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
    String? installId,
    String? totp,
  }) async {
    return AuthResult(
      user: _user(),
      accessToken: 'access',
      refreshToken: 'refresh',
      policyVersion: '1',
    );
  }

  @override
  Future<({BackporchUser user, String policyVersion})> setNsfwEnabled(
    String accessToken,
    bool enabled,
  ) async {
    nsfw = enabled;
    return (user: _user(), policyVersion: '1');
  }
}
