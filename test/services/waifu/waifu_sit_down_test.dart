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
  test(
    'honesty copy names the tools Waifu Coder is not, and the critical-repo law',
    () {
      for (final mode in WaifuPathMode.values) {
        final body = waifuHonestyBody(mode);
        expect(body, contains('Claude Code'));
        expect(body, contains('Grok Build'));
        expect(body, contains('OpenCode'));
        expect(body, contains('critical codebase'));
        expect(body, contains('hard stops'));
        expect(body, contains('real coding tools'));
        expect(body, contains('apply_patch'));
        expect(body, isNot(contains('will not be as reliable')));
        expect(body, isNot(contains('fun tool')));
        expect(body, isNot(contains('half-edit')));
        expect(
          RegExp(
            r'\b(she|her)\b',
            caseSensitive: false,
          ).hasMatch('$body ${waifuPathModeBlurb(mode)}'),
          isFalse,
        );
        expect(
          waifuHonestyCheckbox(mode),
          contains('code I cannot afford to lose'),
        );
      }
    },
  );

  test(
    'Sit down is dead until honesty, tools, folder, and coworker are all set',
    () {
      expect(
        waifuCanSitDown(
          honestyAccepted: true,
          toolsSupported: true,
          hasFolder: true,
          hasCoworker: true,
        ),
        isTrue,
      );
      expect(
        waifuCanSitDown(
          honestyAccepted: false,
          toolsSupported: true,
          hasFolder: true,
          hasCoworker: true,
        ),
        isFalse,
      );
      expect(
        waifuCanSitDown(
          honestyAccepted: true,
          toolsSupported: false,
          hasFolder: true,
          hasCoworker: true,
        ),
        isFalse,
      );
      expect(
        waifuCanSitDown(
          honestyAccepted: true,
          toolsSupported: true,
          hasFolder: false,
          hasCoworker: true,
        ),
        isFalse,
      );
      expect(
        waifuCanSitDown(
          honestyAccepted: true,
          toolsSupported: true,
          hasFolder: true,
          hasCoworker: false,
        ),
        isFalse,
      );
    },
  );

  test('WaifuMode default for a new session is build', () {
    expect(WaifuMode.build.name, 'build');
    expect(
      WaifuMode.values,
      containsAll([WaifuMode.plan, WaifuMode.build, WaifuMode.yolo]),
    );
  });
}
