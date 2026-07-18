// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Hint-only styled text field used across the automated creator step
/// (relationship, custom kinks, backstory notes, description). Restored from
/// the pre-refactor `_styledTextField`; auto-saves and notifies on change so
/// the wizard's Generate button reacts to typing.
class CreatorHintField extends StatelessWidget {
  final CreatorState state;
  final TextEditingController controller;
  final String hint;
  final int? maxLines;
  final int? minLines;
  final bool readOnly;
  final bool enabled;

  const CreatorHintField({
    super.key,
    required this.state,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      style: TextStyle(
        color: enabled
            ? AppColors.textPrimary(context)
            : AppColors.textTertiary(context),
        fontSize: 14,
      ),
      onChanged: (_) {
        state.saveState();
        state.notify();
      },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
        ),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.formMasterAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
