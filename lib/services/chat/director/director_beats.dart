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

/// A one-tap director's note: [label] on the chip, [note] as it is sent.
class DirectorBeat {
  const DirectorBeat(this.label, this.note);

  final String label;
  final String note;

  Map<String, String> toJson() => {'label': label, 'note': note};
}

/// The quick beats the desktop panel shows. The web reads the same list from
/// the chat snapshot, so the two never drift.
const List<DirectorBeat> kDirectorQuickBeats = [
  DirectorBeat(
    'Raise the stakes',
    'Raise the stakes: something happens that makes this moment matter more '
        'to everyone here.',
  ),
  DirectorBeat(
    'Time skip',
    'Time skip: jump ahead a few hours and pick the scene up from there.',
  ),
  DirectorBeat(
    'Change location',
    'Change location: the scene moves somewhere new.',
  ),
  DirectorBeat(
    'Someone arrives',
    'Someone new arrives and changes the mood of the scene.',
  ),
  DirectorBeat(
    'Wrap the scene',
    'Wrap the scene: bring this moment to a natural close.',
  ),
];
