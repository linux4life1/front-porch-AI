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

// No dead sliders: Settings → Generation and a chat's own settings show a
// generation setting only when the active backend's requests carry it
// (samplerKnobsFor). test/services/sampler_payload_test.dart pins that table
// to the real payload builders, so together these say the screen matches
// the wire.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

import 'package:front_porch_ai/database/database.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/open_router/open_router.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_generation_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/tabs.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/settings_page_harness.dart';

/// Every backend kind the app can talk to, with the URL that picks it.
const _hosts = <(String, BackendType, String)>[
  ('KoboldCpp', BackendType.kobold, ''),
  ('oMLX', BackendType.omlx, ''),
  ('a remote API', BackendType.openRouter, 'https://openrouter.ai/api/v1'),
  ('api.openai.com', BackendType.openRouter, 'https://api.openai.com/v1'),
  ('xAI', BackendType.openRouter, 'https://api.x.ai/v1'),
];

/// The Settings → Generation label of each knob.
const _settingsLabels = {
  SamplerKnob.minP: ['Min-P'],
  SamplerKnob.topK: ['Top-K'],
  SamplerKnob.repeatPenalty: ['Repeat Penalty'],
  SamplerKnob.repeatPenaltyTokens: ['Repeat Penalty Tokens'],
  SamplerKnob.xtc: ['XTC Threshold', 'XTC Probability'],
  SamplerKnob.dry: ['DRY Strength'],
  SamplerKnob.dynamicTemp: ['Dynamic Temperature'],
  SamplerKnob.bannedPhrases: ['Banned Phrases'],
};

/// The same knobs in a chat's own settings, which has no banned phrases.
const _chatLabels = {
  SamplerKnob.minP: ['Min-P'],
  SamplerKnob.topK: ['Top-K'],
  SamplerKnob.repeatPenalty: ['Repeat Penalty'],
  SamplerKnob.repeatPenaltyTokens: ['Rep Pen Tokens'],
  SamplerKnob.xtc: ['XTC Threshold', 'XTC Probability'],
  SamplerKnob.dry: ['DRY Strength'],
  SamplerKnob.dynamicTemp: ['Dynamic Temperature'],
};

const _always = ['Temperature', 'Top-P', 'Max Output Tokens', 'Context Size'];

Future<SettingsPageRig> _rigFor(
  WidgetTester tester,
  BackendType backend,
  String url,
) => buildRig(
  tester,
  lastUsedIsB: false,
  before: (rig) async {
    await rig.store.backendSettings.setBackendType(backend.name);
    await rig.store.backendSettings.setRemoteApiUrl(url);
  },
);

void _expectShownExactly(
  Map<SamplerKnob, List<String>> labels,
  Set<SamplerKnob> knobs,
  String host,
) {
  for (final label in _always) {
    expect(find.text(label), findsOneWidget, reason: '$label on $host');
  }
  for (final MapEntry(key: knob, value: names) in labels.entries) {
    for (final label in names) {
      expect(
        find.text(label),
        knobs.contains(knob) ? findsOneWidget : findsNothing,
        reason: '$label on $host',
      );
    }
  }
}

void main() {
  group('Settings → Generation shows only what the backend receives', () {
    for (final (host, backend, url) in _hosts) {
      testWidgets(host, (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final rig = await _rigFor(tester, backend, url);
        final phrases = TextEditingController();
        addTearDown(phrases.dispose);
        await tester.pumpWidget(
          withRigProviders(
            rig,
            child: ChangeNotifierProvider<LLMProvider>.value(
              value: FakeLLMProvider(activeBackend: backend),
              child: MaterialApp(
                home: Scaffold(
                  body: GenerationTab(bannedPhrasesController: phrases),
                ),
              ),
            ),
          ),
        );
        await settle(tester);

        _expectShownExactly(
          _settingsLabels,
          samplerKnobsFor(backend, remoteApiUrl: url),
          host,
        );
      });
    }
  });

  group('a chat\'s own settings show only what the backend receives', () {
    for (final (host, backend, url) in _hosts) {
      testWidgets(host, (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final rig = await _rigFor(tester, backend, url);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatSettingsGenerationSection(
                  gen: ChatGenerationSettings(),
                  storage: rig.store,
                  llmProvider: FakeLLMProvider(activeBackend: backend),
                  isRemote: backend != BackendType.kobold,
                  onChanged: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        _expectShownExactly(
          _chatLabels,
          samplerKnobsFor(backend, remoteApiUrl: url),
          host,
        );
      });
    }
  });

  test('the table: KoboldCpp gets everything, xAI only the basics', () {
    expect(
      samplerKnobsFor(BackendType.kobold, remoteApiUrl: ''),
      SamplerKnob.values.toSet(),
    );
    expect(
      samplerKnobsFor(BackendType.openRouter, remoteApiUrl: kOmlxApiUrl),
      samplerKnobsFor(BackendType.omlx, remoteApiUrl: ''),
      reason: 'oMLX reached through Remote API is still oMLX on the wire',
    );
    expect(
      samplerKnobsFor(
        BackendType.openRouter,
        remoteApiUrl: 'https://api.x.ai/v1',
      ),
      isEmpty,
    );
  });

  test('the phone is told the same list: GET /api/settings on oMLX', () async {
    final root = await Directory.systemTemp.createTemp('fpai sampler knobs');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase.forTesting();
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final storage = StorageService();
    await storage.initialized;
    final router = shelf_router.Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, _OmlxLlm()),
      ),
      router,
    );

    final res = await router.call(
      shelf.Request('GET', Uri.parse('http://localhost/api/settings')),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(body['samplerKnobs'], [
      for (final k in samplerKnobsFor(BackendType.omlx, remoteApiUrl: ''))
        k.name,
    ]);
  });
}

class _OmlxLlm extends FakeLLMProvider {
  _OmlxLlm() : super(activeBackend: BackendType.omlx);
  final OpenRouterService remote = OpenRouterService();
  @override
  OpenRouterService get openRouterService => remote;
}
