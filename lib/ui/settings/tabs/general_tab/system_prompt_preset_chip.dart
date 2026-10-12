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

/// A built-in system-prompt preset. It MUST move the visible field as well as
/// storage: the controller belongs to the settings page, so a notify-driven
/// rebuild never touches its text — writing storage alone left the old prompt
/// on screen and the next keystroke saved that stale text back over the
/// preset. (The saved-prompt dropdown in General does the same two-step.)
class SystemPromptPresetChip extends StatelessWidget {
  const SystemPromptPresetChip({
    super.key,
    required this.label,
    required this.prompt,
    required this.storage,
    required this.systemPromptController,
  });

  final String label;
  final String prompt;
  final StorageService storage;
  final TextEditingController systemPromptController;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        storage.generationSettings.setSystemPrompt(prompt);
        systemPromptController.text = prompt;
      },
    );
  }
}
