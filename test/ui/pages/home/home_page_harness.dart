// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The real HomePage over a real library: StorageService on a temp root,
// an in-memory Drift database, the real Character / Group / Folder / World
// repositories and a real ChatService. ChatPage pushes for real on a tap.
// Only services the tap never reaches (TTS, STT, image, update, hardware)
// are the golden doubles.

import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/pages/home_page.dart';

import '../../../golden/support/fakes.dart';
import '../../../golden/support/fakes_services.dart';
import '../../../helpers/settings_page_harness.dart'
    show IdleClassifier, IdleWebServer;

class HomeRig {
  HomeRig._(
    this.root,
    this.db,
    this.storage,
    this.characters,
    this.groups,
    this.folders,
    this.personas,
    this.worlds,
    this.kobold,
    this.chat,
    this.llm,
    this.openRouter,
    this.backend,
  );

  final Directory root;
  final AppDatabase db;
  final StorageService storage;
  final CharacterRepository characters;
  final GroupChatRepository groups;
  final FolderService folders;
  final UserPersonaService personas;
  final WorldRepository worlds;
  final KoboldService kobold;
  final ChatService chat;
  final LLMProvider llm;
  final OpenRouterService openRouter;
  final BackendManager backend;

  /// Builds the library inside [tester.runAsync]; [seed] runs against the
  /// database before the repositories load.
  static Future<HomeRig> build(
    WidgetTester tester, {
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    // HomePage's activity cache opens the app singleton beside this one.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    late HomeRig rig;
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp('fpai_home_rig_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path,
          );
      SharedPreferences.setMockInitialValues({
        'backend_type': 'openRouter',
        'character_evolution_enabled': false,
      });
      final storage = StorageService();
      await storage.initialized;
      final db = AppDatabase.forTesting(sameIsolate: true);
      await seed?.call(db);
      final characters = CharacterRepository(db, storage);
      await characters.loadCharacters();
      final groups = GroupChatRepository(storage, db);
      final folders = FolderService(db);
      await folders.reload();
      final personas = UserPersonaService(db);
      final worlds = WorldRepository(storage, db)
        ..setCharacterRepository(characters)
        ..setGroupChatRepository(groups);
      final kobold = KoboldService(storage);
      final openRouter = OpenRouterService();
      final backend = BackendManager(storage);
      final llm = LLMProvider(kobold, openRouter, storage, backend);
      final chat = ChatService(kobold, personas, storage, worlds)
        ..setDatabase(db)
        ..setLLMProvider(llm)
        ..setCharacterRepository(characters)
        ..setGroupChatRepository(groups);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      rig = HomeRig._(
        root,
        db,
        storage,
        characters,
        groups,
        folders,
        personas,
        worlds,
        kobold,
        chat,
        llm,
        openRouter,
        backend,
      );
    });
    addTearDown(() => tester.runAsync(rig._dispose));
    return rig;
  }

  Future<void> _dispose() async {
    chat.dispose();
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
      await db.customSelect('SELECT 1').get();
    }
    await db.close();
    kobold.dispose();
    await root.delete(recursive: true);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<AppState>(create: (_) => AppState()),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<CharacterRepository>.value(value: characters),
          ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<FolderService>.value(value: folders),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<BackendManager>.value(value: backend),
          ChangeNotifierProvider<OpenRouterService>.value(value: openRouter),
          ChangeNotifierProvider<TtsService>(create: (_) => FakeTtsService()),
          ChangeNotifierProvider<SttService>(create: (_) => FakeSttService()),
          ChangeNotifierProvider<HardwareService>(
            create: (_) => FakeHardwareService(),
          ),
          ChangeNotifierProvider<ModelManager>(
            create: (_) => FakeModelManager(),
          ),
          ChangeNotifierProvider<ImageGenService>(
            create: (_) => FakeImageGenService(),
          ),
          ChangeNotifierProvider<UpdateService>(
            create: (_) => FakeUpdateService(),
          ),
          ChangeNotifierProvider<ExpressionClassifierService>(
            create: (_) => IdleClassifier(),
          ),
          ChangeNotifierProvider<WebServerHost>(create: (_) => IdleWebServer()),
        ],
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );
    await tester.pump();
  }
}

/// A 1:1 character row whose portrait basename is [file].
Future<String> seedCharacter(AppDatabase db, String name, String file) =>
    db.insertCharacterReturningId(
      CharactersCompanion(name: Value(name), imagePath: Value(file)),
    );
