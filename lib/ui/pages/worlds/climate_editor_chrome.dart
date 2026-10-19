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
//
// The climate editor's frame chrome, styled per the approved mockup: the
// amber-washed header (title + start-from select + close) and the pill
// footer (ghost Cancel, amber Save with the dimmed disabled state).

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class ClimateEditorHeader extends StatelessWidget {
  const ClimateEditorHeader({
    super.key,
    required this.worldName,
    required this.templateId,
    required this.onTemplate,
    required this.onClose,
  });

  final String worldName;
  final String templateId;
  final ValueChanged<String> onTemplate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [amber.withValues(alpha: 0.10), Colors.transparent],
          stops: const [0, 0.55],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              worldName.trim().isEmpty
                  ? 'Custom Climate'
                  : 'Custom Climate — ${worldName.trim()}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: templateId,
                isDense: true,
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
                items: [
                  if (templateId == 'custom')
                    const DropdownMenuItem(
                      value: 'custom',
                      child: Text('Current custom'),
                    ),
                  for (final b in Biome.builtIns)
                    DropdownMenuItem(
                      value: b.id,
                      child: Text('Start from: ${b.displayName}'),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onTemplate(id);
                },
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.textTertiary(context)),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class ClimateEditorFooter extends StatelessWidget {
  const ClimateEditorFooter({
    super.key,
    required this.canSave,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              side: BorderSide(color: AppColors.borderOf(context)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.formAccentOf(context),
              foregroundColor: AppColors.onAccentOf(context),
              disabledBackgroundColor: AppColors.formAccentOf(
                context,
              ).withValues(alpha: 0.45),
              disabledForegroundColor: AppColors.onAccentOf(
                context,
              ).withValues(alpha: 0.7),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: canSave ? onSave : null,
            child: const Text('Save climate'),
          ),
        ],
      ),
    );
  }
}
