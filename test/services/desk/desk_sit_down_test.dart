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
  test(
    'honesty copy names the tools Desk is not, and the critical-repo law',
    () {
      expect(kDeskHonestyBody, contains('Claude Code'));
      expect(kDeskHonestyBody, contains('Grok Build'));
      expect(kDeskHonestyBody, contains('OpenCode'));
      expect(kDeskHonestyBody, contains('critical codebase'));
      expect(
        kDeskHonestyCheckbox,
        'I understand. I will not use Waifu Coder on code I cannot afford '
        'to lose.',
      );
    },
  );

  test(
    'Sit down is dead until honesty, tools, folder, and coworker are all set',
    () {
      expect(
        deskCanSitDown(
          honestyAccepted: true,
          toolsSupported: true,
          hasFolder: true,
          hasCoworker: true,
        ),
        isTrue,
      );
      expect(
        deskCanSitDown(
          honestyAccepted: false,
          toolsSupported: true,
          hasFolder: true,
          hasCoworker: true,
        ),
        isFalse,
      );
      expect(
        deskCanSitDown(
          honestyAccepted: true,
          toolsSupported: false,
          hasFolder: true,
          hasCoworker: true,
        ),
        isFalse,
      );
      expect(
        deskCanSitDown(
          honestyAccepted: true,
          toolsSupported: true,
          hasFolder: false,
          hasCoworker: true,
        ),
        isFalse,
      );
      expect(
        deskCanSitDown(
          honestyAccepted: true,
          toolsSupported: true,
          hasFolder: true,
          hasCoworker: false,
        ),
        isFalse,
      );
    },
  );

  test('DeskMode default for a new session is build', () {
    expect(DeskMode.build.name, 'build');
    expect(
      DeskMode.values,
      containsAll([DeskMode.plan, DeskMode.build, DeskMode.yolo]),
    );
  });
}
