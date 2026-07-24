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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The re-roll editor: with img2img, same seed + same prompt + same strength
/// reproduces the SAME image — so a re-roll is always a chance to steer.
/// Prompt and strength are the levers; the pack's shared seed is kept by
/// default (consistency), with an explicit "new random seed" option when the
/// user wants different noise (that seed then sticks to the slot).
Future<void> showPackRerollEditor(
  BuildContext context,
  ExpressionPackSession session,
  int index,
) async {
  final controller = TextEditingController(
    text: session.effectivePromptFor(index),
  );
  var denoise = session.effectiveDenoiseFor(index);
  var newSeed = false;
  final emotion = session.slots[index].emotion;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Re-roll «$emotion»',
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary(context),
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 6,
                minLines: 3,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textPrimary(context),
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  helperText:
                      'Your wording sticks to this slot for future re-rolls.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Variation strength',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: denoise,
                      min: 0.30,
                      max: 0.85,
                      divisions: 11,
                      activeColor: AppColors.formMasterAccent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: (v) => setState(() => denoise = v),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      denoise.toStringAsFixed(2),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                value: newSeed,
                onChanged: (v) => setState(() => newSeed = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.formMasterAccent,
                title: Text(
                  'New random seed',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12.5,
                  ),
                ),
                subtitle: Text(
                  'Off keeps the pack-consistent noise — the same seed with '
                  'unchanged prompt and strength reproduces the same image, '
                  'so tweak something above or roll new noise here.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.casino_outlined, size: 16),
            label: const Text('Re-roll'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
            ),
          ),
        ],
      ),
    ),
  );
  final prompt = controller.text;
  controller.dispose();
  if (confirmed == true) {
    unawaited(
      session.reroll(
        index,
        promptOverride: prompt,
        denoiseOverride: denoise,
        newSeed: newSeed,
      ),
    );
  }
}
