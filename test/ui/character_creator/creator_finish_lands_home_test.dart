// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI Character Creator is pushed over whatever page the sidebar was on.
// Save & Finish must land on Home, where the new character is, the way the
// manual creator's Done does, not back on that earlier page (User Personas).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _NoHardware extends ChangeNotifier implements HardwareService {
  @override
  HardwareInfo? get hardwareInfo => null;
  @override
  bool get isDetecting => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the main screen: shows which sidebar page is selected and
/// opens the wizard the way the sidebar's AI Character Creator entry does.
class _MainScreen extends StatelessWidget {
  const _MainScreen();

  @override
  Widget build(BuildContext context) {
    final index = context.watch<AppState>().selectedIndex;
    return Scaffold(
      body: Column(
        children: [
          Text('main page $index'),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CharacterCreatorPage()),
            ),
            child: const Text('open creator'),
          ),
        ],
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Save & Finish from User Personas lands on Home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = FakeStorageService();
    final provider = FakeLLMProvider();
    final personas = FakeUserPersonaService();
    final kobold = KoboldService(storage);
    final models = ModelManager(
      storage,
      DownloadManager(targetDir: Directory.systemTemp.path),
    );
    final hardware = _NoHardware();
    final repo = FakeCharacterRepository();
    final images = ImageGenService(storage);
    final appState = AppState()..setIndex(4); // User Personas
    for (final s in [
      provider,
      storage,
      personas,
      kobold,
      models,
      hardware,
      repo,
      images,
      appState,
    ]) {
      addTearDown(s.dispose);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<LLMProvider>.value(value: provider),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ImageGenService>.value(value: images),
        ],
        child: const MaterialApp(home: _MainScreen()),
      ),
    );
    expect(find.text('main page 4'), findsOneWidget);

    await tester.tap(find.text('open creator'));
    await _settle(tester);
    final dynamic page = tester.state(find.byType(CharacterCreatorPage));
    final state = page.creatorState as CreatorState;

    // A card the Portrait panel already saved, now on Review.
    state.generatedCard = CharacterCard(dbId: 'juniper-db', name: 'Juniper');
    state.currentStep = 6;
    state.notify();
    await _settle(tester);

    final finish = find.text('Save & Finish');
    await tester.ensureVisible(finish);
    await tester.pump();
    await tester.tap(finish);
    await _settle(tester);

    expect(find.text('Juniper created successfully!'), findsOneWidget);
    expect(find.byType(CharacterCreatorPage), findsNothing);
    expect(
      find.text('main page 0'),
      findsOneWidget,
      reason: 'the wizard closes onto Home, not the page it was opened over',
    );
  });
}
