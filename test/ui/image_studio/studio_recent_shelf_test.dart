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

// Issue #667: the desktop Studio's Recent shelf shows pictures kept on disk,
// so a picture made before the Studio closed is there when it opens again.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart'
    show
        BackendManager,
        ImageGenMode,
        ImageGenService,
        KoboldService,
        LLMProvider,
        OpenRouterService;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';
import 'package:front_porch_ai/ui/image_studio/studio_expression_tab.dart';
import 'package:front_porch_ai/ui/image_studio/studio_recent_shelf.dart';

// A real PNG (1x1) so the thumbnail decodes.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, //
  0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

void main() {
  late Directory root;
  late StorageService storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fpai_shelf_');
    storage = StorageService.sandbox(root.path);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Widget host(Widget child) => ChangeNotifierProvider<StorageService>.value(
    value: storage,
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 600, child: child)),
    ),
  );

  // The shelf reads the disk as it mounts; mount it on the real clock so
  // that read finishes.
  Future<void> mount(WidgetTester tester, Widget shelf) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(shelf));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
  }

  testWidgets('pictures kept before the Studio opened come back on tap', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await rememberStudioResult(
        storage,
        _png,
        prompt: 'porch swing at dusk',
        edit: false,
      );
      await rememberStudioResult(
        storage,
        _png,
        prompt: 'make her laugh',
        edit: true,
      );
    });
    StudioRecentEntry? restored;
    Uint8List? bytes;
    await mount(
      tester,
      StudioRecentShelf(
        onRestore: (entry, b) {
          restored = entry;
          bytes = b;
        },
      ),
    );

    expect(find.text('Recent · 2 of 50'), findsOneWidget);
    final listed = await tester.runAsync(
      () => StudioRecentStore.of(storage).list(),
    );
    final older = listed!.last;
    await tester.tap(find.byKey(ValueKey('studio-recent-${older.name}')));
    await settle(tester);

    expect(restored?.prompt, 'porch swing at dusk');
    expect(bytes, _png);
  });

  testWidgets('a picture made while the shelf is open appears on it', (
    tester,
  ) async {
    await mount(tester, StudioRecentShelf(onRestore: (entry, bytes) {}));
    expect(find.textContaining('Pictures you make land here'), findsOneWidget);

    await tester.runAsync(
      () => rememberStudioResult(storage, _png, prompt: 'new', edit: false),
    );
    await settle(tester);
    expect(find.text('Recent · 1 of 50'), findsOneWidget);
  });

  testWidgets('choosing Off hides unstarred pictures and stores the choice', (
    tester,
  ) async {
    await tester.runAsync(
      () => rememberStudioResult(storage, _png, prompt: 'one', edit: false),
    );
    await mount(tester, StudioRecentShelf(onRestore: (entry, bytes) {}));
    await tester.tap(find.byKey(const Key('studio-recent-limit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off · only what I save').last);
    await tester.pumpAndSettle();
    await settle(tester);

    expect(storage.imageGenSettings.studioRecentLimit, 0);
    expect(find.text('Recent · off'), findsOneWidget);
    expect(find.textContaining('Recent is off'), findsOneWidget);
  });

  // Issue #775: a picture made outside the Studio (here a character creator
  // draft the generator kept) is on the shelf, and once brought back it can
  // be the Create reference and the expression pack's source.
  testWidgets('a picture kept elsewhere comes back as a reference and source', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path,
        );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
    await storage.imageGenSettings.setImageGenBackend('a1111');
    final draft = await tester.runAsync(() async {
      keepGeneratedPicture(
        storage,
        _png,
        prompt: 'a creator draft',
        edit: false,
      );
      return (await StudioRecentStore.of(storage).list()).single;
    });
    await tester.binding.setSurfaceSize(const Size(1040, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final llm = LLMProvider(
      KoboldService(storage),
      OpenRouterService(),
      storage,
      BackendManager(storage),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>(
              create: (_) => ImageGenService(storage),
            ),
            ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ImageStudio(
                mode: ImageGenMode.characterPortrait,
                characterName: 'Ada',
                characterDbId: 'ada-id',
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);

    final useLast = find.widgetWithText(
      TextButton,
      'Use the last picture I made',
    );
    expect(tester.widget<TextButton>(useLast).onPressed, isNull);

    final thumb = find.byKey(ValueKey('studio-recent-${draft!.name}'));
    await tester.ensureVisible(thumb);
    await tester.tap(thumb);
    await settle(tester);
    final pack = tester.widget<StudioExpressionTab>(
      find.byType(StudioExpressionTab, skipOffstage: false),
    );
    expect(pack.lastStudioImage, _png);

    await tester.ensureVisible(useLast);
    await tester.tap(useLast);
    await tester.pump();
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('How different from the photo?'), findsOneWidget);
    // Let the thumbnail's tooltip delay run out before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
