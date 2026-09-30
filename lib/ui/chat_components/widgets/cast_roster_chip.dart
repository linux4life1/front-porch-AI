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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One face in the desktop cast strip. Soft guests carry the amber GUEST
/// mark and the **only** Promote control (member card / Lite NPC banner
/// stay status-only). Matches the web CastBar.
class CastRosterChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool isFocused;
  final bool isLite;
  final File? imageFile;
  final bool promoteEnabled;
  final VoidCallback onFocus;
  final VoidCallback? onPromote;

  const CastRosterChip({
    super.key,
    required this.name,
    required this.color,
    required this.isFocused,
    required this.isLite,
    this.imageFile,
    this.promoteEnabled = true,
    required this.onFocus,
    this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onFocus,
      child: SizedBox(
        width: isLite ? 72 : 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isFocused ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: color,
                child: imageFile == null
                    ? Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : ClipOval(
                        child: Image.file(
                          imageFile!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Text(
                            name.isNotEmpty ? name[0] : '?',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: isFocused
                    ? AppColors.textPrimary(context)
                    : AppColors.textTertiary(context),
              ),
            ),
            if (isLite) ...[
              Text(
                'GUEST',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: AppColors.porchAmberOf(context),
                ),
              ),
              if (onPromote != null)
                SizedBox(
                  height: 20,
                  child: TextButton(
                    onPressed: promoteEnabled ? onPromote : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onChaosAccent,
                      backgroundColor: AppColors.formMasterAccent,
                      disabledForegroundColor: AppColors.onChaosAccent
                          .withValues(alpha: 0.5),
                      disabledBackgroundColor: AppColors.formMasterAccent
                          .withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 18),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Promote', style: TextStyle(fontSize: 9)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
