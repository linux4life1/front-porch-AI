// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import '../../helpers/expression_workspace_harness.dart' as fixture;
import '../../golden/support/fakes.dart';

class NavigationBackend extends ChangeNotifier implements BackendManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({AppState state, ImageGenService image})> pumpShell(
  WidgetTester tester,
  fixture.WorkspaceRig rig,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.runAsync(
    () => rig.storage.backendSettings.setBackendType('openRouter'),
  );
  final state = AppState()..setIndex(5);
  final image = ImageGenService(rig.storage);
  await tester.runAsync(() => image.batches.ready);
  final backend = NavigationBackend();
  final worlds = FakeWorldRepository();
  final update = FakeUpdateService();
  addTearDown(() {
    state.dispose();
    image.dispose();
    backend.dispose();
    worlds.dispose();
    update.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<StorageService>.value(value: rig.storage),
        ChangeNotifierProvider<CharacterRepository>.value(
          value: rig.repository,
        ),
        ChangeNotifierProvider<ImageGenService>.value(value: image),
        ChangeNotifierProvider<BackendManager>.value(value: backend),
        ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ChangeNotifierProvider<UpdateService>.value(value: update),
      ],
      child: const MaterialApp(home: MainLayout()),
    ),
  );
  return (state: state, image: image);
}

void main() {
  testWidgets(
    'sidebar opens the shared Image Studio, whose Batch tab is the real queue',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      final shell = await pumpShell(tester, rig);
      expect(find.byType(WorldManagementPage), findsOneWidget);
      await tester.tap(find.text('Image Studio'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ImageStudio), findsOneWidget);
      // A dialog over the page, not a page of its own.
      expect(shell.state.selectedIndex, 5);
      await tester.tap(find.text('Batch'));
      await tester.pump();
      await tester.runAsync(() => shell.image.batches.ready);
      await tester.pump();
      expect(find.byType(ImageBatchesPage), findsOneWidget);
      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Backend and model'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Image Studio opened from Home picks its Character subject from the library',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await pumpShell(tester, rig);
      await tester.tap(find.text('Image Studio'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Character…'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Choose a character'), findsOneWidget);
      await tester.tap(find.text('First card'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Choose a character'), findsNothing);
      final subject = find.widgetWithText(OutlinedButton, 'First card');
      expect(subject, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
