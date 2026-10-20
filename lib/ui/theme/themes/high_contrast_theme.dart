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

/// High Contrast reading page: light ink on black paper, 7:1 or better.
const BookPageColors highContrastPage = BookPageColors(
  paperEdge: Color(0xFF0A0A0A),
  paper: Color(0xFF000000),
  paperInner: Color(0xFF050505),
  cover: Color(0xFF111111),
  edgeShade: Color(0x14FFFFFF),
  inkStrong: Color(0xFFFFFFFF),
  ink: Color(0xFFF2F2F2),
  inkWarm: Color(0xFFFFD60A),
  inkMuted: Color(0xFFD9D9D9),
  inkFaint: Color(0xFFB3B3B3),
);

/// High Contrast: pure black or white with solid borders, WCAG AAA (7:1+).
const AppThemePalettes highContrastTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF000000),
    card: Color(0xFF0D0D0D),
    surfaceContainer: Color(0xFF141414),
    sunken: Color(0xFF000000),
    deepWell: Color(0xFF000000),
    insetPanel: Color(0xFF0D0D0D),
    border: Color(0xFFFFFFFF),
    navigationSelection: Color(0xFF3A3A3A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFE6E6E6),
    textTertiary: Color(0xFFCCCCCC),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFFFFFFFF),
    faint: Color(0xFFD9D9D9),
    amber: Color(0xFFFFD60A),
    honey: Color(0xFFFFE066),
    terracotta: Color(0xFFFFAB91),
    sage: Color(0xFFA5D6A7),
    formAccent: Color(0xFFFFD60A),
    onAccent: Color(0xFF000000),
    studioCard: Color(0xFF0D0D0D),
    studioRaise: Color(0xFF1F1F1F),
    studioLineStrong: Color(0xFFFFFFFF),
    studioProse: Color(0xFFFFFFFF),
    studioNarration: Color(0xFFE6E6E6),
    studioAmberInk: Color(0xFF000000),
    studioTeal: Color(0xFF4DD0C4),
    studioBad: Color(0xFFFF8A80),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF1E40AF),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF000000),
      aiText: Color(0xFFFFFFFF),
      dialogue: Color(0xFFFFD60A),
      action: Color(0xFF7DD3FC),
    ),
    page: highContrastPage,
  ),
  light: AppPalette(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF2F2F2),
    sunken: Color(0xFFF2F2F2),
    deepWell: Color(0xFFFFFFFF),
    insetPanel: Color(0xFFF7F7F7),
    border: Color(0xFF000000),
    navigationSelection: Color(0xFFB3C7FF),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF1A1A1A),
    textTertiary: Color(0xFF333333),
    ink: Color(0xFF000000),
    muted: Color(0xFF000000),
    faint: Color(0xFF333333),
    amber: Color(0xFF0033CC),
    honey: Color(0xFF5C4300),
    terracotta: Color(0xFF7C2D12),
    sage: Color(0xFF1B5E20),
    formAccent: Color(0xFF0033CC),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFFFFFF),
    studioRaise: Color(0xFFE6E6E6),
    studioLineStrong: Color(0xFF000000),
    studioProse: Color(0xFF000000),
    studioNarration: Color(0xFF1A1A1A),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF004D40),
    studioBad: Color(0xFF8E1414),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF0033CC),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFFFFFFF),
      aiText: Color(0xFF000000),
      dialogue: Color(0xFF7C2D12),
      action: Color(0xFF0033CC),
    ),
    page: highContrastPage,
  ),
);
