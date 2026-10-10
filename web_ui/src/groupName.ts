// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The name a new group gets until the user types one: every member, so a
// group of two is not saved under the first member's name alone. Same rule as
// the desktop's defaultGroupName (lib/utils/default_group_name.dart).

export function defaultGroupName(memberNames: string[]): string {
  const names = memberNames.map((n) => n.trim()).filter(Boolean);
  if (names.length <= 1) return names[0] ?? '';
  if (names.length <= 3) return `${names.slice(0, -1).join(', ')} & ${names[names.length - 1]}`;
  return `${names[0]} & ${names.length - 1} others`;
}
