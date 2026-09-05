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
  test('recap is extractive: keeps named files from folded turns', () {
    final msgs = <DeskMessage>[
      const DeskMessage(isUser: true, text: 'please write hello.txt'),
      for (var i = 0; i < 24; i++)
        DeskMessage(isUser: i.isEven, text: 'pad $i ' * 40),
    ];
    final compact = deskCompactTranscript(msgs, budgetChars: 80, keep: 4);
    expect(compact.first.text.toLowerCase(), contains('recap'));
    expect(compact.first.text, contains('hello.txt'));
    expect(compact.first.text, isNot(contains('invented.txt')));
    expect(compact.first.text, isNot(contains('secret.py')));
  });
}
