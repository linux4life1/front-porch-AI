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

void main() {
  final xib = File('macos/Runner/Base.lproj/MainMenu.xib');

  test('macOS Edit menu does not advertise Find', () {
    expect(xib.existsSync(), isTrue);
    final text = xib.readAsStringSync();
    expect(text.contains('performFindPanelAction:'), isFalse);
    expect(text.contains('performTextFinderAction:'), isFalse);
    expect(text.contains('title="Find"'), isFalse);
    expect(text.contains('title="Find…"'), isFalse);
    expect(text.contains('title="Find and Replace…"'), isFalse);
    expect(text.contains('title="Find Next"'), isFalse);
    expect(text.contains('title="Find Previous"'), isFalse);
    expect(text.contains('title="Use Selection for Find"'), isFalse);
    expect(
      text.contains('title="Enter Full Screen"'),
      isTrue,
      reason: '⌃⌘F full screen is not Find — keep it',
    );
  });
}
