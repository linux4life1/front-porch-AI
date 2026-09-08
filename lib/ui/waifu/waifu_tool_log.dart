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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One tool row per call, stacked — not a wrapping chip cloud.
class WaifuToolLog extends StatelessWidget {
  const WaifuToolLog({super.key, required this.chips});

  final List<WaifuToolChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    final amber = AppColors.porchAmberOf(context);
    final fail = AppColors.negativeAccentOf(context);
    return Padding(
      key: const Key('waifu-tool-log'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < chips.length; i++)
            Padding(
              key: Key('waifu-tool-row-$i'),
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  chips[i].running
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            key: Key('waifu-tool-pending-$i'),
                            strokeWidth: 1.6,
                            color: amber,
                          ),
                        )
                      : Icon(
                          Icons.circle,
                          size: 6,
                          color: chips[i].ok ? amber : fail,
                        ),
                  const SizedBox(width: 8),
                  Text(
                    chips[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  if (chips[i].detail.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chips[i].detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
