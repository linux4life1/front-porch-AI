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

/// The Create Group wizard's steps, in order. Every step index in the
/// wizard (dots, Next, Back, the page's switch) reads these, so inserting
/// a step can no longer leave one of them pointing at the wrong page.
abstract final class GroupWizardSteps {
  static const members = 0;
  static const identity = 1;
  static const setting = 2;
  static const prompts = 3;
  static const lore = 4;
  static const realism = 5;

  /// Only offered to groups of [dynamicsMaxMembers] or fewer.
  static const dynamics = 6;
  static const opening = 7;
  static const review = 8;

  static const dynamicsMaxMembers = 4;

  static const labels = [
    'Members',
    'Identity',
    'Setting',
    'Prompts',
    'Lore',
    'Realism',
    'Group Dynamics',
    'Opening',
    'Review',
  ];

  /// The step Next goes to from [current], or null past Review.
  static int? next(int current, {required int memberCount}) {
    var step = current + 1;
    if (step == dynamics && memberCount > dynamicsMaxMembers) step++;
    return step > review ? null : step;
  }

  /// The step Back goes to from [current]; it skips Dynamics the way
  /// Next does.
  static int previous(int current, {required int memberCount}) {
    var step = current - 1;
    if (step == dynamics && memberCount > dynamicsMaxMembers) step--;
    return step < members ? members : step;
  }
}
