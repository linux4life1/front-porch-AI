// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The name a new group gets until the user types one: every member, so a
/// group of two is not saved under the first member's name alone.
///
/// "Juniper & Marlow", "Juniper, Marlow & Ivy", then "Juniper & 3 others"
/// past three. The web creator (`web_ui/src/groupName.ts`) uses the same
/// rule.
String defaultGroupName(List<String> memberNames) {
  final names = [
    for (final n in memberNames)
      if (n.trim().isNotEmpty) n.trim(),
  ];
  switch (names.length) {
    case 0:
      return '';
    case 1:
      return names.first;
    case 2:
    case 3:
      return '${names.sublist(0, names.length - 1).join(', ')} & '
          '${names.last}';
    default:
      return '${names.first} & ${names.length - 1} others';
  }
}
