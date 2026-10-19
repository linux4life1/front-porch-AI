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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/dialogs/piper_voice_label.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Piper (legacy/lightweight) settings block for the TTS settings dialog:
/// the installed-voice picker, the Browse action ([onBrowse]) and the
/// built-in info card.
class PiperTtsSettings extends StatelessWidget {
  const PiperTtsSettings({
    super.key,
    required this.settings,
    required this.installedVoices,
    required this.catalog,
    required this.onBrowse,
  });

  final TtsSettings settings;
  final List<String> installedVoices;
  final List<PiperVoice> catalog;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Default Voice',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: installedVoices.contains(settings.ttsVoiceModel)
                    ? settings.ttsVoiceModel
                    : null,
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(color: AppColors.textPrimary(context)),
                // isExpanded avoids a ~12px right-edge overflow on long
                // installed-voice filenames (matches the fix already on
                // the main tree so this doesn't reintroduce a merge conflict).
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: installedVoices.isEmpty
                      ? 'No voices installed'
                      : 'Select a voice',
                  hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: installedVoices
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          piperVoiceLabel(v, catalog),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) settings.setTtsVoiceModel(val);
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Browse'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formAccentOf(context),
                foregroundColor: AppColors.onAccentOf(context),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: AppColors.resolve(
                  context,
                  AppColors.logReady,
                  AppColors.bondHighLight,
                ),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Piper TTS is built in — voices download on install and '
                  'play with the in-app engine.',
                  style: TextStyle(
                    color: AppColors.resolve(
                      context,
                      AppColors.logReady,
                      AppColors.bondHighLight,
                    ),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
