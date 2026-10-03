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

@Tags(['golden'])
@TestOn('linux')
library;

// First widget pixel goldens — the needs bar/grid. These are prop-only
// StatelessWidgets (no provider tree), so they prove the widget-golden pipeline
// end to end and lock the character "needs" UI in both light and dark themes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/widgets/needs_bar.dart';

import '../support/golden_app.dart';

void main() {
  testWidgets('NeedsBar — healthy value', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const SizedBox(
        width: 360,
        child: NeedsBar(need: 'hunger', value: 72, reason: 'ate recently'),
      ),
      group: 'needs_bar',
      name: 'bar_healthy',
    );
  });

  testWidgets('NeedsBar — critical value', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const SizedBox(
        width: 360,
        child: NeedsBar(need: 'bladder', value: 4, reason: 'desperate'),
      ),
      group: 'needs_bar',
      name: 'bar_critical',
    );
  });

  testWidgets('NeedsBar — mini variant', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const SizedBox(
        width: 160,
        child: NeedsBar(need: 'energy', value: 30, mini: true),
      ),
      group: 'needs_bar',
      name: 'bar_mini',
      surface: const Size(220, 120),
    );
  });

  testWidgets('NeedsGrid — full 8-need set', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const SizedBox(
        width: 380,
        child: NeedsGrid(
          needs: {
            'hunger': 75,
            'bladder': 10,
            'bowels': 45,
            'energy': 55,
            'social': 40,
            'fun': 88,
            'hygiene': 62,
            'comfort': 30,
          },
        ),
      ),
      group: 'needs_bar',
      name: 'grid_full',
      surface: const Size(440, 460),
    );
  });
}
