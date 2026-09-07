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
  test('folder jail blocks cd-out while whole-disk mode allows it', () async {
    final root = await Directory.systemTemp.createTemp('waifu_bash_scope_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await Directory('${root.path}/src').create();
    for (final command in [
      r'cd $HOME && pwd',
      r'cd ${HOME} && pwd',
      'pushd / && pwd',
      'CD / && pwd',
      'builtin cd /',
      'cd .. && pwd',
    ]) {
      expect(
        await waifuBashScopeBlock(command, root.path, WaifuPathMode.folderJail),
        isNotNull,
        reason: command,
      );
      expect(
        await waifuBashScopeBlock(command, root.path, WaifuPathMode.wholeDisk),
        isNull,
        reason: command,
      );
    }
    expect(
      await waifuBashScopeBlock(
        'cd src && ls',
        root.path,
        WaifuPathMode.folderJail,
      ),
      isNull,
    );
  });
}
