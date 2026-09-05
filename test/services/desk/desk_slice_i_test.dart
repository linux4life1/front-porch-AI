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

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_i_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('no toggle means zero HTTP on sit-down', () async {
    var hits = 0;
    File(p.join(root.path, 'project.godot')).writeAsStringSync('');
    final langs = DeskLangRuntime(
      directory: p.join(root.path, 'lang'),
      fetch: (url) async {
        hits++;
        return DeskLangBytes(url, <int>[1, 2, 3]);
      },
    );
    final suggested = await deskDetectLangs(root.path);
    expect(suggested, contains('gdscript'));
    expect(hits, 0);
    expect(langs.enabled, isEmpty);
  });

  test('Godot marker suggests Godot, not Rust', () async {
    File(p.join(root.path, 'project.godot')).writeAsStringSync('');
    final ids = await deskDetectLangs(root.path);
    expect(ids, contains('gdscript'));
    expect(ids, isNot(contains('rust')));
  });

  test('enabling one entry does not fetch others', () async {
    final fetched = <String>[];
    final py = utf8Bytes('py-lsp');
    final langs = DeskLangRuntime(
      directory: p.join(root.path, 'lang'),
      catalog: [
        DeskLangDoor(
          id: 'python',
          name: 'Python',
          url: 'https://example.test/py',
          sha256: sha256.convert(py).toString(),
        ),
        DeskLangDoor(
          id: 'rust',
          name: 'Rust',
          url: 'https://example.test/rs',
          sha256: 'abcd',
        ),
      ],
      fetch: (url) async {
        fetched.add(url);
        return DeskLangBytes(url, py);
      },
      which: (_) async => null,
      start: (cmd, args) async => _FakeProc(),
    );
    await langs.enable('python');
    expect(fetched, ['https://example.test/py']);
    expect(langs.enabled, {'python'});
  });

  test('checksum fail does not spawn', () async {
    var spawned = 0;
    final langs = DeskLangRuntime(
      directory: p.join(root.path, 'lang'),
      catalog: [
        DeskLangDoor(
          id: 'python',
          name: 'Python',
          url: 'https://example.test/py',
          sha256: 'deadbeef',
        ),
      ],
      fetch: (url) async => DeskLangBytes(url, utf8Bytes('nope')),
      which: (_) async => null,
      start: (cmd, args) async {
        spawned++;
        return _FakeProc();
      },
    );
    await langs.enable('python');
    expect(spawned, 0);
    expect(langs.enabled, isEmpty);
  });

  test('custom command is what we exec, no rewrite', () async {
    final started = <List<String>>[];
    final langs = DeskLangRuntime(
      directory: p.join(root.path, 'lang'),
      start: (cmd, args) async {
        started.add([cmd, ...args]);
        return _FakeProc();
      },
    );
    langs.addCustom(
      id: 'holy_c',
      command: 'holy-c-lsp',
      args: ['--stdio'],
      extensions: ['.HC'],
    );
    await langs.enable('holy_c');
    expect(started, [
      ['holy-c-lsp', '--stdio'],
    ]);
  });

  test('disable stops the process', () async {
    final proc = _FakeProc();
    final langs = DeskLangRuntime(
      directory: p.join(root.path, 'lang'),
      catalog: [
        const DeskLangDoor(id: 'python', name: 'Python', pathCommand: 'pylsp'),
      ],
      which: (cmd) async => cmd == 'pylsp' ? '/usr/bin/pylsp' : null,
      start: (cmd, args) async => proc,
    );
    await langs.enable('python');
    expect(proc.running, isTrue);
    await langs.disable('python');
    expect(proc.killed, isTrue);
    expect(proc.running, isFalse);
    expect(langs.enabled, isEmpty);
  });

  test('Yolo does not auto-enable language doors', () async {
    File(p.join(root.path, 'project.godot')).writeAsStringSync('');
    final langs = DeskLangRuntime(directory: p.join(root.path, 'lang'));
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      mode: DeskMode.yolo,
      langs: langs,
    );
    await deskPrepareLangs(session);
    expect(session.suggestedLangs, contains('gdscript'));
    expect(langs.enabled, isEmpty);
    expect(session.mode, DeskMode.yolo);
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;

class _FakeProc implements DeskLangProc {
  var killed = false;
  @override
  var running = true;

  @override
  Future<void> kill() async {
    killed = true;
    running = false;
  }
}
