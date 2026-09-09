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

/// Used tokens vs context window. Fill ≥ 75% is the compact line.
class WaifuContextBar extends StatelessWidget {
  const WaifuContextBar({super.key, required this.session, this.onCompact});

  final WaifuSession session;

  /// When fill ≥ 75%, tap folds old turns. Null = display only.
  final VoidCallback? onCompact;

  @override
  Widget build(BuildContext context) {
    final used = session.tokensUsed;
    final budget = session.contextBudget < 1
        ? kWaifuDefaultContextTokens
        : session.contextBudget;
    final fill = budget <= 0 ? 0.0 : (used / budget).clamp(0.0, 1.0);
    final hot = fill >= kWaifuCompactAt;
    final amber = AppColors.porchAmberOf(context);
    final danger = AppColors.negativeAccentOf(context);
    final bar = hot ? danger : amber;
    final body = Padding(
      key: const Key('waifu-context-bar'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Context',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              Text(
                '$used / $budget',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: hot ? danger : AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fill,
              minHeight: 8,
              color: bar,
              backgroundColor: AppColors.surfaceContainerOf(context),
            ),
          ),
        ],
      ),
    );
    if (!hot || onCompact == null) return body;
    return Semantics(
      button: true,
      label: 'Fold old turns',
      child: InkWell(
        key: const Key('waifu-context-bar-compact'),
        onTap: onCompact,
        child: body,
      ),
    );
  }
}
