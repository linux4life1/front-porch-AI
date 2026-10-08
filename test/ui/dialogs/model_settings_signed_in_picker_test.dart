// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// A signed-in host (SuperGrok) keeps the key box blank on purpose. The
// dialog's model list must still go out with the session's credentials —
// it used to send the blank box and come back "No models available".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Hardware extends FakeHardwareService {
  @override
  bool get cpuOnlyLowPerf => false;
}

class _ModelsManager extends FakeModelManager {
  @override
  get models => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('model list is fetched with the sign-in token when the key '
      'box is blank', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    HttpOverrides.global = null;

    String? seenAuth;
    var requests = 0;
    late final HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (requests++ == 0) seenAuth = req.headers.value('authorization');
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'data': [
              {'id': 'porch-signed-in-model'},
            ],
          }),
        );
        await req.response.close();
      });
    });
    addTearDown(() => server.close(force: true));
    final url = 'http://127.0.0.1:${server.port}/v1';

    final storage = FakeStorageService();
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(url);
    storage.backendSettings.bearerOverlay = (u) =>
        u.startsWith(url) ? 'session-token' : null;
    final llm = FakeLLMProvider(activeBackend: BackendType.openRouter);
    final openRouter = OpenRouterService();
    final mm = _ModelsManager();
    final hw = _Hardware();
    final kobold = FakeKoboldService();
    addTearDown(() {
      storage.dispose();
      llm.dispose();
      openRouter.dispose();
      mm.dispose();
      hw.dispose();
      kobold.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<OpenRouterService>.value(value: openRouter),
          ChangeNotifierProvider<ModelManager>.value(value: mm),
          ChangeNotifierProvider<HardwareService>.value(value: hw),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
        ],
        child: const MaterialApp(home: Material(child: ModelSettingsDialog())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      await tester.tap(find.text('Tap to select a model...'));
      for (var i = 0; i < 100 && requests == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(requests, greaterThan(0), reason: 'the picker never asked');
    expect(seenAuth, 'Bearer session-token');

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('porch-signed-in-model'), findsWidgets);
  });
}
