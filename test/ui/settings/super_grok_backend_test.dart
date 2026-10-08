// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// xAI in Settings → Backend: SuperGrok sign-in is the main path. The key
// box stays tucked away until asked for (or a key is already saved), and a
// signed-in session hides it entirely.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/xai/xai.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/remote_api_section.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _Store extends FakeStorageService {
  _Store() {
    _backend.initializeBase(null, notifyListeners);
    _backend.setBackendType('openRouter');
    _backend.setRemoteApiUrl(kXaiApiV1);
  }

  final BackendSettings _backend = BackendSettings();

  @override
  BackendSettings get backendSettings => _backend;
}

class _Llm extends FakeLLMProvider {
  _Llm(this.superGrok) : super(activeBackend: BackendType.openRouter);

  @override
  final SuperGrokAuth superGrok;
}

SuperGrokAuth _auth({String? session}) =>
    SuperGrokAuth(readSession: () => session, writeSession: (_) async {});

Future<_Store> _pump(WidgetTester tester, SuperGrokAuth auth) async {
  final store = _Store();
  final url = TextEditingController(text: kXaiApiV1);
  final key = TextEditingController();
  addTearDown(url.dispose);
  addTearDown(key.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: store),
        ChangeNotifierProvider<LLMProvider>.value(value: _Llm(auth)),
        ChangeNotifierProvider<OpenRouterService>.value(
          value: OpenRouterService(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteApiSection(
              apiUrlController: url,
              apiKeyController: key,
              availableModels: const [],
              onModelsFetched: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return store;
}

void main() {
  testWidgets('signed out: sign-in shows, the key box waits to be asked', (
    tester,
  ) async {
    final auth = _auth();
    addTearDown(auth.dispose);
    await _pump(tester, auth);

    expect(find.byKey(const Key('super-grok-sign-in')), findsOneWidget);
    expect(find.text('xAI API Key'), findsNothing);

    await tester.tap(find.byKey(const Key('super-grok-use-key')));
    await tester.pump();
    expect(find.text('xAI API Key'), findsOneWidget);
    expect(find.byKey(const Key('super-grok-use-key')), findsNothing);
  });

  testWidgets('a saved xAI key shows its box without asking', (tester) async {
    final auth = _auth();
    addTearDown(auth.dispose);
    final store = await _pump(tester, auth);
    await store.backendSettings.setRemoteApiKey('xai-saved');
    await tester.pump();
    expect(find.text('xAI API Key'), findsOneWidget);
  });

  testWidgets('signed in: no key box at all', (tester) async {
    final auth = _auth(
      session: XaiTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        email: 'porch@example.com',
      ).encode(),
    );
    addTearDown(auth.dispose);
    await tester.runAsync(auth.load);
    await _pump(tester, auth);

    expect(find.byKey(const Key('super-grok-signed-in')), findsOneWidget);
    expect(find.text('Signed in as porch@example.com'), findsOneWidget);
    expect(find.text('xAI API Key'), findsNothing);
    expect(find.byKey(const Key('super-grok-use-key')), findsNothing);
  });
}
