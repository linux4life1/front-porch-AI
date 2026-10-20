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

import 'package:flutter/material.dart';

import '../app_palette.dart';
import '../chat_default_colors.dart';

/// Plum: dark aubergine with a rose accent, for romance and cozy chats.
const AppThemePalettes plumTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF1A1220),
    surface: Color(0xFF20172A),
    card: Color(0xFF281D33),
    surfaceContainer: Color(0xFF312440),
    sunken: Color(0xFF140E19),
    deepWell: Color(0xFF100B14),
    insetPanel: Color(0xFF18111E),
    border: Color(0xFF3D2D4A),
    navigationSelection: Color(0x14FFFFFF),
    textPrimary: Color(0xFFFBF5FF),
    textSecondary: Color(0xB3FBF5FF),
    textTertiary: Color(0x7AFBF5FF),
    ink: Color(0xFFF3E8F7),
    muted: Color(0xFFB5A3BF),
    faint: Color(0xFF8F7C9A),
    amber: Color(0xFFF472B6),
    honey: Color(0xFFE8C170),
    terracotta: Color(0xFFE8957F),
    sage: Color(0xFF8FC3A0),
    formAccent: Color(0xFFF472B6),
    onAccent: Color(0xFF2A0A1C),
    studioCard: Color(0xFF281D33),
    studioRaise: Color(0xFF33253F),
    studioLineStrong: Color(0xFF4F3C5E),
    studioProse: Color(0xFFECDFF2),
    studioNarration: Color(0xFFD6C2DF),
    studioAmberInk: Color(0xFF2A0A1C),
    studioTeal: Color(0xFF4DB6AC),
    studioBad: Color(0xFFEF7D7D),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF9D174D),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF33253F),
      aiText: Color(0xFFFBF5FF),
      dialogue: Color(0xFFFCD34D),
      action: Color(0xFFC4B5FD),
    ),
  ),
  light: AppPalette(
    background: Color(0xFFFAF5FB),
    surface: Color(0xFFF3EAF5),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEFE4F1),
    sunken: Color(0xFFEBDFEE),
    deepWell: Color(0xFFF3EAF5),
    insetPanel: Color(0xFFF6EFF7),
    border: Color(0xFFDCCBE0),
    navigationSelection: Color(0xFFF9DCEA),
    textPrimary: Color(0xFF22132B),
    textSecondary: Color(0xFF5C4866),
    textTertiary: Color(0xFF7D6987),
    ink: Color(0xFF2A1A33),
    muted: Color(0xFF6A5672),
    faint: Color(0xFF8E7A96),
    amber: Color(0xFFBE185D),
    honey: Color(0xFF845C00),
    terracotta: Color(0xFF9C4B2F),
    sage: Color(0xFF2F6B3F),
    formAccent: Color(0xFFBE185D),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFFFDFE),
    studioRaise: Color(0xFFEBDFEE),
    studioLineStrong: Color(0xFFC4ADCA),
    studioProse: Color(0xFF2A1A33),
    studioNarration: Color(0xFF6A5672),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF00695C),
    studioBad: Color(0xFFB3261E),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF9D174D),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFECE0EF),
      aiText: Color(0xFF22132B),
      dialogue: Color(0xFF854D0E),
      action: Color(0xFF6D28D9),
    ),
  ),
);
