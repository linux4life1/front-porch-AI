// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('desk_projects_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('three folders become three projects, newest first', () async {
    final store = DeskStore(dir.path);
    for (final name in ['folder1', 'folder2', 'folder3']) {
      await store.saveLast(
        DeskSession(
          folderRoot: p.join(dir.path, name),
          coworker: CharacterCard(name: 'Mira'),
          title: 'work in $name',
        ),
      );
    }
    final list = await store.listProjects();
    expect(list, hasLength(3));
    expect(list.map((p) => p.folderName).toList(), [
      'folder3',
      'folder2',
      'folder1',
    ]);
    expect(list.first.title, 'work in folder3');
  });

  test('loadSession does not return a different folder last_desk', () async {
    final store = DeskStore(dir.path);
    final a = p.join(dir.path, 'folderA');
    final b = p.join(dir.path, 'folderB');
    await store.saveLast(
      DeskSession(
        folderRoot: a,
        coworker: CharacterCard(name: 'Ada'),
        title: 'work in A',
      ),
    );
    await store.saveLast(
      DeskSession(
        folderRoot: b,
        coworker: CharacterCard(name: 'Mira'),
        title: 'work in B',
      ),
    );
    final aFile = File(
      p.join(dir.path, 'sessions', '${deskSessionSlug(a)}.json'),
    );
    if (await aFile.exists()) await aFile.delete();
    final loaded = await store.loadSession(a);
    expect(loaded?.folderRoot, isNot(b));
    expect(loaded, isNull);
  });

  test('migrate copies last_desk into a per-folder session file', () async {
    final store = DeskStore(dir.path);
    final a = p.join(dir.path, 'folderA');
    await File(p.join(dir.path, kDeskLastFile)).writeAsString(
      '{"title":"old A","folderRoot":"$a","mode":"build",'
      '"coworker":{"name":"Ada","personality":"","description":"",'
      '"systemPrompt":""},"transcript":[]}',
    );
    final list = await store.listProjects();
    expect(list, hasLength(1));
    expect(list.first.folderRoot, a);
    final loaded = await store.loadSession(a);
    expect(loaded, isNotNull);
    expect(loaded!.coworker.name, 'Ada');
    expect(loaded.title, 'old A');
  });
}
