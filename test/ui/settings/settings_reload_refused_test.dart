// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A model or preset picked on Settings -> Backend while KoboldCpp runs goes
// into the running engine at once. When KoboldCpp could not load it, the old
// model keeps running and the reload answers with a refusal that says so. The
// page shows those words in a snackbar, the way a Start shows its own
// reasons, instead of dropping the answer.
//
// The real Settings page; the engine is marked running and the live reload is
// counted and answers as the test says (see settings_page_harness.dart).
// What a refusal holds is pinned where it is made, in
// kobold_reload_keeps_engine_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/settings_page_harness.dart';

const _words =
    'The new model was not loaded. The previous one is still running. '
    'Not a valid GGUF model file.';

void main() {
  Finder modelDropdown() => find.descendant(
    of: find.byType(ModelSelector),
    matching: find.byType(DropdownButton<String>),
  );
  Finder presetDropdown() => find.descendant(
    of: find.byType(KcppsSelector),
    matching: find.byType(DropdownButton<String>),
  );

  /// Settings -> Backend over two models and one preset, with KoboldCpp
  /// running and a reload that answers with [answer].
  Future<SettingsPageRig> backendTab(
    WidgetTester tester,
    KoboldLaunchResult? answer,
  ) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        File(
          p.join(rig.store.binDir.path, 'list.kcpps'),
        ).writeAsStringSync(jsonEncode({'contextsize': 8192}));
        rig.kobold.debugMarkProcessRunning();
        rig.llm.answer = () async => answer;
      },
    );
    await openTab(tester, 'Backend');
    // The hardware-detected snackbar from opening the page goes first.
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump();
    return rig;
  }

  testWidgets('a model KoboldCpp could not load: the page says why in a '
      'snackbar', (tester) async {
    final rig = await backendTab(
      tester,
      const KoboldLaunchResult.refused(_words),
    );

    await pickFromDropdown(tester, modelDropdown(), p.basename(rig.b));
    await settle(tester, () => rig.llm.reloads > 0);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      rig.llm.reloads,
      1,
      reason: 'the running engine was asked to load it',
    );
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_words), findsOneWidget);
  });

  testWidgets('a preset KoboldCpp could not load: the page says why, after '
      'the message that it was saved', (tester) async {
    final rig = await backendTab(
      tester,
      const KoboldLaunchResult.refused(_words),
    );

    await pickFromDropdown(tester, presetDropdown(), 'list.kcpps');
    await settle(tester, () => rig.llm.reloads > 0);
    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    );
    messenger.hideCurrentSnackBar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(_words), findsOneWidget);
  });

  testWidgets('a reload with nothing to report says nothing', (tester) async {
    final rig = await backendTab(tester, null);

    await pickFromDropdown(tester, modelDropdown(), p.basename(rig.b));
    await settle(tester, () => rig.llm.reloads > 0);
    await tester.pump(const Duration(milliseconds: 100));

    expect(rig.llm.reloads, 1);
    expect(find.byType(SnackBar), findsNothing);
  });
}
