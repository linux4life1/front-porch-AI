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
///
/// Setting and Realism come before the Opening so the generator can write
/// the scene where chats start, with the Group Dynamics already set. Group Dynamics is a section of Realism and
/// Prompts share a page with Lore, so every step always exists and Next
/// and Back never skip.
abstract final class GroupWizardSteps {
  static const members = 0;
  static const identity = 1;
  static const setting = 2;
  static const realism = 3;
  static const opening = 4;
  static const promptsLore = 5;
  static const review = 6;

  /// Groups this size or smaller get the Group Dynamics section.
  static const dynamicsMaxMembers = 4;

  static const labels = [
    'Members',
    'Identity',
    'Setting',
    'Realism',
    'Opening',
    'Prompts & Lore',
    'Review',
  ];

  /// The step Next goes to from [current], or null past Review.
  static int? next(int current) => current >= review ? null : current + 1;

  /// The step Back goes to from [current].
  static int previous(int current) =>
      current <= members ? members : current - 1;
}
