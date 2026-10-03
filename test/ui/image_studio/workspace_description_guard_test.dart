// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'expression_workspace_test.dart' as fixture;

void main() {
  testWidgets('Create pack needs a description before making images', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await fixture.pumpWorkspace(tester, rig);
    await tester.tap(find.text('Expressions'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('expression-description')), '');
    await tester.pump();
    await tester.ensureVisible(find.text('Start (8)'));
    await tester.tap(find.text('Start (8)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a pack description before generating.'),
      findsOneWidget,
    );
    expect(rig.image.calls, isEmpty);
  });
}
