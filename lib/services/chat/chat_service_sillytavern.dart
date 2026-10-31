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

/// SillyTavern-shaped **transcript export** only.
///
/// Import of ST JSON / `.fpchat` is unified in [ChatService.importChatPackage]
/// (Phase 0 reseed + Phase 1 timeline). The old `importFromSillyTavern` path
/// was deleted so the bleed guard cannot pin a dead method while the UI
/// routes everything through the package importer.
extension ChatServiceSillyTavern on ChatService {
  /// Export current chat as **SillyTavern JSONL** (one JSON object per line).
  /// Dialogue only — no FPAI stamps. Use [exportToFpchat] for a full package.
  ///
  /// Phase 2: real `.jsonl` rather than a single JSON wrapper so ST and other
  /// tools that expect JSONL chats can import without conversion.
  String? exportToSillyTavern() {
    if (_session.messages.isEmpty) return null;
    final personaName = _userPersonaService.persona.name.trim();
    final userName = personaName.isEmpty ? 'User' : personaName;
    final charName =
        _session.activeCharacter?.name ?? _activeGroup?.name ?? 'Character';
    return encodeSillyTavernJsonl(
      List<ChatMessage>.from(_session.messages),
      userName: userName,
      characterName: charName,
    );
  }
}
