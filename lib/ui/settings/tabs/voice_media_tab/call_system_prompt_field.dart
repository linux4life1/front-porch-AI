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

/// The Call System Prompt box. It edits a value that lives in StorageService,
/// and every keystroke notifies — which rebuilds this whole tab. A field whose
/// identity or `initialValue` is derived from that value is therefore torn
/// down mid-word (the old `key: ValueKey(prompt.hashCode)` did exactly that:
/// new key → `canUpdate` fails → new EditableText, new FocusNode, caret gone
/// after the first character). Owning the controller keeps ONE element alive
/// across those rebuilds while still following EXTERNAL changes — the Reset
/// button — through [didUpdateWidget].
class CallSystemPromptField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const CallSystemPromptField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<CallSystemPromptField> createState() => _CallSystemPromptFieldState();
}

class _CallSystemPromptFieldState extends State<CallSystemPromptField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(CallSystemPromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Echoing our own onChanged back into the controller would move the caret
    // to the end on every keystroke, so only adopt a value that differs from
    // what is already typed.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 4,
      minLines: 2,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        hintText: 'Instructions appended during voice calls...',
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
        ),
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: widget.onChanged,
    );
  }
}
