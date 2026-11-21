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

// A character's Title is the library label that is not its name: a full name
// ("Alice Smith" for Alice) or the card's premise ("Misty Meadows, Misguided
// Meteorologist" for Misty). Backyard calls it the title (`displayName` in a
// .byaf) and the Stoop shows it as the listing name. Chats still address the
// character by its name; only the library shows the title.

/// The editor's Title placeholder and the line under it; the web editor shows
/// the same two strings.
const kCardTitleHint = 'Optional: a full name, or what the card is about';
const kCardTitleHelp =
    'Shown under the name in your library. Chats still use the name.';

/// [candidate] trimmed, when it says something the [name] does not: null when
/// it is blank or only the name again (any case), so an import never stores a
/// title that repeats the name.
String? distinctTitle(String? candidate, String name) {
  final t = candidate?.trim() ?? '';
  if (t.isEmpty || t.toLowerCase() == name.trim().toLowerCase()) return null;
  return t;
}

/// Whether a library entry matches the search [lowerTerm] (already lowercase):
/// its name, its title or any tag contains it. The desktop grid and the web
/// list both search through this, so a title finds a card on either.
bool libraryEntryMatches(
  String lowerTerm, {
  required String name,
  required String title,
  required Iterable<String> tags,
}) =>
    name.toLowerCase().contains(lowerTerm) ||
    title.toLowerCase().contains(lowerTerm) ||
    tags.any((t) => t.toLowerCase().contains(lowerTerm));
