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

// The Chance Time overlay must paint through the extracted painters. A second
// private copy of the wheel or the confetti is how the two drifted last time.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the overlay paints through the extracted Chance Time painters', () {
    final view = File(
      'lib/ui/widgets/chance_time_overlay.view.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/ui/widgets/chance_time_overlay.dart',
    ).readAsStringSync();
    expect(view.contains('WheelPainter('), isTrue);
    expect(view.contains('PointerPainter('), isTrue);
    expect(view.contains('ConfettiPainter('), isTrue);
    expect(shell.contains('class _WheelPainter'), isFalse);
    expect(shell.contains('class _ConfettiPainter'), isFalse);
    expect(
      File('lib/ui/widgets/chance_time/wheel_painter.dart').existsSync(),
      isTrue,
    );
    expect(
      File('lib/ui/widgets/chance_time/confetti_painter.dart').existsSync(),
      isTrue,
    );
  });
}
