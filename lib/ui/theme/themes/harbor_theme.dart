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

/// Harbor: deep sea teal with a coral accent, a cool feel with a warm accent.
const AppThemePalettes harborTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF0E1A1F),
    surface: Color(0xFF122229),
    card: Color(0xFF172B33),
    surfaceContainer: Color(0xFF1D3640),
    sunken: Color(0xFF0A1418),
    deepWell: Color(0xFF081115),
    insetPanel: Color(0xFF0C171B),
    border: Color(0xFF24404B),
    navigationSelection: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF1F8FA),
    textSecondary: Color(0xB3F1F8FA),
    textTertiary: Color(0x7AF1F8FA),
    ink: Color(0xFFE6F1F3),
    muted: Color(0xFF93ACB3),
    faint: Color(0xFF6F8A91),
    amber: Color(0xFFFF8A65),
    honey: Color(0xFFE9C46A),
    terracotta: Color(0xFFE8957A),
    sage: Color(0xFF8CC49A),
    formAccent: Color(0xFFFF8A65),
    onAccent: Color(0xFF2A0F05),
    studioCard: Color(0xFF172B33),
    studioRaise: Color(0xFF1D3640),
    studioLineStrong: Color(0xFF335563),
    studioProse: Color(0xFFDCEBEE),
    studioNarration: Color(0xFFBCD3D8),
    studioAmberInk: Color(0xFF2A0F05),
    studioTeal: Color(0xFF4DB6AC),
    studioBad: Color(0xFFE57373),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF0E7490),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF1D3640),
      aiText: Color(0xFFF1F8FA),
      dialogue: Color(0xFFFDE68A),
      action: Color(0xFF7DD3FC),
    ),
  ),
  light: AppPalette(
    background: Color(0xFFF2F7F8),
    surface: Color(0xFFE6EFF1),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFE1EBEE),
    sunken: Color(0xFFDBE8EB),
    deepWell: Color(0xFFE6EFF1),
    insetPanel: Color(0xFFEDF4F5),
    border: Color(0xFFC3D5DA),
    navigationSelection: Color(0xFFF8E0D6),
    textPrimary: Color(0xFF0E1A1F),
    textSecondary: Color(0xFF3F565D),
    textTertiary: Color(0xFF637A81),
    ink: Color(0xFF14242A),
    muted: Color(0xFF4F666D),
    faint: Color(0xFF6F868C),
    amber: Color(0xFFB03A0A),
    honey: Color(0xFF845C00),
    terracotta: Color(0xFF9C4B2F),
    sage: Color(0xFF2F6B3F),
    formAccent: Color(0xFFB03A0A),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFDFEFE),
    studioRaise: Color(0xFFDBE8EB),
    studioLineStrong: Color(0xFFA9C0C6),
    studioProse: Color(0xFF14242A),
    studioNarration: Color(0xFF4F666D),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF00695C),
    studioBad: Color(0xFFB3261E),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF0E7490),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFDBE8EB),
      aiText: Color(0xFF0E1A1F),
      dialogue: Color(0xFF854D0E),
      action: Color(0xFF0369A1),
    ),
  ),
);
