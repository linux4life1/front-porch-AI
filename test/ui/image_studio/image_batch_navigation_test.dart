// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import '../../helpers/expression_workspace_harness.dart' as fixture;
import '../../golden/support/fakes.dart';

class NavigationBackend extends ChangeNotifier implements BackendManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'sidebar navigates from Worlds into the real batch page and service',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
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
      expect(find.byType(WorldManagementPage), findsOneWidget);
      await tester.tap(find.text('Image batches'));
      await tester.pump();
      await tester.runAsync(() => image.batches.ready);
      await tester.pump();
      expect(state.selectedIndex, 6);
      expect(find.byType(ImageBatchesPage), findsOneWidget);
      expect(find.text('Prepare'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
