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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Prominent subject explanation card. Describes the currently selected
/// Image Studio subject (Freeform / Character / Persona).
class ModeInfoCard extends StatelessWidget {
  final ImageGenMode mode;

  const ModeInfoCard({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final (title, body) = _infoFor(mode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  (String, String) _infoFor(ImageGenMode m) {
    switch (m) {
      case ImageGenMode.characterPortrait:
        return (
          'Character Portrait',
          'Tight visual close-up using only the character\'s appearance description and current expression from the card. No personality or backstory leaks into the image.',
        );
      case ImageGenMode.customPrompt:
        return (
          'Freeform',
          'Describe anything you like — the prompt is fully yours. Leave it blank and tap Craft to picture the current scene from the recent chat. Style is enforced at the end for consistency.',
        );
      case ImageGenMode.userAvatar:
        return (
          'Your Persona',
          'Portrait of your persona using the appearance description you provided. Close-up, expressive, high-quality rendering.',
        );
    }
  }
}
