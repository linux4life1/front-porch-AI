// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Kabbage/pubspec.yaml reads pubspec.yaml when cwd is Kabbage', () async {
    final root = await Directory.systemTemp.createTemp('Kabbage_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsString('name: kabbage');
    final fs = DeskFs(root.path);
    final out = await fs.dispatch('read', {
      'path': '${p.basename(root.path)}/pubspec.yaml',
    });
    expect(out.ok, isTrue);
    expect(out.output, contains('name: kabbage'));
  });

  test('a real nested folder with the same name still wins', () async {
    final root = await Directory.systemTemp.createTemp('Kabbage_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final nested = Directory(p.join(root.path, p.basename(root.path)));
    await nested.create();
    await File(p.join(nested.path, 'notes.txt')).writeAsString('inner');
    await File(p.join(root.path, 'notes.txt')).writeAsString('outer');
    final fs = DeskFs(root.path);
    final out = await fs.dispatch('read', {
      'path': '${p.basename(root.path)}/notes.txt',
    });
    expect(out.ok, isTrue);
    expect(out.output, 'inner');
  });

  test('loop prompt uses the absolute sit-down path', () async {
    final root = await Directory.systemTemp.createTemp('Kabbage_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(calls: [], text: 'here.'),
    ]);
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: DeskMode.yolo,
    );
    await DeskHarness(session: session, llm: llm).send('list files');
    expect(llm.calls, isNotEmpty);
    expect(llm.calls.first.prompt, contains(root.path));
    expect(llm.calls.first.prompt, contains('Do not prefix'));
    expect(llm.calls.first.prompt, isNot(contains('.desk/')));
  });
}
