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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// How a persona becomes a character: straight into the manual wizard, or
/// through the AI creator, which fills in what a persona does not carry.
enum PersonaToCharacterMode { manual, aiAssist }

/// The user's answer to [showPersonaToCharacterDialog].
class PersonaToCharacterChoice {
  const PersonaToCharacterChoice(this.mode, {required this.swapMacros});
  final PersonaToCharacterMode mode;
  final bool swapMacros;
}

/// Confirms "Use as Persona". Null when cancelled, otherwise whether to swap
/// `{{char}}` and `{{user}}` (only asked when the text uses them).
Future<bool?> showCharacterToPersonaDialog(
  BuildContext context, {
  required String characterName,
  required bool hasMacros,
}) {
  return showWarmDialogOf<bool>(
    context,
    builder: (_) => _ConvertDialog(
      title: 'Use as Persona',
      icon: Icons.switch_account,
      body:
          'Save "$characterName" as a persona you can play as. The name, '
          'description, personality and portrait are copied, plus the '
          'birthday when the character has one. '
          'Greetings, scenario, lorebook and Porch Life stay with the '
          'character, which is not changed.',
      hasMacros: hasMacros,
      actions: (swap) => [
        (label: 'Create Persona', key: 'persona-convert-confirm', value: swap),
      ],
    ),
  );
}

/// Asks how to make a character from a persona. Null when cancelled.
Future<PersonaToCharacterChoice?> showPersonaToCharacterDialog(
  BuildContext context, {
  required String personaName,
  required bool hasMacros,
}) {
  return showWarmDialogOf<PersonaToCharacterChoice>(
    context,
    builder: (_) => _ConvertDialog(
      title: 'Make a Character',
      icon: Icons.person_add_alt_1,
      body:
          'Start a character from "$personaName". Manual opens the character '
          'wizard with the name, description and picture filled in, plus the '
          'birthday when the persona has one. '
          'AI Assist hands the persona to the AI creator, which writes the '
          'personality, scenario and greetings around it. The persona stays.',
      hasMacros: hasMacros,
      actions: (swap) => [
        (
          label: 'Manual',
          key: 'persona-to-char-manual',
          value: PersonaToCharacterChoice(
            PersonaToCharacterMode.manual,
            swapMacros: swap,
          ),
        ),
        (
          label: 'AI Assist',
          key: 'persona-to-char-ai',
          value: PersonaToCharacterChoice(
            PersonaToCharacterMode.aiAssist,
            swapMacros: swap,
          ),
        ),
      ],
    ),
  );
}

typedef _ConvertAction = ({String label, String key, Object value});

class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({
    required this.title,
    required this.icon,
    required this.body,
    required this.hasMacros,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final String body;
  final bool hasMacros;
  final List<_ConvertAction> Function(bool swapMacros) actions;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  bool _swap = true;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    return WarmDialog(
      title: widget.title,
      icon: widget.icon,
      accent: accent,
      width: 380,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WarmDialogText(widget.body),
          if (widget.hasMacros) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('persona-convert-swap'),
              value: _swap,
              onChanged: (v) => setState(() => _swap = v ?? true),
              activeColor: accent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Swap {{char}} and {{user}}',
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              subtitle: Text(
                'Keeps lines like "{{char}} is {{user}}\'s neighbour" '
                'pointing at the right people.',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        warmDialogCancel(context),
        for (final a in widget.actions(_swap))
          warmDialogConfirm(
            context,
            key: ValueKey(a.key),
            label: a.label,
            onPressed: () => Navigator.of(context).pop(a.value),
          ),
      ],
    );
  }
}
