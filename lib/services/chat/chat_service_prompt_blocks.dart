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

part of '../chat_service.dart';

/// Static prompt-block builders: the Author's Note (setter + strength-modulated
/// wrapper) and the user-persona block. Extracted verbatim from the god file
/// (zero behaviour change); both are pure string builders with no Realism/Needs
/// state, identical in 1:1 and group modes.
extension ChatServicePromptBlocks on ChatService {
  void setAuthorNote(String note, {int? strength}) {
    _authorNote = note;
    if (strength != null) _authorNoteStrength = strength;
    _saveChat();
    notifyListeners();
  }

  /// Build the Author's Note block with strength-modulated wrapper text.
  /// Strength 1–3: subtle suggestion, 4–7: standard, 8–10: urgent directive.
  String _buildAuthorNoteBlock() {
    if (_authorNote.isEmpty) return '';
    if (_authorNoteStrength <= 3) {
      return '[Author\'s Note (gentle suggestion): $_authorNote]\n';
    } else if (_authorNoteStrength <= 7) {
      return '[Author\'s Note: $_authorNote]\n';
    } else {
      return '[Author\'s Note (IMPORTANT — apply immediately): $_authorNote]\n';
    }
  }

  /// Build the user persona block for the generation prompt.
  /// The user's self-description is ground truth. (What the character has
  /// *learned* about the user now lives in her per-chat Journal cards —
  /// injected separately via journal_injection — not here.)
  Future<String> _buildUserPersonaBlock(String userName) async {
    final persona = _userPersonaService.persona;
    final personaText = persona.persona.trim();
    final safeUserName = userName.replaceAll(RegExp(r'[\n\r"]'), ' ').trim();

    final buf = StringBuffer();
    // ALWAYS establish the user's identity by NAME — even with no persona text.
    // Otherwise the model only sees "$userName:" history labels and invents a
    // generic descriptor ("the boy"/"the girl") for the human. (Previously this
    // returned '' entirely when the persona had no description.)
    if (personaText.isNotEmpty) {
      final safePersonaText = personaText
          .replaceAll(RegExp(r'[\n\r"]'), ' ')
          .trim();
      buf.writeln("$safeUserName's Persona: $safePersonaText");
    } else {
      buf.writeln('$safeUserName is the human you are talking with.');
    }
    // The model HAS the name above — nudge it to actually use it instead of
    // reaching for a generic epithet for the human.
    buf.writeln(
      'Always refer to $safeUserName by name; never substitute a generic '
      'descriptor like "the boy", "the girl", or "the user".',
    );
    buf.writeln();
    return buf.toString();
  }
}
