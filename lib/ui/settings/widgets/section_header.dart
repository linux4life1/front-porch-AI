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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Section header for the Settings tabs.
///
/// Warm-porch makeover: titles use the warm amber accent
/// ([AppColors.porchAmberOf]) — light-mode safe — instead of the old cool
/// blue. Shared by every settings tab so the whole page stays consistent.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.porchAmberOf(context);
    return Text(
      title,
      style:
          theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: accent,
          ) ??
          TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent),
    );
  }
}
