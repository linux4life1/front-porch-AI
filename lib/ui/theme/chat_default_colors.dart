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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// An app theme's default chat colors at one brightness.
///
/// They apply only where the user has not picked their own color in Chat
/// Appearance; per-character colors and per-chat themes still win.
@immutable
class ChatDefaultColors {
  const ChatDefaultColors({
    required this.userBubble,
    required this.userText,
    required this.aiBubble,
    required this.aiText,
    required this.dialogue,
    required this.action,
  });

  final Color userBubble;
  final Color userText;
  final Color aiBubble;
  final Color aiText;

  /// Quoted speech.
  final Color dialogue;

  /// `*Action*` text.
  final Color action;

  /// Porch, dark: the chat defaults from before themes existed.
  static const ChatDefaultColors porchDark = ChatDefaultColors(
    userBubble: Color(0xFF3B82F6),
    userText: Colors.white,
    aiBubble: Color(0xFF374151),
    aiText: Colors.white,
    dialogue: Colors.amberAccent,
    action: Color(0xFF90CAF9),
  );

  /// Porch, light.
  static const ChatDefaultColors porchLight = ChatDefaultColors(
    userBubble: AppColors.userBubbleLight,
    userText: AppColors.userTextLight,
    aiBubble: AppColors.aiBubbleLight,
    aiText: AppColors.aiTextLight,
    dialogue: AppColors.dialogueLight,
    action: AppColors.actionLight,
  );

  List<Color> get _roles => [
    userBubble,
    userText,
    aiBubble,
    aiText,
    dialogue,
    action,
  ];

  static ChatDefaultColors lerp(
    ChatDefaultColors a,
    ChatDefaultColors b,
    double t,
  ) {
    Color c(Color Function(ChatDefaultColors p) role) =>
        Color.lerp(role(a), role(b), t)!;
    return ChatDefaultColors(
      userBubble: c((p) => p.userBubble),
      userText: c((p) => p.userText),
      aiBubble: c((p) => p.aiBubble),
      aiText: c((p) => p.aiText),
      dialogue: c((p) => p.dialogue),
      action: c((p) => p.action),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatDefaultColors && listEquals(_roles, other._roles);

  @override
  int get hashCode => Object.hashAll(_roles);
}
