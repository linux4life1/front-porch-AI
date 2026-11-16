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

import 'package:flutter/painting.dart' show Color;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/group_speaker_resolution.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/accent_fit.dart' show accentHex;

/// The character card's own chat font and colours for one message, as the
/// desktop bubble resolves them (`UiSettings.getChatFontFamily` and the
/// colour getters): a chat theme wins over the card, the card over the
/// global Chat Appearance. Only the card's half travels — the web already
/// paints the chat theme and the global choices — so this is null when the
/// chat has a theme, or the card sets none of the seven.
///
/// Whose card: in a 1:1 the chat's character for every bubble; in a group
/// the speaking member's for a reply and nobody's for the user's lines
/// (`bubbleHost` and the transcript's `characterFor` on the desktop).
Map<String, String>? webCardLook(ChatService chat, ChatMessage m) {
  final preset = ChatThemePreset.byId(chat.sessionThemeOverrides.themeId);
  if (preset != null) return null;
  final CharacterCard? card;
  if (chat.isGroupMode) {
    card = m.isUser
        ? null
        : resolveGroupSpeakerForMessage(
            chat.groupCharacters,
            m,
            logOnMiss: false,
          );
  } else {
    card = chat.activeCharacter;
  }
  return cardLookWire(card?.frontPorchExtensions);
}

/// The seven per-card appearance fields as the web reads them; null when
/// none is set.
Map<String, String>? cardLookWire(FrontPorchExtensions? e) {
  if (e == null) return null;
  String? hex(Color? c) => c == null ? null : accentHex(c);
  final font = e.chatFontFamily;
  final look = <String, String>{
    if (font != null && font.isNotEmpty) 'font': font,
    'userBubble': ?hex(e.userBubbleColor),
    'userText': ?hex(e.userTextColor),
    'aiBubble': ?hex(e.aiBubbleColor),
    'aiText': ?hex(e.aiTextColor),
    'dialogue': ?hex(e.dialogueColor),
    'action': ?hex(e.actionColor),
  };
  return look.isEmpty ? null : look;
}
