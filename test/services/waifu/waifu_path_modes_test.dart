// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory root;
  late File outside;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('waifu_scope_');
    root = await Directory(p.join(sandbox.path, 'project')).create();
    outside = File(p.join(sandbox.path, 'outside.txt'));
    await outside.writeAsString('ordinary outside file');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'folder jail contains lexical, absolute, and realpath escapes',
    () async {
      expect(
        WaifuSession(
          folderRoot: root.path,
          coworker: CharacterCard(name: 'Iris'),
        ).pathMode,
        WaifuPathMode.folderJail,
      );
      for (final path in ['../outside.txt', outside.path, '~/.config']) {
        expect(
          WaifuJail.resolve(
            root.path,
            path,
            pathMode: WaifuPathMode.folderJail,
          ).ok,
          isFalse,
          reason: path,
        );
      }
      final alias = Link(p.join(root.path, 'outside-link'));
      await alias.create(outside.path);
      final linked = await WaifuJail.resolveLive(
        root.path,
        alias.path,
        pathMode: WaifuPathMode.folderJail,
      );
      expect(linked.ok, isFalse);
      expect(linked.error, contains('jail'));
    },
  );

  test(
    'whole-disk mode resolves parent, absolute, and symlink paths',
    () async {
      final alias = Link(p.join(root.path, 'outside-link'));
      await alias.create(outside.path);
      final canonicalOutside = await outside.resolveSymbolicLinks();
      for (final path in ['../outside.txt', outside.path, alias.path]) {
        final hit = await WaifuJail.resolveLive(
          root.path,
          path,
          pathMode: WaifuPathMode.wholeDisk,
        );
        expect(hit.ok, isTrue, reason: path);
        expect(hit.path, canonicalOutside, reason: path);
      }
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        final hit = WaifuJail.resolve(
          root.path,
          '~',
          pathMode: WaifuPathMode.wholeDisk,
        );
        expect(hit.ok, isTrue);
        expect(p.normalize(hit.path!), p.normalize(home));
      }
    },
  );

  test('empty path is a plain error in either mode', () {
    for (final mode in WaifuPathMode.values) {
      final hit = WaifuJail.resolve(root.path, '', pathMode: mode);
      expect(hit.ok, isFalse);
      expect(hit.error, 'path is empty');
      expect(hit.error, isNot(contains('jail')));
    }
  });

  test('honesty, Yolo, MCP, and tool copy tell the selected truth', () {
    final jailed = waifuHonestyBody(WaifuPathMode.folderJail);
    final open = waifuHonestyBody(WaifuPathMode.wholeDisk);
    expect(jailed, contains('safer default'));
    expect(jailed, contains('stay inside'));
    expect(open, contains('starting porch, not a fence'));
    expect(open, contains('absolute paths, ~, .., and cd'));

    expect(
      waifuYoloWarning(WaifuPathMode.folderJail),
      contains('folder jail still holds'),
    );
    expect(waifuYoloWarning(WaifuPathMode.wholeDisk), contains('whole disk'));
    expect(
      waifuYoloWarning(WaifuPathMode.wholeDisk),
      isNot(contains('jail still holds')),
    );
    expect(
      waifuMcpScopeWarning(WaifuPathMode.folderJail),
      contains('folder jail covers'),
    );
    expect(
      waifuMcpScopeWarning(WaifuPathMode.wholeDisk),
      contains('Whole-disk access is already open'),
    );
  });
}
