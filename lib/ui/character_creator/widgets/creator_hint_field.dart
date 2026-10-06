// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Hint-only styled text field used across the automated creator step
/// (relationship, custom kinks, backstory notes, description). Restored from
/// the pre-refactor `_styledTextField`; auto-saves and notifies on change so
/// the wizard's Generate button reacts to typing.
///
/// Stateful only to own the save debounce: on Windows and Linux every
/// preference write rewrites the whole preferences file on the UI thread,
/// so a save per keystroke stalled typing (#371; invisible on macOS).
/// `notify()` stays immediate — it is just a listener callback, and the
/// Generate button's enabled state rides on it.
class CreatorHintField extends StatefulWidget {
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
  State<CreatorHintField> createState() => _CreatorHintFieldState();
}

class _CreatorHintFieldState extends State<CreatorHintField> {
  static const _saveDebounce = Duration(milliseconds: 500);

  Timer? _saveTimer;

  @override
  void dispose() {
    // Flush a pending save so the last keystrokes before leaving the field
    // (or the wizard) are never the ones that get dropped.
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      widget.state.saveState();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final enabled = widget.enabled;
    return TextField(
      controller: widget.controller,
      readOnly: widget.readOnly,
      enabled: enabled,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      style: TextStyle(
        color: enabled
            ? AppColors.textPrimary(context)
            : AppColors.textTertiary(context),
        fontSize: 14,
      ),
      onChanged: (_) {
        _saveTimer?.cancel();
        _saveTimer = Timer(_saveDebounce, state.saveState);
        state.notify();
      },
      decoration: InputDecoration(
        hintText: widget.hint,
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
