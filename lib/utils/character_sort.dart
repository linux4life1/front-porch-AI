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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// The home-screen library sort modes. String keys are the persisted values
/// (StorageService.sortMode) and the dropdown item values — kept stable.
enum CharacterSortMode {
  name('name'),
  recent('recent'),
  importDate('importDate'),
  messages('messages');

  const CharacterSortMode(this.key);
  final String key;

  static CharacterSortMode fromKey(String key) => switch (key) {
    'recent' => CharacterSortMode.recent,
    'importDate' => CharacterSortMode.importDate,
    'messages' => CharacterSortMode.messages,
    _ => CharacterSortMode.name,
  };
}

final DateTime _epochZero = DateTime.fromMillisecondsSinceEpoch(0);

/// Returns a new list of [characters] sorted by [mode].
///
/// Data-driven modes read the caches (keyed by [CharacterCard.stableGroupId],
/// exactly as the home screen builds them). Every mode falls back to a
/// case-insensitive name comparison as a stable tiebreak, so cards with equal
/// keys (e.g. two never-chatted characters under "Recent Activity", or the
/// zero-message pile under "Messages Sent") keep a deterministic order instead
/// of jittering between rebuilds.
List<CharacterCard> sortCharacters(
  List<CharacterCard> characters,
  CharacterSortMode mode, {
  Map<String, DateTime> lastActivity = const {},
  Map<String, int> messageCount = const {},
}) {
  final list = List<CharacterCard>.from(characters);

  int byName(CharacterCard a, CharacterCard b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  int tie(int primary, CharacterCard a, CharacterCard b) =>
      primary != 0 ? primary : byName(a, b);

  switch (mode) {
    case CharacterSortMode.name:
      list.sort(byName);
    case CharacterSortMode.recent:
      list.sort((a, b) {
        final at = lastActivity[a.stableGroupId] ?? _epochZero;
        final bt = lastActivity[b.stableGroupId] ?? _epochZero;
        return tie(bt.compareTo(at), a, b);
      });
    case CharacterSortMode.importDate:
      list.sort((a, b) => tie(dateAdded(b).compareTo(dateAdded(a)), a, b));
    case CharacterSortMode.messages:
      list.sort((a, b) {
        final ac = messageCount[a.stableGroupId] ?? 0;
        final bc = messageCount[b.stableGroupId] ?? 0;
        return tie(bc.compareTo(ac), a, b);
      });
  }
  return list;
}

/// The "date added" a card sorts by. Prefers the real DB [CharacterCard.createdAt];
/// for legacy cards imported before that column was hydrated it falls back to
/// the epoch embedded in the old `<name>_<epochMs>.png` filename, then to zero.
DateTime dateAdded(CharacterCard card) {
  final created = card.createdAt;
  if (created != null) return created;
  final epoch = _legacyFilenameEpoch(card);
  return epoch > 0 ? DateTime.fromMillisecondsSinceEpoch(epoch) : _epochZero;
}

int _legacyFilenameEpoch(CharacterCard card) {
  final imagePath = card.imagePath;
  if (imagePath == null) return 0;
  final basename = p.basenameWithoutExtension(imagePath);
  final lastUnderscore = basename.lastIndexOf('_');
  if (lastUnderscore == -1) return 0;
  return int.tryParse(basename.substring(lastUnderscore + 1)) ?? 0;
}
