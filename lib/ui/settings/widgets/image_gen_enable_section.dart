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
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';

/// Settings section that turns image generation on or off.
///
/// Surfaces the same `imageGenEnabled` flag (and the existing
/// [StorageService.setImageGenEnabled] setter) that the Image Studio's
/// GenerationOptionsTab uses, so the feature can be enabled from the main
/// Settings → Voice & Media tab. This matters because the ✨ Image Studio
/// button in the chat toolbar stays hidden until this flag is on, and the
/// only other place to flip it lived behind the character creator's avatar
/// panel — easy to miss. Detailed backend / model / LoRA configuration still
/// lives inside the Image Studio; this is the discoverable on/off switch only.
class ImageGenEnableSection extends StatelessWidget {
  const ImageGenEnableSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        final enabled = storage.imageGenEnabled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Image Generation'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        enabled
                            ? Icons.auto_awesome
                            : Icons.auto_awesome_outlined,
                        color: enabled
                            ? AppColors.presetColors[6] // teal accent
                            : AppColors.textTertiary(context),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Image Generation',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              enabled
                                  ? 'Enabled — Image Studio button shown in chat'
                                  : 'Disabled',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: enabled,
                        onChanged: (val) => storage.setImageGenEnabled(val),
                        activeTrackColor: AppColors.presetColors[6],
                      ),
                    ],
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Adds the ✨ Image Studio button to the chat toolbar. '
                      'Configure the backend, model, and LoRAs inside the '
                      'Image Studio.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
