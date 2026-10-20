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

/// Evergreen: deep pine grounds with an old-gold accent.
const AppThemePalettes evergreenTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF111814),
    surface: Color(0xFF16201A),
    card: Color(0xFF1C2820),
    surfaceContainer: Color(0xFF24332A),
    sunken: Color(0xFF0C120F),
    deepWell: Color(0xFF090E0B),
    insetPanel: Color(0xFF131C17),
    border: Color(0xFF2C3B31),
    navigationSelection: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF2F5EF),
    textSecondary: Color(0xB3F2F5EF),
    textTertiary: Color(0x85F2F5EF),
    ink: Color(0xFFE8EDE4),
    muted: Color(0xFFA3B0A2),
    faint: Color(0xFF7F8C7E),
    amber: Color(0xFFD4B45F),
    honey: Color(0xFFEDD58A),
    terracotta: Color(0xFFE29578),
    sage: Color(0xFF9CCB9A),
    formAccent: Color(0xFFD4B45F),
    onAccent: Color(0xFF1F1A05),
    studioCard: Color(0xFF1C2820),
    studioRaise: Color(0xFF24332A),
    studioLineStrong: Color(0xFF3D5044),
    studioProse: Color(0xFFE8EDE4),
    studioNarration: Color(0xFFD2DCCB),
    studioAmberInk: Color(0xFF1F1A05),
    studioTeal: Color(0xFF4DB6AC),
    studioBad: Color(0xFFE57373),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF3F6212),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF24332A),
      aiText: Color(0xFFF2F5EF),
      dialogue: Color(0xFFFDE68A),
      action: Color(0xFFA7F3D0),
    ),
  ),
  light: AppPalette(
    background: Color(0xFFF3F6F1),
    surface: Color(0xFFE9EFE6),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFE3EADF),
    sunken: Color(0xFFDDE6D9),
    deepWell: Color(0xFFE9EFE6),
    insetPanel: Color(0xFFEEF3EB),
    border: Color(0xFFC9D4C4),
    navigationSelection: Color(0xFFEDE6CC),
    textPrimary: Color(0xFF14201A),
    textSecondary: Color(0xFF3F4F44),
    textTertiary: Color(0xFF5E6E62),
    ink: Color(0xFF1A2A20),
    muted: Color(0xFF3F4F44),
    faint: Color(0xFF5E6E62),
    amber: Color(0xFF6B5300),
    honey: Color(0xFF7A5600),
    terracotta: Color(0xFF9C4B2F),
    sage: Color(0xFF2F6B3F),
    formAccent: Color(0xFF6B5300),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFFFFFF),
    studioRaise: Color(0xFFDDE6D9),
    studioLineStrong: Color(0xFF9DAE96),
    studioProse: Color(0xFF1A2A20),
    studioNarration: Color(0xFF3F4F44),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF00695C),
    studioBad: Color(0xFFB71C1C),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF3F6212),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFDDE6D9),
      aiText: Color(0xFF14201A),
      dialogue: Color(0xFF854D0E),
      action: Color(0xFF166534),
    ),
  ),
);
