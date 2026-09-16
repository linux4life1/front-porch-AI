// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tools-incapable model: Generate/Next is blocked. Copy names a tool-calling
// model. Proven: flipping toolsAdvertised to true re-enables Next.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_page.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

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

class _SetupCapableStorage extends FakeStorageService {
  @override
  int get kvQuantizationLevel => 0;
  @override
  bool get kcppsHasModel => false;
  @override
  bool get kcppsModelFileExists => false;
  @override
  String get backendType => 'kobold';
  @override
  String get remoteApiUrl => '';
}

WorldFromWikiState _worldOf(WidgetTester tester) {
  final dynamic pageState = tester.state(find.byType(WorldFromWikiPage));
  return pageState.worldState as WorldFromWikiState;
}

ButtonStyleButton _next(WidgetTester tester) => tester
    .widget<ButtonStyleButton>(find.byKey(const Key('world-from-wiki-next')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tools-incapable model blocks Next and shows copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final llm = FakeLLMProvider();
    final storage = _SetupCapableStorage();
    final personas = FakeUserPersonaService();
    final kobold = KoboldService(storage);
    final models = ModelManager(
      storage,
      DownloadManager(targetDir: Directory.systemTemp.path),
    );
    final hardware = _NoHardware();
    for (final s in [llm, storage, personas, kobold, models, hardware]) {
      addTearDown(s.dispose);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
        ],
        child: const MaterialApp(home: WorldFromWikiPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('world-from-wiki-tools-copy')), findsOneWidget);
    expect(find.textContaining('Qwen 27B'), findsOneWidget);
    expect(_next(tester).onPressed, isNull);

    final world = _worldOf(tester);
    expect(world.toolsAdvertised, isFalse);

    world.toolsAdvertised = true;
    world.notify();
    await tester.pump();

    expect(_next(tester).onPressed, isNotNull);
    expect(kWorldFromWikiToolsCopy, contains('tool-calling'));
  });
}
