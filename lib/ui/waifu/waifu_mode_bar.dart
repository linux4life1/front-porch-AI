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
import 'package:front_porch_ai/ui/waifu/waifu_scope_badge.dart';

class WaifuModeBar extends StatelessWidget {
  const WaifuModeBar({
    super.key,
    required this.mode,
    required this.onChanged,
    this.pathMode = WaifuPathMode.folderJail,
    this.enabled = true,
    this.preserveThinking = false,
    this.onPreserveThinking,
  });

  final WaifuMode mode;
  final ValueChanged<WaifuMode> onChanged;
  final WaifuPathMode pathMode;
  final bool enabled;
  final bool preserveThinking;
  final ValueChanged<bool>? onPreserveThinking;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WaifuModeBadge(
                key: const Key('waifu-harness-mode'),
                mode: mode,
              ),
              WaifuScopeBadge(
                key: const Key('waifu-harness-scope'),
                pathMode: pathMode,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in WaifuMode.values)
                ChoiceChip(
                  key: Key('waifu-mode-${m.name}'),
                  label: Text(m.name[0].toUpperCase() + m.name.substring(1)),
                  selected: mode == m,
                  onSelected: !enabled || mode == m
                      ? null
                      : (_) => onChanged(m),
                  selectedColor: amber.withValues(alpha: 0.3),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            waifuPathModeSessionLine(pathMode),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          if (mode == WaifuMode.yolo) ...[
            const SizedBox(height: 6),
            Text(
              waifuYoloWarning(pathMode),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
          CheckboxListTile(
            key: const Key('waifu-preserve-thinking'),
            value: preserveThinking,
            onChanged: !enabled || onPreserveThinking == null
                ? null
                : (v) => onPreserveThinking!(v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Preserve thinking',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            subtitle: Text(
              'Send prior thought tokens back on the next turn. Off drops them.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }
}
