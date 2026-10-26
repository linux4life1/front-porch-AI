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

// The `golden` CI job and the Update Goldens workflow run
// `flutter test --tags golden test/golden`: the path keeps flutter test from
// loading every one of the ~1700 test files to find the tagged ones, which
// took 15 to 20 minutes and hit the step's limit (PR #626, 2026-10-26). The
// path is only safe while every golden-tagged test lives under test/golden.
// This guard fails the moment one lands elsewhere, with the fix in the
// message, so a pixel golden never silently stops running in CI.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every golden-tagged test file lives under test/golden/', () {
    final tagged = RegExp(r"""(@Tags\(\[[^\]]*'golden'|tags:\s*\[?'golden')""");
    final strays = <String>[];
    var underGolden = 0;
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      if (!tagged.hasMatch(entity.readAsStringSync())) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('test/golden/')) {
        underGolden++;
      } else {
        strays.add(path);
      }
    }
    expect(
      underGolden,
      greaterThan(0),
      reason:
          'no golden-tagged tests found under test/golden; the scoped '
          'golden job would run nothing',
    );
    expect(
      strays,
      isEmpty,
      reason:
          'golden-tagged tests outside test/golden never run in CI '
          '(.github/workflows/ci.yml scopes the golden job to that path). '
          'Move them under test/golden/.',
    );
  });
}
