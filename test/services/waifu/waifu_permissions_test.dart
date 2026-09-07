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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('git checkout --, git restore, and rm -rf / are hard-denied', () {
    expect(waifuDeniedCommand('git checkout -- .'), isNotNull);
    expect(waifuDeniedCommand('git checkout -- file.txt'), isNotNull);
    expect(waifuDeniedCommand('git restore dirty.txt'), isNotNull);
    expect(waifuDeniedCommand('git reset --hard'), isNotNull);
    expect(waifuDeniedCommand('rm -rf /'), isNotNull);
    expect(waifuDeniedCommand('rm -rf / '), isNotNull);
    expect(waifuDeniedCommand('ls'), isNull);
    expect(waifuDeniedCommand('git status'), isNull);
    expect(waifuDeniedCommand('rm -rf build'), isNull);
  });

  test('.env and .env.* paths are denied in every mode', () {
    expect(waifuIsEnvPath('.env'), isTrue);
    expect(waifuIsEnvPath('src/.env'), isTrue);
    expect(waifuIsEnvPath('.env.local'), isTrue);
    expect(waifuIsEnvPath('readme.env'), isFalse);
    expect(waifuIsEnvPath('hello.txt'), isFalse);
  });

  test('Plan blocks mutate; read is allowed', () {
    final p = WaifuPermissions(mode: WaifuMode.plan);
    expect(
      p.hardBlock(name: 'write', args: {'path': 'a.txt', 'contents': 'x'}),
      isNotNull,
    );
    expect(
      p.hardBlock(
        name: 'edit',
        args: {'path': 'a.txt', 'old_string': 'a', 'new_string': 'b'},
      ),
      isNotNull,
    );
    expect(p.hardBlock(name: 'read', args: {'path': 'a.txt'}), isNull);
  });

  test('Yolo does not ask until the 3rd identical tool (doom-loop)', () {
    final p = WaifuPermissions(mode: WaifuMode.yolo);
    const args = {'path': 'a.txt', 'contents': 'x'};
    expect(p.needsAsk(name: 'write', args: args), isFalse);
    p.record(name: 'write', args: args);
    expect(p.needsAsk(name: 'write', args: args), isFalse);
    p.record(name: 'write', args: args);
    expect(p.needsAsk(name: 'write', args: args), isTrue);
  });
}
