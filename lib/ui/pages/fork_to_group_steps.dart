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

// Step bodies for ForkToGroupPage, extracted as focused widgets. The page
// (fork_to_group_page.dart) owns all state + nav and passes what each step needs.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

/// Shared accent for the fork wizard (matches the create-group wizard).
Color forkAccent(BuildContext context) => AppColors.resolve(
  context,
  const Color(0xFF7C3AED),
  const Color(0xFF6D28D9),
);

/// Shared avatar used across the fork wizard steps. Resolves the image path via
/// StorageService (same as the rest of the app) so relative paths work too.
Widget forkAvatar(BuildContext context, CharacterCard c, {double radius = 20}) {
  final path = c.imagePath;
  final hasImage = path != null && path.isNotEmpty;
  return CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.surfaceContainerOf(context),
    backgroundImage: hasImage
        ? FileImage(
            Provider.of<StorageService>(
              context,
              listen: false,
            ).resolveCharacterImage(path),
          )
        : null,
    child: hasImage ? null : Text(c.name.isNotEmpty ? c.name[0] : '?'),
  );
}

Widget forkStepHeader(BuildContext context, String title, {String? subtitle}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary(context),
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: AppColors.textSecondary(context))),
      ],
      const SizedBox(height: 16),
    ],
  );
}

class ForkSetupStep extends StatelessWidget {
  const ForkSetupStep({
    super.key,
    required this.nameController,
    required this.scenarioController,
    required this.turnOrder,
    required this.onNameChanged,
    required this.onTurnOrderChanged,
  });

  final TextEditingController nameController;
  final TextEditingController scenarioController;
  final TurnOrder turnOrder;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<TurnOrder> onTurnOrderChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        forkStepHeader(context, 'Group Setup'),
        AppTextField(
          controller: nameController,
          onChanged: onNameChanged,
          decoration: const InputDecoration(labelText: 'Group Name'),
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        const SizedBox(height: 20),
        AppTextField(
          controller: scenarioController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Scenario (optional)',
            hintText: 'Set the scene for the group conversation...',
          ),
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        const SizedBox(height: 24),
        Text(
          'Turn Order',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 8),
        SegmentedButton<TurnOrder>(
          segments: const [
            ButtonSegment(
              value: TurnOrder.roundRobin,
              label: Text('Round Robin'),
              icon: Icon(Icons.repeat),
            ),
            ButtonSegment(
              value: TurnOrder.random,
              label: Text('Random'),
              icon: Icon(Icons.shuffle),
            ),
          ],
          selected: {turnOrder},
          onSelectionChanged: (v) => onTurnOrderChanged(v.first),
        ),
        const SizedBox(height: 10),
        Text(
          turnOrder == TurnOrder.roundRobin
              ? 'Round Robin — characters take turns in a fixed, repeating order '
                    '(the order set on the Characters step).'
              : 'Random — each turn a character is chosen at random (the last '
                    'speaker won\'t go twice in a row).',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }
}

class ForkEntranceStep extends StatelessWidget {
  const ForkEntranceStep({
    super.key,
    required this.character,
    required this.controller,
    required this.creative,
    required this.turnOrder,
    required this.onCreativeChanged,
  });

  final CharacterCard character;
  final TextEditingController controller;
  final bool creative;
  final TurnOrder turnOrder;
  final ValueChanged<bool> onCreativeChanged;

  @override
  Widget build(BuildContext context) {
    final c = character;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        forkStepHeader(
          context,
          'Entrance — ${c.name}',
          subtitle:
              'Optional. Leave blank and ${c.name} simply joins the turn order.',
        ),
        Row(
          children: [
            forkAvatar(context, c, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'How does ${c.name} arrive?',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Entrance (optional)',
            hintText: 'How they enter the scene...',
          ),
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        const SizedBox(height: 16),
        Text(
          'How your text is used:',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
        RadioGroup<bool>(
          groupValue: creative,
          onChanged: (v) => onCreativeChanged(v ?? false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<bool>(
                value: false,
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Opening line (default)',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  "Your text is used as ${c.name}'s entrance exactly as written (no AI).",
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ),
              RadioListTile<bool>(
                value: true,
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Direction',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  'The AI writes the entrance in their own voice from your text.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (turnOrder == TurnOrder.roundRobin)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'After all entrances, the next turn follows whoever falls right '
              'after the last arrival in the rotation.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Review ───────────────────────────────────────────────────────────────

class ForkReviewStep extends StatelessWidget {
  const ForkReviewStep({
    super.key,
    required this.name,
    required this.turnOrder,
    required this.scenario,
    required this.added,
    required this.entranceTextFor,
    required this.creativeFor,
  });

  final String name;
  final TurnOrder turnOrder;
  final String scenario;
  final List<CharacterCard> added;
  final String Function(CharacterCard) entranceTextFor;
  final bool Function(CharacterCard) creativeFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        forkStepHeader(context, 'Review'),
        _row(context, 'Group name', name),
        _row(
          context,
          'Turn order',
          turnOrder == TurnOrder.roundRobin ? 'Round Robin' : 'Random',
        ),
        if (scenario.isNotEmpty) _row(context, 'Scenario', scenario),
        const SizedBox(height: 16),
        Text(
          'Arrivals',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        ...added.map((c) {
          final text = entranceTextFor(c);
          final mode = text.isEmpty
              ? 'silent join'
              : (creativeFor(c)
                    ? 'entrance (Direction)'
                    : 'entrance (Opening line)');
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    forkAvatar(context, c, radius: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.name,
                        style: TextStyle(color: AppColors.textPrimary(context)),
                      ),
                    ),
                    Text(
                      mode,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 42, top: 4),
                    child: Text(
                      '"$text"',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }
}
