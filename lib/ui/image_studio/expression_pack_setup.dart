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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Step 1 of the Expression-pack dialog: the setup form. Owns its own local
/// choices (set size, variation strength, replace-existing) and reports them
/// once on Start; the dialog then builds the generation session from them.
class ExpressionPackSetup extends StatefulWidget {
  const ExpressionPackSetup({
    super.key,
    required this.baseImage,
    required this.characterName,
    required this.existingEmotions,
    required this.onCancel,
    required this.onStart,
  });

  final Uint8List baseImage;
  final String characterName;

  /// Emotions this character already has images for (drives the default
  /// "keep what you have, generate only the missing" behavior on second
  /// runs — e.g. Starter first, Full later).
  final Set<String> existingEmotions;

  final VoidCallback onCancel;
  final void Function({
    required bool fullSet,
    required double denoise,
    required bool replaceExisting,
    required bool skipExisting,
  })
  onStart;

  @override
  State<ExpressionPackSetup> createState() => _ExpressionPackSetupState();
}

class _ExpressionPackSetupState extends State<ExpressionPackSetup> {
  bool _fullSet = false;
  bool _skipExisting = true;
  // 0.7 default from maintainer field-testing: at 0.5 the img2img anchor
  // dominates and expressions barely move (the face is a small region of an
  // avatar-shaped base); 0.7 changes the face while the base holds identity.
  double _denoise = 0.7;
  bool _replaceExisting = true;

  List<String> get _chosenSet =>
      _fullSet ? kFullExpressionSet : kCuratedExpressionSet;
  int get _existingInChosen =>
      _chosenSet.where(widget.existingEmotions.contains).length;
  int get _effectiveCount => _skipExisting
      ? _chosenSet.length - _existingInChosen
      : _chosenSet.length;

  @override
  Widget build(BuildContext context) {
    final count = (_fullSet ? kFullExpressionSet : kCuratedExpressionSet)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                widget.baseImage,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Every emotion is generated from this base portrait, so the '
                'whole pack stays recognizably ${widget.characterName}.',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _setChoice(
          context,
          selected: !_fullSet,
          title: 'Starter (${kCuratedExpressionSet.length} emotions)',
          subtitle: 'the essentials, quick to generate',
          emotions: kCuratedExpressionSet,
          onTap: () => setState(() => _fullSet = false),
        ),
        const SizedBox(height: 8),
        _setChoice(
          context,
          selected: _fullSet,
          title: 'Full (${kFullExpressionSet.length} emotions)',
          subtitle: 'every expression the chat can show',
          emotions: kFullExpressionSet,
          onTap: () => setState(() => _fullSet = true),
        ),
        if (_existingInChosen > 0) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _skipExisting,
            onChanged: (v) => setState(() => _skipExisting = v ?? true),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.formMasterAccent,
            title: Text(
              'Keep the $_existingInChosen you already have — generate only '
              'the missing ${_chosenSet.length - _existingInChosen}',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 12.5,
              ),
            ),
            subtitle: Text(
              _skipExisting
                  ? 'Your existing expression images stay untouched.'
                  : 'All ${_chosenSet.length} will be regenerated (with '
                        '"replace existing" on, that overwrites the ones '
                        'you kept).',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
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
                value: _denoise,
                min: 0.30,
                max: 0.85,
                divisions: 11,
                activeColor: AppColors.formMasterAccent,
                inactiveColor: AppColors.borderOf(context),
                onChanged: (v) => setState(() => _denoise = v),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                _denoise.toStringAsFixed(2),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        Text(
          'Higher = more expressive, less faithful to the base.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _replaceExisting,
                activeColor: AppColors.formMasterAccent,
                onChanged: (v) => setState(() => _replaceExisting = v ?? true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Replace old images when an emotion is regenerated',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Off adds the new one alongside the old.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Generates $count images one at a time — you can keep, re-roll, or '
          'drop each one before importing.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _effectiveCount == 0
                  ? null
                  : () => widget.onStart(
                      fullSet: _fullSet,
                      denoise: _denoise,
                      replaceExisting: _replaceExisting,
                      skipExisting: _skipExisting,
                    ),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text('Start ($_effectiveCount)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formMasterAccent,
                foregroundColor: AppColors.onChaosAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _setChoice(
    BuildContext context, {
    required bool selected,
    required String title,
    required String subtitle,
    required List<String> emotions,
    required VoidCallback onTap,
  }) {
    final accent = AppColors.formMasterAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardOf(context) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : AppColors.borderOf(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: selected ? accent : AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              emotions.map((e) => EmotionLabels.emoji[e] ?? '🎭').join(' '),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
