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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory root;
  late DeskFs fs;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('desk_fs_');
    root = await Directory(p.join(sandbox.path, 'proj')).create();
    await File(p.join(root.path, 'hello.txt')).writeAsString('hello world');
    await Directory(p.join(root.path, 'src')).create();
    await File(
      p.join(root.path, 'src', 'app.dart'),
    ).writeAsString('void main() {}');
    fs = DeskFs(root.path);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('read of a jailed file returns bytes; ../ does not', () async {
    final ok = await fs.dispatch('read', {'path': 'hello.txt'});
    expect(ok.ok, isTrue);
    expect(ok.output, contains('hello world'));

    final leak = await fs.dispatch('read', {'path': '../secret.txt'});
    expect(leak.ok, isFalse);
    expect(leak.output, contains('jail'));
    expect(leak.output, isNot(contains('SECRET')));
  });

  test('read_file alias is jailed the same way as read', () async {
    final leak = await fs.dispatch('read_file', {'path': '/etc/passwd'});
    expect(leak.ok, isFalse);
    expect(leak.output, contains('jail'));
  });

  test('write records before-bytes and overwrites inside the jail', () async {
    final first = await fs.dispatch('write', {
      'path': 'hello.txt',
      'contents': 'patched',
    });
    expect(first.ok, isTrue);
    expect(first.write, isNotNull);
    expect(first.write!.relativePath, 'hello.txt');
    expect(first.write!.before, 'hello world');
    expect(first.write!.after, 'patched');
    expect(
      await File(p.join(root.path, 'hello.txt')).readAsString(),
      'patched',
    );
  });

  test('edit replaces a unique string; missing string is an error', () async {
    final ok = await fs.dispatch('edit', {
      'path': 'hello.txt',
      'old_string': 'world',
      'new_string': 'desk',
    });
    expect(ok.ok, isTrue);
    expect(
      await File(p.join(root.path, 'hello.txt')).readAsString(),
      'hello desk',
    );

    final miss = await fs.dispatch('edit', {
      'path': 'hello.txt',
      'old_string': 'nope',
      'new_string': 'x',
    });
    expect(miss.ok, isFalse);
  });

  test('glob lists jailed matches; grep finds a line', () async {
    final glob = await fs.dispatch('glob', {'pattern': '**/*.dart'});
    expect(glob.ok, isTrue);
    expect(glob.output, contains('src/app.dart'));

    final grep = await fs.dispatch('grep', {'pattern': 'void main'});
    expect(grep.ok, isTrue);
    expect(grep.output, contains('src/app.dart'));
    expect(grep.output, contains('void main'));
  });
}
