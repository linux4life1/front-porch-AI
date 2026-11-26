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

import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A group member's Author's Note: its label with the on/off switch, then
/// [child] (the note and its Strength), greyed in place while off. Edit
/// group and the member editor's "In the group" both build it, so the two
/// cannot drift. Off keeps the text and starts new chats without it.
class MemberNoteSwitch extends StatelessWidget {
  const MemberNoteSwitch({
    super.key,
    required this.label,
    required this.on,
    required this.onChanged,
    required this.switchKey,
    required this.child,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;
  final Key switchKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: kit.fieldLabel(on ? label : '$label · off')),
            SizedBox(
              height: 24,
              child: Tooltip(
                message: on
                    ? 'Turn the note off without losing what you wrote.'
                    : 'The note is kept but starts new chats without it.',
                child: Switch(
                  key: switchKey,
                  value: on,
                  activeTrackColor: AppColors.porchAmberOf(context),
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Opacity(opacity: on ? 1 : 0.45, child: child),
      ],
    );
  }
}
