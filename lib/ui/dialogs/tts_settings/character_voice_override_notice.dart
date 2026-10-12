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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Amber notice naming the open character when THEIR voice overrides the
/// global one, with a jump to where it can be changed. Renders nothing
/// when no character is open or the character follows the global voice —
/// the common case must stay quiet.
class CharacterVoiceOverrideNotice extends StatelessWidget {
  const CharacterVoiceOverrideNotice({super.key, required this.voices});

  final List<TtsVoiceInfo> voices;

  @override
  Widget build(BuildContext context) {
    // Chat is optional in the tree — Settings can open without one, and then
    // there is no "open character" to warn about, so the notice is simply
    // absent rather than an exception that takes the dialog down with it.
    CharacterCard? character;
    try {
      character = Provider.of<ChatService>(
        context,
        listen: false,
      ).activeCharacter;
    } on ProviderNotFoundException {
      character = null;
    }
    final assigned = character?.ttsVoice ?? '';
    if (character == null || assigned.isEmpty) return const SizedBox.shrink();

    final amber = AppColors.porchAmberOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.record_voice_over, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${character.name} has their own voice '
              '(${CharacterVoicePicker.labelFor(assigned, voices)}), so the '
              'voice above will not be used for them. Change it in Edit '
              'Character → Details → Voice.',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
