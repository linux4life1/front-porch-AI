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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// The Realism/feature toggles moved to the Porch Life tab (2026-08-07):
/// nesting them under the master realism switch meant turning the engine OFF
/// also HID the switches for features that work without it. This pointer is
/// all that remains in General — see lib/ui/settings/tabs/porch_life_tab.dart.
class PorchLifePointerCard extends StatelessWidget {
  const PorchLifePointerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cottage_outlined,
            size: 18,
            color: AppColors.porchAmberOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The Realism Engine, passage of time, weather, the Journal, '
              'dreams, promises, ambitions and the welcome-back recap all live '
              'in the Porch Life tab now — each one saying plainly what it '
              'needs.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
