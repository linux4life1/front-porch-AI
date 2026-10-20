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
import '../book_page_colors.dart';
import '../chat_default_colors.dart';

/// Midnight's story page: dark paper and light warm ink.
const BookPageColors midnightPage = BookPageColors(
  paperEdge: Color(0xFF15130F),
  paper: Color(0xFF1C1915),
  paperInner: Color(0xFF181511),
  cover: Color(0xFF0E0C0A),
  edgeShade: Color(0x29000000),
  inkStrong: Color(0xFFF2E6D0),
  ink: Color(0xFFE6DAC4),
  inkWarm: Color(0xFFE0B880),
  inkMuted: Color(0xFFBFB2A0),
  inkFaint: Color(0xFF8C8070),
);

/// Midnight: true black for OLED screens and night use, with a teal accent.
const AppThemePalettes midnightTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF0A0A0A),
    card: Color(0xFF121212),
    surfaceContainer: Color(0xFF1C1C1C),
    sunken: Color(0xFF050505),
    deepWell: Color(0xFF000000),
    insetPanel: Color(0xFF0D0D0D),
    border: Color(0xFF262626),
    navigationSelection: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xB3F5F5F5),
    textTertiary: Color(0x80F5F5F5),
    ink: Color(0xFFEDEDED),
    muted: Color(0xFFA3A3A3),
    faint: Color(0xFF7A7A7A),
    amber: Color(0xFF2DD4BF),
    honey: Color(0xFFE5C07B),
    terracotta: Color(0xFFE0957A),
    sage: Color(0xFF8CC9A0),
    formAccent: Color(0xFF2DD4BF),
    onAccent: Color(0xFF042F2E),
    studioCard: Color(0xFF121212),
    studioRaise: Color(0xFF1F1F1F),
    studioLineStrong: Color(0xFF3A3A3A),
    studioProse: Color(0xFFE5E5E5),
    studioNarration: Color(0xFFD4D4D4),
    studioAmberInk: Color(0xFF042F2E),
    studioTeal: Color(0xFF5EEAD4),
    studioBad: Color(0xFFF28B82),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF0F766E),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF1A1A1A),
      aiText: Color(0xFFF5F5F5),
      dialogue: Color(0xFFFDE68A),
      action: Color(0xFF7DD3FC),
    ),
    page: midnightPage,
  ),
  light: AppPalette(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F6F6),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEAF0EF),
    sunken: Color(0xFFE6EDED),
    deepWell: Color(0xFFF3F6F6),
    insetPanel: Color(0xFFF6F9F9),
    border: Color(0xFFD6DDDC),
    navigationSelection: Color(0xFFD5F0EC),
    textPrimary: Color(0xFF0B1414),
    textSecondary: Color(0xFF3F5150),
    textTertiary: Color(0xFF5F7170),
    ink: Color(0xFF142020),
    muted: Color(0xFF3F5150),
    faint: Color(0xFF5F7170),
    amber: Color(0xFF0F766E),
    honey: Color(0xFF7A5600),
    terracotta: Color(0xFF9C4B2F),
    sage: Color(0xFF2F6B4A),
    formAccent: Color(0xFF0F766E),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFFFFFF),
    studioRaise: Color(0xFFE6EDED),
    studioLineStrong: Color(0xFF9FB0AE),
    studioProse: Color(0xFF142020),
    studioNarration: Color(0xFF3F5150),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF00695C),
    studioBad: Color(0xFFB71C1C),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF0F766E),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFE6EDED),
      aiText: Color(0xFF0B1414),
      dialogue: Color(0xFF854D0E),
      action: Color(0xFF0369A1),
    ),
    page: midnightPage,
  ),
);
