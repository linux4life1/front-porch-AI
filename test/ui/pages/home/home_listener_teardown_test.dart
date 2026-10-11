// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MainLayout swaps HomePage out of the tree on every sidebar navigation, so
// its State is disposed and rebuilt each visit, while KoboldService,
// CharacterRepository and AppState live for the whole run. A listener Home
// leaves behind keeps a dead _HomePageState (and its caches) alive, one more
// per visit. Here the real HomePage over the real library visits three
// times under providers that stay put, the way MainLayout's do, and each
// notifier must be back to the listeners it had after the first visit.
// The notifiers are the real classes; the subclasses only record who is
// subscribed. A Provider lookup in dispose would throw (the element is
// already deactivated) and fail the swap itself.
// Proven red by dropping each removeListener from HomePage.dispose, and by
// replacing one with a Provider.of lookup.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/pages/home_page.dart';

import '../../../golden/support/fakes.dart';
import '../../../golden/support/fakes_services.dart';
import '../../../helpers/settings_page_harness.dart'
    show IdleClassifier, IdleWebServer;
import 'home_page_harness.dart';

/// Mirrors ChangeNotifier's own bookkeeping: add appends, remove drops the
/// first equal callback and ignores one that is not there.
mixin _Subscribers on ChangeNotifier {
  final List<VoidCallback> subscribers = [];

  @override
  void addListener(VoidCallback listener) {
    subscribers.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    subscribers.remove(listener);
    super.removeListener(listener);
  }
}

class _Kobold extends KoboldService with _Subscribers {
  _Kobold(super.storage);
}

class _Characters extends CharacterRepository with _Subscribers {
  _Characters(super.db, super.storage);
}

class _AppState extends AppState with _Subscribers {}

void main() {
  testWidgets('leaving Home unsubscribes it from every app-scoped notifier', (
    tester,
  ) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    late _Kobold kobold;
    late _Characters characters;
    final appState = _AppState();
    await tester.runAsync(() async {
      kobold = _Kobold(rig.storage);
      characters = _Characters(rig.db, rig.storage);
      await characters.loadCharacters();
    });
    addTearDown(() {
      kobold.dispose();
      characters.dispose();
      appState.dispose();
    });

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget tree(Widget page) => MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: rig.db),
        ChangeNotifierProvider<StorageService>.value(value: rig.storage),
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<KoboldService>.value(value: kobold),
        ChangeNotifierProvider<CharacterRepository>.value(value: characters),
        ChangeNotifierProvider<UserPersonaService>.value(value: rig.personas),
        ChangeNotifierProvider<GroupChatRepository>.value(value: rig.groups),
        ChangeNotifierProvider<FolderService>.value(value: rig.folders),
        ChangeNotifierProvider<WorldRepository>.value(value: rig.worlds),
        ChangeNotifierProvider<ChatService>.value(value: rig.chat),
        ChangeNotifierProvider<LLMProvider>.value(value: rig.llm),
        ChangeNotifierProvider<BackendManager>.value(value: rig.backend),
        ChangeNotifierProvider<OpenRouterService>.value(value: rig.openRouter),
        ChangeNotifierProvider<TtsService>(create: (_) => FakeTtsService()),
        ChangeNotifierProvider<SttService>(create: (_) => FakeSttService()),
        ChangeNotifierProvider<HardwareService>(
          create: (_) => FakeHardwareService(),
        ),
        ChangeNotifierProvider<ModelManager>(create: (_) => FakeModelManager()),
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
      child: MaterialApp(home: Scaffold(body: page)),
    );

    Future<Map<String, int>> visitHome() async {
      await tester.pumpWidget(tree(const HomePage()));
      await tester.pump();
      expect(find.text('Ada'), findsWidgets, reason: 'Home is up');
      await tester.pumpWidget(tree(const SizedBox()));
      await tester.pump();
      expect(find.byType(HomePage), findsNothing);
      // The leftovers must not do anything to a Home that is gone.
      kobold.notifyListeners();
      characters.notifyListeners();
      appState.notifyListeners();
      await tester.pump(const Duration(milliseconds: 300));
      return {
        'KoboldService': kobold.subscribers.length,
        'CharacterRepository': characters.subscribers.length,
        'AppState': appState.subscribers.length,
      };
    }

    final afterFirst = await visitHome();
    await visitHome();
    final afterThird = await visitHome();

    for (final name in afterFirst.keys) {
      expect(
        afterThird[name],
        afterFirst[name],
        reason:
            '$name gained a listener on each Home visit — HomePage.dispose '
            'no longer unsubscribes from it',
      );
    }
  });
}
