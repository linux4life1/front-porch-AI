// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import '../../helpers/expression_workspace_harness.dart' as fixture;

void main() {
  testWidgets('Select visible ticks every card the search shows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rig = await fixture.workspaceRig(tester);
    late ImageBatchService queue;
    await tester.runAsync(() async {
      queue = ImageBatchService(rig.storage, rig.image);
      await queue.ready;
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(
            value: rig.repository,
          ),
        ],
        child: MaterialApp(home: ImageBatchesPage(queue: queue)),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    await tester.tap(find.text('Select visible'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Prepare for 2 characters'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Find characters'),
      'second',
    );
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    await tester.tap(find.text('Select visible'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Prepare for 1 character'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
