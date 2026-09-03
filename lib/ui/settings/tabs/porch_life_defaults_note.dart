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

/// Closing note on Porch Life — extracted so the tab stays under 500.
class PorchLifeDefaultsNote extends StatelessWidget {
  const PorchLifeDefaultsNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        border: Border(
          left: BorderSide(color: AppColors.porchAmberOf(context), width: 3),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Text(
        'These are the defaults new chats start from. Any single chat can '
        'overrule them from its sidebar — Chaos Mode, Needs, Objectives '
        'and Growth Rings all have a switch there for that one story.',
        style: TextStyle(
          fontSize: 12.5,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}
