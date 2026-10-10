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

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app sidebar's width at ordinary text sizes.
const double kSidebarWidth = 250;

/// Room a nav row takes besides its label: the row's outer and inner
/// padding (12 each side, twice), the 22 px icon, the 12 px gap, and a
/// little slack for rounding.
const double kSidebarRowChrome = 12 * 4 + 22 + 12 + 4;

/// Widest share of the window the sidebar may take, so the page beside it
/// keeps most of the room at the largest Reading Size.
const double kSidebarMaxShare = 0.4;

/// The sidebar width at which every one of [labels] fits on one line at the
/// current text scale (Reading Size): [kSidebarWidth] while they already
/// fit, wider as the text grows, never past [kSidebarMaxShare] of the window.
double sidebarWidthFor(BuildContext context, List<String> labels) {
  // Bold is the widest a label is drawn (the selected row).
  final style = DefaultTextStyle.of(
    context,
  ).style.copyWith(fontWeight: FontWeight.w600);
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  final cap = math.max(
    kSidebarWidth,
    MediaQuery.sizeOf(context).width * kSidebarMaxShare,
  );
  return (widest + kSidebarRowChrome).clamp(kSidebarWidth, cap);
}
