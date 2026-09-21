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

/// Full-width kill switch while the coworker is looping tools.
class WaifuStopBar extends StatelessWidget {
  const WaifuStopBar({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.negativeAccentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          key: const Key('waifu-abort'),
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle, size: 22),
          label: const Text('Stop'),
          style: FilledButton.styleFrom(
            backgroundColor: danger,
            foregroundColor: AppColors.onChaosAccent,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
