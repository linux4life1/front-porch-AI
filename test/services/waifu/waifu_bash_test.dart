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
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_bash_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('bash cwd is the project root and stdout is returned', () async {
    final bash = WaifuBash(root.path);
    final result = await bash.run({'command': 'pwd'});
    expect(result.ok, isTrue);
    final realRoot = await Directory(root.path).resolveSymbolicLinks();
    expect(result.output, contains(realRoot));
  });

  test('bash cannot cd out', () async {
    final bash = WaifuBash(root.path);
    final result = await bash.run({'command': 'cd / && pwd'});
    expect(result.ok, isFalse);
    expect(result.output, contains('cd'));
    expect(result.output, isNot(contains('\n/')));
  });

  test('whole-disk bash may leave the sit-down folder', () async {
    final bash = WaifuBash(root.path, pathMode: WaifuPathMode.wholeDisk);
    final result = await bash.run({'command': 'cd .. && pwd'});
    expect(result.ok, isTrue);
    final parent = await root.parent.resolveSymbolicLinks();
    expect(result.output, contains(parent));
  });

  test('git checkout -- is denied before the process starts', () async {
    final bash = WaifuBash(root.path);
    final result = await bash.run({'command': 'git checkout -- .'});
    expect(result.ok, isFalse);
    expect(result.output.toLowerCase(), contains('denied'));
  });

  test('timeout kills a hung command', () async {
    final bash = WaifuBash(
      root.path,
      timeout: const Duration(milliseconds: 200),
    );
    final result = await bash.run({'command': 'sleep 10'});
    expect(result.ok, isFalse);
    expect(result.output.toLowerCase(), contains('timeout'));
  });
}
