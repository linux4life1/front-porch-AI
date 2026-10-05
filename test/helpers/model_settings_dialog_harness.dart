// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The real Model Settings dialog (the one chat opens) on the local backend,
// over the same two models, engine folder and doubles as the Settings page
// tests (see settings_page_harness.dart): the launch is real, and only the
// engine start is recorded.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

import 'settings_page_harness.dart';

/// Opens the dialog over [buildRig]'s two models.
Future<SettingsPageRig> openModelSettings(
  WidgetTester tester, {
  required bool lastUsedIsB,
  Future<void> Function(SettingsPageRig rig)? before,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final rig = await buildRig(tester, lastUsedIsB: lastUsedIsB, before: before);
  await tester.pumpWidget(
    withRigProviders(
      rig,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ModelSettingsDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
  return rig;
}

/// Presses the dialog's start button. The model check reads the real file and
/// the dialog then waits a second for the port, so the tap runs in real time.
Future<void> pressDialogStart(WidgetTester tester, String label) async {
  final start = find.text(label);
  await tester.ensureVisible(start);
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tap(start);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
  });
  await tester.pump(const Duration(milliseconds: 300));
}
