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

/// What one import of `.porch` / `.porchpack` files did, across every file.
class PorchImportReport {
  /// Names of the characters added to the library.
  final List<String> imported = [];

  /// Names of characters the library already had, so they were left alone.
  final List<String> skipped = [];

  /// One plain sentence per file (or character) that could not be used.
  final List<String> refused = [];

  /// Chats restored with the imported characters.
  int chats = 0;

  /// The summary a person reads after the import.
  String get message {
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final lines = <String>[
      if (imported.isNotEmpty)
        'Imported ${plural(imported.length, 'character')}'
            '${chats > 0 ? ' with ${plural(chats, 'chat')}' : ''}.',
      if (skipped.isNotEmpty)
        'Skipped ${skipped.length} you already have: ${_names(skipped)}.',
      ...refused,
    ];
    return lines.isEmpty ? 'Those files held no characters.' : lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
    'imported': imported,
    'skipped': skipped,
    'refused': refused,
    'chats': chats,
    'message': message,
  };
}

String _names(List<String> names) {
  const shown = 8;
  if (names.length <= shown) return names.join(', ');
  return '${names.take(shown).join(', ')} and ${names.length - shown} more';
}
