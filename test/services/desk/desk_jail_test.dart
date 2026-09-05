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
  late File outside;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('desk_jail_');
    root = await Directory(p.join(sandbox.path, 'proj')).create();
    outside = File(p.join(sandbox.path, 'secret.txt'));
    await outside.writeAsString('SECRET_MUST_NOT_LEAK');
    await File(p.join(root.path, 'hello.txt')).writeAsString('ok');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('relative path inside the root resolves', () {
    final hit = DeskJail.resolve(root.path, 'hello.txt');
    expect(hit.ok, isTrue);
    expect(hit.path, p.join(root.path, 'hello.txt'));
    expect(hit.error, isNull);
  });

  test('.. segments are a tool error, not an escape', () {
    final hit = DeskJail.resolve(root.path, '../secret.txt');
    expect(hit.ok, isFalse);
    expect(hit.path, isNull);
    expect(hit.error, contains('jail'));
  });

  test('absolute path outside the root is a tool error', () {
    final hit = DeskJail.resolve(root.path, outside.path);
    expect(hit.ok, isFalse);
    expect(hit.error, contains('jail'));
  });

  test('/etc is a tool error', () {
    final hit = DeskJail.resolve(root.path, '/etc/passwd');
    expect(hit.ok, isFalse);
    expect(hit.error, contains('jail'));
  });

  test('nested .. that would leave the root is denied before normalize', () {
    final hit = DeskJail.resolve(root.path, 'sub/../../secret.txt');
    expect(hit.ok, isFalse);
    expect(hit.error, contains('jail'));
  });

  test('symlink that escapes the root is denied', () async {
    final link = Link(p.join(root.path, 'escape.txt'));
    await link.create(outside.path);
    final live = await DeskJail.resolveLive(root.path, 'escape.txt');
    expect(live.ok, isFalse);
    expect(live.error, contains('jail'));
  });

  test('realpath of a file inside a /var temp dir is allowed', () async {
    final live = await DeskJail.resolveLive(root.path, 'hello.txt');
    expect(live.ok, isTrue);
    expect(live.path, isNotNull);
  });
}
