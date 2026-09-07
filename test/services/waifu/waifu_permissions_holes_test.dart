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
  test('git checkout HEAD -- discards work and is denied', () {
    expect(waifuDeniedCommand('git checkout HEAD -- .'), isNotNull);
    expect(waifuDeniedCommand('git checkout main -- dirty.txt'), isNotNull);
    expect(waifuDeniedCommand('git checkout -b topic'), isNull);
  });

  test('rm --recursive --force / is denied the same as rm -rf /', () {
    expect(waifuDeniedCommand('rm --recursive --force /'), isNotNull);
    expect(waifuDeniedCommand('rm -rf /.'), isNotNull);
    expect(waifuDeniedCommand('rm --recursive --force build'), isNull);
  });

  test('.ENV is denied case-insensitively', () {
    expect(waifuIsEnvPath('.ENV'), isTrue);
    expect(waifuIsEnvPath('src/.Env.local'), isTrue);
    final p = WaifuPermissions(mode: WaifuMode.yolo);
    expect(p.hardBlock(name: 'read', args: {'path': '.ENV'}), isNotNull);
  });
}
