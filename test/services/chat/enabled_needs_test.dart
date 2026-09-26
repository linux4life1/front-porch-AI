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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

CharacterCard _card(List<String> off) => CharacterCard(
  name: 'Aria',
  frontPorchExtensions: FrontPorchExtensions(needsOff: off),
);

void main() {
  test('null card gives all seven keys in canonical order', () {
    expect(enabledNeedKeys(null), NeedsSimulation.needKeys);
    expect(needsOffOf(null), isEmpty);
  });

  test('needsOff hygiene+fun yields the five remaining keys in order', () {
    expect(enabledNeedKeys(_card(['hygiene', 'fun'])), [
      'hunger',
      'bladder',
      'energy',
      'social',
      'comfort',
    ]);
  });

  test('all seven off yields an empty list', () {
    expect(enabledNeedKeys(_card(NeedsSimulation.needKeys)), isEmpty);
  });

  test('visibleNeedsFor with empty off leaves the vector as-is', () {
    const vector = {'hunger': 80, 'bladder': 70};
    expect(visibleNeedsFor(vector, _card(const [])), same(vector));
    expect(visibleNeedsFor(vector, null), same(vector));
  });
}
