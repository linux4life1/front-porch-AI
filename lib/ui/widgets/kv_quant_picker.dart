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

import 'package:front_porch_ai/services/kobold/kobold_launch_config.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The five attention-cache types KoboldCpp accepts, with what each saves.
class KvQuantPicker extends StatelessWidget {
  const KvQuantPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.fontSize = 13,
  });

  final KvQuant value;
  final ValueChanged<KvQuant> onChanged;
  final double fontSize;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<KvQuant>(
      key: const ValueKey('kv-quant-picker'),
      value: value,
      isExpanded: true,
      dropdownColor: AppColors.surfaceContainerOf(context),
      // Built on the theme's text style: a bare TextStyle here drops the
      // app's font for the platform default.
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.textPrimary(context),
        fontSize: fontSize,
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      items: [
        for (final q in KvQuant.values)
          DropdownMenuItem(value: q, child: Text(q.label)),
      ],
    ),
  );
}
