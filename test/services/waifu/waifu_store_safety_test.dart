// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

/// Saved sessions are never silently lost: a damaged file says so instead
/// of opening blank, and quick saves cannot drop each other's projects.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_store_safety_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  String folder(String name) => p.join(root.path, 'work', name);

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
}
