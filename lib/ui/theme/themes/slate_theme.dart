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

/// Slate: cool navy from before the brown, with a soft blue accent.
const AppThemePalettes slateTheme = AppThemePalettes(
  dark: AppPalette(
    background: Color(0xFF0F172A),
    surface: Color(0xFF1F2937),
    card: Color(0xFF1E293B),
    surfaceContainer: Color(0xFF273449),
    sunken: Color(0xFF0B1220),
    deepWell: Color(0xFF080E1A),
    insetPanel: Color(0xFF111A2E),
    border: Color(0xFF334155),
    navigationSelection: Color(0x14FFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    textTertiary: Color(0x80FFFFFF),
    ink: Color(0xFFE2E8F0),
    muted: Color(0xFF94A3B8),
    faint: Color(0xFF7C8BA1),
    amber: Color(0xFF60A5FA),
    honey: Color(0xFFE5C07B),
    terracotta: Color(0xFFE8A087),
    sage: Color(0xFF8CC9A6),
    formAccent: Color(0xFF60A5FA),
    onAccent: Color(0xFF0B1530),
    studioCard: Color(0xFF1E293B),
    studioRaise: Color(0xFF273449),
    studioLineStrong: Color(0xFF475569),
    studioProse: Color(0xFFE2E8F0),
    studioNarration: Color(0xFFCBD5E1),
    studioAmberInk: Color(0xFF0B1530),
    studioTeal: Color(0xFF5EC4B6),
    studioBad: Color(0xFFF28B82),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF2563EB),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFF374151),
      aiText: Color(0xFFFFFFFF),
      dialogue: Color(0xFFFFD54F),
      action: Color(0xFF93C5FD),
    ),
  ),
  light: AppPalette(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFF1F5F9),
    card: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFE8EEF5),
    sunken: Color(0xFFE2E8F0),
    deepWell: Color(0xFFF1F5F9),
    insetPanel: Color(0xFFF4F7FA),
    border: Color(0xFFCBD5E1),
    navigationSelection: Color(0xFFDBE7FB),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF64748B),
    ink: Color(0xFF1E293B),
    muted: Color(0xFF475569),
    faint: Color(0xFF64748B),
    amber: Color(0xFF1D4ED8),
    honey: Color(0xFF7A5600),
    terracotta: Color(0xFF9C4B2F),
    sage: Color(0xFF2F6B4A),
    formAccent: Color(0xFF1D4ED8),
    onAccent: Color(0xFFFFFFFF),
    studioCard: Color(0xFFFFFFFF),
    studioRaise: Color(0xFFE2E8F0),
    studioLineStrong: Color(0xFF94A3B8),
    studioProse: Color(0xFF1E293B),
    studioNarration: Color(0xFF475569),
    studioAmberInk: Color(0xFFFFFFFF),
    studioTeal: Color(0xFF00695C),
    studioBad: Color(0xFFB71C1C),
    chat: ChatDefaultColors(
      userBubble: Color(0xFF2563EB),
      userText: Color(0xFFFFFFFF),
      aiBubble: Color(0xFFE2E8F0),
      aiText: Color(0xFF0F172A),
      dialogue: Color(0xFF92400E),
      action: Color(0xFF1D4ED8),
    ),
  ),
);
