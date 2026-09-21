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
              child: _WaifuToolRow(chip: chips[i], index: i),
            ),
        ],
      ),
    );
  }
}

class _WaifuToolRow extends StatelessWidget {
  const _WaifuToolRow({required this.chip, required this.index});

  final WaifuToolChip chip;
  final int index;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final fail = AppColors.negativeAccentOf(context);
    final pending = chip.pending;
    final mark = pending
        ? SizedBox(
            key: Key('waifu-tool-pending-$index'),
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: amber),
          )
        : Icon(Icons.circle, size: 6, color: chip.ok ? amber : fail);
    return Row(
      children: [
        SizedBox(width: 10, height: 10, child: Center(child: mark)),
        const SizedBox(width: 8),
        Text(
          chip.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontStyle: pending ? FontStyle.italic : FontStyle.normal,
            color: pending ? amber : AppColors.textSecondary(context),
          ),
        ),
        if (chip.detail.trim().isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chip.detail,
              maxLines: chip.ok ? 1 : 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontStyle: pending ? FontStyle.italic : FontStyle.normal,
                color: chip.ok
                    ? AppColors.textTertiary(context)
                    : AppColors.negativeAccentOf(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
