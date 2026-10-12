// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('waifu_projects_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('three folders become three projects, newest first', () async {
    final store = WaifuStore(dir.path);
    for (final name in ['folder1', 'folder2', 'folder3']) {
      await store.saveLast(
        WaifuSession(
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

  test('loadSession does not return a different folder last_waifu', () async {
    final store = WaifuStore(dir.path);
    final a = p.join(dir.path, 'folderA');
    final b = p.join(dir.path, 'folderB');
    await store.saveLast(
      WaifuSession(
        folderRoot: a,
        coworker: CharacterCard(name: 'Ada'),
        title: 'work in A',
      ),
    );
    await store.saveLast(
      WaifuSession(
        folderRoot: b,
        coworker: CharacterCard(name: 'Mira'),
        title: 'work in B',
      ),
    );
    final aFile = File(
      p.join(dir.path, 'sessions', '${waifuSessionSlug(a)}.json'),
    );
    if (await aFile.exists()) await aFile.delete();
    final loaded = await store.loadSession(a);
    expect(loaded?.folderRoot, isNot(b));
    expect(loaded, isNull);
  });

  test('migrate copies last_waifu into a per-folder session file', () async {
    final store = WaifuStore(dir.path);
    final a = p.join(dir.path, 'folderA');
    await File(p.join(dir.path, kWaifuLastFile)).writeAsString(
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

  group('saved sessions are never silently lost', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('waifu_store_safety_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    String folder(String name) => p.join(root.path, 'work', name);

    test('an unreadable task list does not block the session', () async {
      final store = WaifuStore(p.join(root.path, 'waifu'));
      final toy = folder('toy');
      await store.saveLast(
        WaifuSession(
          folderRoot: toy,
          coworker: CharacterCard(name: 'Iris'),
        ),
      );
      await waifuTodosFile(toy).writeAsBytes([0xff, 0xfe, 0xc3]);
      final back = await store.loadSession(toy);
      expect(back, isNotNull);
      expect(back!.todos.items, isEmpty);
    });

    test('a damaged session file is reported, not treated as empty', () async {
      final store = WaifuStore(p.join(root.path, 'waifu'));
      final toy = folder('toy');
      await Directory(
        p.join(store.directory, 'sessions'),
      ).create(recursive: true);
      await File(
        p.join(store.directory, 'sessions', '${waifuSessionSlug(toy)}.json'),
      ).writeAsString('{"folderRoot": "$toy", "transcript": [');
      await expectLater(
        store.loadSession(toy),
        throwsA(isA<WaifuSessionUnreadable>()),
      );
      expect(await store.loadSession(folder('other')), isNull);
    });

    test('a damaged project list is kept beside the new one', () async {
      final store = WaifuStore(p.join(root.path, 'waifu'));
      await Directory(store.directory).create(recursive: true);
      final index = File(p.join(store.directory, kWaifuProjectsFile));
      await index.writeAsString('[{"folderRoot": "/old/project"');
      expect(await store.listProjects(), isEmpty);
      await store.saveLast(
        WaifuSession(
          folderRoot: folder('toy'),
          coworker: CharacterCard(name: 'Iris'),
        ),
      );
      final kept = File('${index.path}.unreadable');
      expect(await kept.readAsString(), contains('/old/project'));
      expect(await store.listProjects(), hasLength(1));
    });

    test('quick saves from separate stores keep every project', () async {
      final dir = p.join(root.path, 'waifu');
      await Future.wait([
        for (var i = 0; i < 12; i++)
          WaifuStore(dir).saveLast(
            WaifuSession(
              folderRoot: folder('p$i'),
              coworker: CharacterCard(name: 'Iris'),
            ),
          ),
      ]);
      final projects = await WaifuStore(dir).listProjects();
      expect(projects.map((x) => x.folderName).toSet(), {
        for (var i = 0; i < 12; i++) 'p$i',
      });
      final leftovers = Directory(
        dir,
      ).listSync(recursive: true).where((e) => e.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });
  });
}
