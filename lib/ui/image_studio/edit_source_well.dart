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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The single reference-photo well on the Edit tab: tap to pick a photo, ✕ to
/// clear. Single image only (multi-reference was dropped across the app), so
/// there is exactly one well and no "soon" placeholders.
class EditSourceWell extends StatelessWidget {
  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const EditSourceWell({
    super.key,
    required this.bytes,
    required this.busy,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final has = bytes != null;
    return GestureDetector(
      onTap: busy ? null : onPick,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: has ? AppColors.formMasterAccent : AppColors.borderOf(context),
            width: has ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: has
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes!, fit: BoxFit.cover),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: busy ? null : onClear,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundOf(context)
                              .withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.iconSecondary(context),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.iconSecondary(context),
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add photo',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
