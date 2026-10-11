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

/// Dialog title with the coworker's portrait, so an ask or a question
/// comes from her and not from the app.
class WaifuDialogFace extends StatelessWidget {
  const WaifuDialogFace({
    super.key,
    required this.name,
    required this.line,
    this.portrait,
  });

  final String name;
  final String line;
  final File? portrait;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final face = portrait;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          key: const Key('waifu-dialog-face'),
          radius: 22,
          backgroundColor: amber.withValues(alpha: 0.25),
          foregroundImage: face == null ? null : FileImage(face),
          child: Text(
            initial,
            style: TextStyle(color: amber, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            line,
            style: TextStyle(
              fontSize: 17,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }
}
