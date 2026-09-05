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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk_wizard_page.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('desk_wiz_');
    await File(p.join(folder.path, 'pubspec.yaml')).writeAsString('name: toy');
  });

  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  final mira = CharacterCard(
    name: 'Mira',
    personality: 'tsundere, does the work anyway',
  );

  Future<void> pumpWizard(
    WidgetTester tester, {
    bool toolsSupported = true,
    bool isLocalBackend = false,
    void Function(DeskSession session)? onSatDown,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: DeskWizardPage(
          characters: [mira],
          toolsSupported: toolsSupported,
          isLocalBackend: isLocalBackend,
          backendLabel: 'test-model',
          initialFolder: folder.path,
          onSatDown: onSatDown,
          listDirectory: (path) async => DeskFolderListing(
            path: path,
            parentPath: null,
            directories: const [],
            projectHints: const ['pubspec.yaml'],
          ),
        ),
      ),
    );
  }

  Future<void> reachSitDown(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-use-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mira'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-wizard-next')));
    await tester.pumpAndSettle();
  }

  testWidgets('wizard chrome is Project → Coworker → Sit down', (tester) async {
    await pumpWizard(tester);
    await tester.pumpAndSettle();
    expect(find.text('Project'), findsWidgets);
    expect(find.text('Coworker'), findsWidgets);
    expect(find.text('Sit down'), findsWidgets);
    expect(find.text('Use this folder'), findsOneWidget);
  });

  testWidgets('Confirm is dead until the honesty checkbox is ticked', (
    tester,
  ) async {
    DeskSession? sat;
    await pumpWizard(tester, onSatDown: (s) => sat = s);
    await reachSitDown(tester);

    expect(find.textContaining('Claude Code'), findsOneWidget);
    expect(find.textContaining('Grok Build'), findsOneWidget);
    expect(find.textContaining('OpenCode'), findsOneWidget);

    final before = tester.widget<ElevatedButton>(
      find.byKey(const Key('desk-sit-down-confirm')),
    );
    expect(before.onPressed, isNull);

    await tester.ensureVisible(find.byKey(const Key('desk-honesty-checkbox')));
    await tester.tap(find.byKey(const Key('desk-honesty-checkbox')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('desk-sit-down-confirm')));
    final after = tester.widget<ElevatedButton>(
      find.byKey(const Key('desk-sit-down-confirm')),
    );
    expect(after.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('desk-sit-down-confirm')));
    await tester.pumpAndSettle();
    expect(sat, isNotNull);
    expect(sat!.coworker.name, 'Mira');
    expect(sat!.folderRoot, folder.path);
    expect(sat!.mode, DeskMode.build);
  });

  testWidgets('tools-unsupported blocks Sit down even after the checkbox', (
    tester,
  ) async {
    await pumpWizard(tester, toolsSupported: false);
    await reachSitDown(tester);
    expect(find.textContaining('cannot do Desk'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('desk-honesty-checkbox')));
    await tester.tap(find.byKey(const Key('desk-honesty-checkbox')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('desk-sit-down-confirm')));
    final confirm = tester.widget<ElevatedButton>(
      find.byKey(const Key('desk-sit-down-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  test('project step does not import or call FilePicker', () {
    final src = File(
      'lib/ui/desk/desk_wizard_project_step.dart',
    ).readAsStringSync();
    expect(src, isNot(contains('FilePicker')));
    expect(src, isNot(contains('file_picker')));
  });
}
