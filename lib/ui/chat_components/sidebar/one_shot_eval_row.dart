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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'sidebar_tokens.dart';

/// One-Shot Eval Auto/On/Off, sitting directly above the tool-calling pill
/// because Auto's choice depends on that verdict. It used to live in the
/// Character State gear flyout next to a per-chat Needs switch; the card
/// editor owns Needs now, so the flyout is gone.
class OneShotEvalRow extends StatelessWidget {
  final ChatService chat;

  const OneShotEvalRow({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    // Listening on purpose: one-shot eval lives on StorageService.
    final storage = Provider.of<StorageService>(context);
    final value = storage.realismSettings.oneShotMode;
    final accent = AppColors.journalAccentOf(context);
    final ValueChanged<OneShotMode>? onChanged = chat.isGenerating
        ? null
        : (mode) => storage.realismSettings.setOneShotMode(mode);

    // Auto is listed first because it is the default and the recommendation.
    Widget pill(OneShotMode mode, String name) {
      final selected = value == mode;
      return Semantics(
        button: true,
        selected: selected,
        label: 'One-Shot Eval $name',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged(mode),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.22)
                  : AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : AppColors.borderOf(context),
              ),
            ),
            child: Text(
              name,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.textPrimary(context)
                    : AppColors.textSecondary(context),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: SidebarTokens.wellPadding,
      margin: const EdgeInsets.only(bottom: SidebarTokens.sectionGap),
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed,
                size: 14,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'One-Shot Eval',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              pill(OneShotMode.auto, 'Auto'),
              const SizedBox(width: 4),
              pill(OneShotMode.on, 'On'),
              const SizedBox(width: 4),
              pill(OneShotMode.off, 'Off'),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Fuses the realism evals into a single LLM call for roughly '
            'double the processing speed. Auto uses it on remote AI '
            'services that support tool calls, and keeps the safer '
            'multi-call path on local models, where small models can '
            'struggle with the combined prompt.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
