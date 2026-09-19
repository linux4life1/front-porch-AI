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

/// flutter_test stubs HttpClient to 400. An un-overridden HttpOverrides
/// restores the real client so browse/login/nsfw can hit the loopback
/// server (same pattern as test/services/model_fetch_test.dart).
class _RealHttpOverrides extends HttpOverrides {}

/// The account-sheet NSFW switch must refetch the mounted browse grid.
///
/// Red-proved: commenting out the nsfw watch in StoopBrowseView.didChangeDependencies
/// leaves "Porch Neighbor" on screen after the toggle (the bug in #264).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = _RealHttpOverrides());
  tearDown(() => HttpOverrides.global = savedOverrides);

  late HttpServer server;
  late AuthState auth;
  var cardName = 'Porch Neighbor';
  var nsfw = false;

  Map<String, Object?> _userJson() => {
    'id': 'u1',
    'email': 'a@b.c',
    'displayName': 'Tester',
    'role': 'USER',
    'ageVerified': true,
    'nsfwEnabled': nsfw,
    'acceptedPolicyVersion': '1',
    'twoFactorEnabled': false,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cardName = 'Porch Neighbor';
    nsfw = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/characters') {
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
      } else if (path == '/auth/login') {
        await request.fold<List<int>>([], (b, c) => b..addAll(c));
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'user': _userJson(),
              'accessToken': 'access',
              'refreshToken': 'refresh',
              'policyVersion': '1',
            }),
          );
      } else if (path == '/auth/nsfw') {
        final raw = await request.fold<List<int>>([], (b, c) => b..addAll(c));
        final body = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        nsfw = body['enabled'] == true;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'user': _userJson(), 'policyVersion': '1'}));
      } else if (path == '/auth/me') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'user': _userJson(), 'policyVersion': '1'}));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    BackporchApi.overrideBaseUrl = 'http://127.0.0.1:${server.port}';

    auth = AuthState(api: BackporchApi(), store: BackporchAuthStore());
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
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(find.text('Porch Neighbor'), findsWidgets);

    cardName = 'Adult Neighbor';
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Show NSFW content'), findsOneWidget);

    await tester.runAsync(() async {
      HttpOverrides.global = _RealHttpOverrides();
      await tester.tap(find.text('Show NSFW content'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    expect(auth.user?.nsfwEnabled, isTrue);
    expect(find.text('Adult Neighbor'), findsWidgets);
    expect(find.text('Porch Neighbor'), findsNothing);
  });
}
