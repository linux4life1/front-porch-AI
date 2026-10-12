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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'world_edit_draft.dart';

/// Climate picker block for the create/edit World dialog: label +
/// dropdown over [Biome.builtIns] plus 'Custom climate...', and the "what
/// it feels like" preview. [setDialogState] is the dialog's
/// StatefulBuilder setState; [draft] is the shared edit-session draft.
class WorldClimateSection extends StatelessWidget {
  const WorldClimateSection({
    super.key,
    required this.draft,
    required this.setDialogState,
  });

  final WorldEditDraft draft;
  final StateSetter setDialogState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Climate picker — not jargon "biome"; show what
        // the weather will *feel* like in story.
        Text(
          'Climate',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'How the weather behaves in this place — seasons, '
          'rain, heat, storms. Characters react to it in chat '
          'when weather is on.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('world-climate-picker'),
          // ignore: deprecated_member_use
          value: draft.selectedBiomeId ?? Biome.temperate.id,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          dropdownColor: AppColors.surfaceOf(context),
          selectedItemBuilder: (_) => [
            for (final b in Biome.builtIns)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  b.displayName,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Custom climate',
                style: TextStyle(
                  color: AppColors.porchAmberOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          items: [
            for (final b in Biome.builtIns)
              DropdownMenuItem(
                value: b.id,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        b.displayName,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        b.description,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            DropdownMenuItem(
              value: 'custom',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Custom climate…',
                      style: TextStyle(
                        color: AppColors.porchAmberOf(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Author this place\'s own weather '
                      '— Mars cold, volcano heat, '
                      'renamed rain.',
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (v) async {
            if (v != 'custom') {
              setDialogState(() => draft.selectedBiomeId = v);
              return;
            }
            final fahrenheit = Provider.of<StorageService>(
              context,
              listen: false,
            ).realismSettings.weatherFahrenheit;
            final result = await showClimateEditorDialog(
              context,
              worldName: draft.nameController.text.trim(),
              existingBiomeJson: draft.customBiomeJson,
              fahrenheit: fahrenheit,
            );
            if (result != null) {
              setDialogState(() {
                draft.customBiomeJson = result;
                draft.selectedBiomeId = 'custom';
              });
            } else if (draft.customBiomeJson == null) {
              // Cancelled with no prior custom — keep
              // the previous built-in selection.
              setDialogState(() {});
            }
          },
        ),
        Builder(
          builder: (_) {
            final biome = draft.selectedBiomeId == 'custom'
                ? (Biome.tryParse(draft.customBiomeJson) ?? Biome.temperate)
                : (Biome.builtInById(draft.selectedBiomeId) ?? Biome.temperate);
            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.formMasterAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.formMasterAccent.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.thermostat,
                        size: 16,
                        color: AppColors.formMasterAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'What it feels like',
                        style: TextStyle(
                          color: AppColors.formMasterAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    biome.description,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  if (biome.feel.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      biome.feel,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (draft.selectedBiomeId == 'custom') ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.tune, size: 15),
                        label: const Text('Edit custom climate'),
                        onPressed: () async {
                          final fahrenheit = Provider.of<StorageService>(
                            context,
                            listen: false,
                          ).realismSettings.weatherFahrenheit;
                          final result = await showClimateEditorDialog(
                            context,
                            worldName: draft.nameController.text.trim(),
                            existingBiomeJson: draft.customBiomeJson,
                            fahrenheit: fahrenheit,
                          );
                          if (result != null) {
                            setDialogState(
                              () => draft.customBiomeJson = result,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
