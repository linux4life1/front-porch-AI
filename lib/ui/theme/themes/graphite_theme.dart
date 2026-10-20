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

/// Graphite: plain grey with no warm tint, keeping the porch amber.
const AppThemePalettes graphiteTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF131313),
    surface: Color(0xFF1A1A1A),
    card: Color(0xFF222222),
    surfaceContainer: Color(0xFF2A2A2A),
    sunken: Color(0xFF0E0E0E),
    deepWell: Color(0xFF0B0B0B),
    insetPanel: Color(0xFF171717),
    border: Color(0xFF333333),
    navigationSelection: Color(0x14FFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    textTertiary: Color(0x80FFFFFF),
    ink: Color(0xFFEDEDED),
    muted: Color(0xFFA3A3A3),
    faint: Color(0xFF858585),
    amber: Color(0xFFF4A259),
    honey: Color(0xFFE9C46A),
    terracotta: Color(0xFFE29578),
    sage: Color(0xFF8FC4A0),
    formAccent: Color(0xFFF4A259),
    onAccent: Color(0xFF1A1200),
    studioCard: Color(0xFF222222),
    studioRaise: Color(0xFF2C2C2C),
    studioLineStrong: Color(0xFF474747),
    studioProse: Color(0xFFE5E5E5),
    studioNarration: Color(0xFFD4D4D4),
    studioAmberInk: Color(0xFF2A1A08),
    studioTeal: Color(0xFF4DB6AC),
    studioBad: Color(0xFFE57373),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF2563EB),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF2C2C2C),
      aiText: Color(0xFFFFFFFF),
      dialogue: Color(0xFFFFD54F),
      action: Color(0xFF90CAF9),
    ),
  ),
  light: AppPalette(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFEDEDED),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFE8E8E8),
    sunken: Color(0xFFE5E5E5),
    deepWell: Color(0xFFEDEDED),
    insetPanel: Color(0xFFF0F0F0),
    border: Color(0xFFD4D4D4),
    navigationSelection: Color(0xFFF6E3D0),
    textPrimary: Color(0xFF171717),
    textSecondary: Color(0xFF525252),
    textTertiary: Color(0xFF737373),
    ink: Color(0xFF262626),
    muted: Color(0xFF525252),
    faint: Color(0xFF737373),
    amber: Color(0xFFA84B06),
    honey: Color(0xFF7A5600),
    terracotta: Color(0xFF9C4B2F),
    sage: Color(0xFF2F6B4A),
    formAccent: Color(0xFFA84B06),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFFFFFF),
    studioRaise: Color(0xFFE5E5E5),
    studioLineStrong: Color(0xFFA3A3A3),
    studioProse: Color(0xFF262626),
    studioNarration: Color(0xFF525252),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF00695C),
    studioBad: Color(0xFFB71C1C),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF2563EB),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFE5E5E5),
      aiText: Color(0xFF171717),
      dialogue: Color(0xFF92400E),
      action: Color(0xFF1565C0),
    ),
  ),
);
