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

// Issue #767: the growth route's whitelist and the facade's switch must name
// the same actions. They agreed when hand-checked after PR #762; nothing
// pinned them, so an action added to one side would 400 at the route (the
// web-Undo bug this PR drive-by fixed) with no test noticing. This is that
// pin: the switch's `case` labels ARE the handled set.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/web/routes/chat_tools_growth_routes.dart';

void main() {
  test('knownGrowthActions is exactly the facade switch\'s handled set', () {
    final source = File(
      'lib/services/web/facade/chat_tools/chat_tools_memory.dart',
    ).readAsStringSync();
    // The growth mutation switch is the only one in that file whose cases
    // are bare strings (the ring action names). Every such label counts: an
    // earlier `.where(knownGrowthActions.contains)` here threw away exactly
    // the switch-only action this test exists to catch. A second bare-string
    // switch added to that file would fail this loudly — the safe direction.
    final handled = RegExp(
      r"case '([A-Za-z]+)':",
    ).allMatches(source).map((m) => m.group(1)!).toSet();

    expect(
      handled,
      equals(knownGrowthActions),
      reason:
          'route whitelist and facade switch drifted: only in whitelist '
          '${knownGrowthActions.difference(handled)}, only in switch '
          '${handled.difference(knownGrowthActions)}',
    );
  });
}
