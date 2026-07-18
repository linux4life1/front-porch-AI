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

/// SillyTavern chat JSON import/export. Extracted verbatim from
/// `chat_service.dart` (zero behaviour change) to shrink the god file. As
/// `part of` the same library it reaches `_messages`, `_activeCharacter`,
/// `_currentSessionId`, and `_saveChat` exactly as the in-class methods did.
extension ChatServiceSillyTavern on ChatService {
  // Import chat from SillyTavern JSON format
  Future<void> importFromSillyTavern(String jsonData) async {
    if (_activeCharacter == null) throw Exception('No active character');

    try {
      final Map<String, dynamic> data = jsonDecode(jsonData);
      final List<dynamic> messages = data['messages'] ?? [];

      debugPrint(
        '[ChatService] 🟡 importFromSillyTavern: clearing messages for import',
      );
      _messages.clear();

      for (final msg in messages) {
        final String name = msg['name'] ?? '';
        final bool isUser = msg['is_user'] ?? false;
        final String text = msg['mes'] ?? '';

        _messages.add(ChatMessage(text: text, sender: name, isUser: isUser));
      }

      // Create new session for imported chat
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _saveChat();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to parse SillyTavern JSON: $e');
    }
  }

  // Export current chat to SillyTavern JSON format
  String? exportToSillyTavern() {
    if (_messages.isEmpty) return null;

    final List<Map<String, dynamic>> messages = _messages.map((msg) {
      return {
        'name': msg.sender,
        'is_user': msg.isUser,
        'mes': msg.text,
        'send_date': DateTime.now().millisecondsSinceEpoch,
      };
    }).toList();

    final Map<String, dynamic> export = {
      'chat_metadata': {'note_prompt': '', 'note_interval': 0},
      'messages': messages,
    };

    return jsonEncode(export);
  }
}
