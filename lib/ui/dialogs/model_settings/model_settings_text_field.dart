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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The filled, borderless text field the Model Settings dialog uses for its
/// context size, API URL and API key boxes.
class ModelSettingsTextField extends StatelessWidget {
  const ModelSettingsTextField({
    super.key,
    required this.label,
    required this.controller,
    this.isNumber = false,
    this.isObscured = false,
    this.onEditingComplete,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool isNumber;
  final bool isObscured;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      obscureText: isObscured,
      onEditingComplete: onEditingComplete,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
