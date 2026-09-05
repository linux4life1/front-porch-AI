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
import 'package:front_porch_ai/services/desk/desk.dart';

void main() {
  test('git checkout --, git restore, and rm -rf / are hard-denied', () {
    expect(deskDeniedCommand('git checkout -- .'), isNotNull);
    expect(deskDeniedCommand('git checkout -- file.txt'), isNotNull);
    expect(deskDeniedCommand('git restore dirty.txt'), isNotNull);
    expect(deskDeniedCommand('git reset --hard'), isNotNull);
    expect(deskDeniedCommand('rm -rf /'), isNotNull);
    expect(deskDeniedCommand('rm -rf / '), isNotNull);
    expect(deskDeniedCommand('ls'), isNull);
    expect(deskDeniedCommand('git status'), isNull);
    expect(deskDeniedCommand('rm -rf build'), isNull);
  });

  test('.env and .env.* paths are denied in every mode', () {
    expect(deskIsEnvPath('.env'), isTrue);
    expect(deskIsEnvPath('src/.env'), isTrue);
    expect(deskIsEnvPath('.env.local'), isTrue);
    expect(deskIsEnvPath('readme.env'), isFalse);
    expect(deskIsEnvPath('hello.txt'), isFalse);
  });

  test('Plan blocks mutate; read is allowed', () {
    final p = DeskPermissions(mode: DeskMode.plan);
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
    final p = DeskPermissions(mode: DeskMode.yolo);
    const args = {'path': 'a.txt', 'contents': 'x'};
    expect(p.needsAsk(name: 'write', args: args), isFalse);
    p.record(name: 'write', args: args);
    expect(p.needsAsk(name: 'write', args: args), isFalse);
    p.record(name: 'write', args: args);
    expect(p.needsAsk(name: 'write', args: args), isTrue);
  });
}
