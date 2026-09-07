// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';

void main() {
  late Directory storeDir;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('desk_sit_save_');
  });

  tearDown(() async {
    if (await storeDir.exists()) await storeDir.delete(recursive: true);
  });

  testWidgets('sitting down parks the folder before any chat turn', (
    tester,
  ) async {
    final store = DeskStore(storeDir.path);
    final session = DeskSession(
      folderRoot: '/tmp/new-project',
      coworker: CharacterCard(name: 'Iris'),
    );
    late List<DeskProject> list;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DeskPage(session: session, store: store),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      list = await store.listProjects();
    });
    await tester.pump();
    expect(list, hasLength(1));
    expect(list.single.folderName, 'new-project');
    expect(list.single.coworker.name, 'Iris');
  });
}
