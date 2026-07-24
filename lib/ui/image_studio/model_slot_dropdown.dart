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

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The ONE image-model dropdown for the create/edit model-slot split
/// (phase #12): reads and writes either [ImageGenSettings.imageGenModel]
/// (the CREATE slot — txt2img/base generation) or
/// [ImageGenSettings.imageGenEditModel] (the EDIT slot — instruction edits,
/// edit-first expression packs). One widget serves every picker site
/// (Image Studio settings, the Edit tab, the creators' engine strip), so a
/// new surface can't accidentally bind the wrong slot.
///
/// Create-slot instances render [EditModelInCreateSlotWarning] beneath the
/// field — the non-blocking "this looks like an edit model" nudge.
class ModelSlotDropdown extends StatelessWidget {
  const ModelSlotDropdown({
    super.key,
    required this.settings,
    required this.options,
    required this.editSlot,
    required this.decoration,
    this.keyPrefix = 'model-slot',
    this.fontSize = 11,
  });

  final ImageGenSettings settings;

  /// Available models as (value, label) pairs; label falls back to value at
  /// call sites where the backend has no display names.
  final List<({String value, String label})> options;

  /// true → bound to the EDIT slot; false → the CREATE slot (+ warning).
  final bool editSlot;

  final InputDecoration decoration;
  final String keyPrefix;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final current = editSlot ? settings.imageGenEditModel : settings.imageGenModel;
    final known = options.any((o) => o.value == current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('$keyPrefix-$current'),
          initialValue: known ? current : null,
          dropdownColor: AppColors.surfaceContainerOf(context),
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: fontSize,
          ),
          isExpanded: true,
          menuMaxHeight: 400,
          decoration: decoration,
          items: options
              .map(
                (o) => DropdownMenuItem(
                  value: o.value,
                  child: Text(
                    o.label,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: fontSize,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            if (editSlot) {
              settings.setImageGenEditModel(v);
            } else {
              settings.setImageGenModel(v);
            }
          },
        ),
        if (!editSlot) EditModelInCreateSlotWarning(modelName: current),
      ],
    );
  }
}

/// Non-blocking nudge shown under a CREATE-slot picker whose model name
/// smells like an edit/inpaint model ([looksLikeEditModel]). Edit models
/// can't paint from scratch, so leaving one in the create slot silently
/// breaks base-image generation — but the heuristic can be wrong in both
/// directions, so this warns and never gates.
class EditModelInCreateSlotWarning extends StatelessWidget {
  const EditModelInCreateSlotWarning({super.key, required this.modelName});

  final String modelName;

  @override
  Widget build(BuildContext context) {
    if (!looksLikeEditModel(modelName)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.formMasterAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.formMasterAccent.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          'This looks like an edit/inpaint model — those usually can\'t '
          'generate images from scratch. Pick it as the Edit model instead, '
          'and choose a regular checkpoint here.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
