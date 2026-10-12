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
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/vision_palette.dart';

/// Shared "Vision: supported / none / unknown" pill, driven by a resolver
/// verdict. "Unknown" (server unreachable, model still loading, inconclusive
/// error) is rendered distinctly so a failed CHECK never reads as a
/// definitive "this model can't see".
Widget visionStatusPill(BuildContext context, VisionSupport support) {
  final green = VisionPalette.supportedOf(context);
  final unknown = support.source == VisionSource.unknown;
  final color = support.supported ? green : AppColors.textTertiary(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      support.supported
          ? 'Vision: supported'
          : (unknown ? 'Vision: could not check' : 'Vision: none'),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
    ),
  );
}
