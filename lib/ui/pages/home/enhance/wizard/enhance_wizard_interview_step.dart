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

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/wizard/enhance_wizard_chrome.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Step 3 of the AI Enhance wizard before the run: which parts of the card
/// the interview may rewrite, the 18+ switch, and the last run's error.
class EnhanceInterviewChecklist extends StatelessWidget {
  const EnhanceInterviewChecklist({
    super.key,
    required this.selection,
    required this.onSelectionChanged,
    required this.nsfw,
    required this.onNsfwChanged,
    required this.userTurnCount,
    required this.runError,
  });

  final EnhanceSelection selection;
  final ValueChanged<EnhanceSelection> onSelectionChanged;
  final bool nsfw;
  final ValueChanged<bool> onNsfwChanged;

  /// The picked chat's user turns; null before its context has loaded.
  final int? userTurnCount;
  final String? runError;

  EnhanceSelection _with({
    bool? description,
    bool? personality,
    bool? exampleDialogue,
    bool? scenario,
    bool? greetings,
    bool? lorebook,
    bool? porchLife,
  }) => EnhanceSelection(
    description: description ?? selection.description,
    personality: personality ?? selection.personality,
    exampleDialogue: exampleDialogue ?? selection.exampleDialogue,
    scenario: scenario ?? selection.scenario,
    greetings: greetings ?? selection.greetings,
    lorebook: lorebook ?? selection.lorebook,
    porchLife: porchLife ?? selection.porchLife,
  );

  @override
  Widget build(BuildContext context) {
    Widget row(
      String label,
      String hint,
      bool value,
      ValueChanged<bool> onChanged,
    ) {
      return CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: AppColors.porchAmberOf(context),
        checkColor: AppColors.onChaosAccent,
        contentPadding: EdgeInsets.zero,
        title: Text(
          label,
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
        ),
        subtitle: Text(
          hint,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
      );
    }

    return EnhanceStepScroll(
      children: [
        EnhanceStepHeading(text: 'What should the interview rewrite?'),
        EnhanceStepBody(
          text:
              'Tick the parts of the card the AI may rewrite. Everything it '
              'writes is shown to you on the next step before anything is saved.',
        ),
        if ((userTurnCount ?? 99) < 2) ...[
          EnhanceCallout(
            icon: Icons.hourglass_bottom,
            text:
                'Heads up: this chat is very short, so the AI has little to '
                'work with — results may be thin.',
            accent: AppColors.porchHoneyOf(context),
          ),
          const SizedBox(height: 8),
        ],
        row(
          'Description',
          'Physical appearance, rewritten with detail from the story',
          selection.description,
          (v) => onSelectionChanged(_with(description: v)),
        ),
        row(
          'Personality',
          'Inner traits grounded in how they actually behaved',
          selection.personality,
          (v) => onSelectionChanged(_with(personality: v)),
        ),
        row(
          'Example dialogue',
          'Teaching lines mined from their real voice in the chat',
          selection.exampleDialogue,
          (v) => onSelectionChanged(_with(exampleDialogue: v)),
        ),
        Divider(color: AppColors.borderOf(context)),
        row(
          'Scenario',
          'Re-anchor the opening situation to where the story went',
          selection.scenario,
          (v) => onSelectionChanged(_with(scenario: v)),
        ),
        row(
          'First message + alternates',
          'Fresh openings written in the voice from the chat',
          selection.greetings,
          (v) => onSelectionChanged(_with(greetings: v)),
        ),
        row(
          'Lorebook',
          'World entries built from places and facts the story revealed',
          selection.lorebook,
          (v) => onSelectionChanged(_with(lorebook: v)),
        ),
        row(
          'Porch Life (wardrobe, ambitions, likes)',
          'Propose what they wear and carry, long-term goals, and tastes — you keep or accept each list on the next step',
          selection.porchLife,
          (v) => onSelectionChanged(_with(porchLife: v)),
        ),
        Divider(color: AppColors.borderOf(context)),
        SwitchListTile(
          value: nsfw,
          onChanged: onNsfwChanged,
          dense: true,
          activeThumbColor: AppColors.porchAmberOf(context),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Allow 18+ themes',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary(context),
            ),
          ),
          subtitle: Text(
            'Lets suggestive material from the chat shape the card',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        ),
        if (runError != null) ...[
          const SizedBox(height: 8),
          EnhanceCallout(
            icon: Icons.error_outline,
            text: runError!,
            accent: AppColors.porchTerracottaOf(context),
          ),
        ],
      ],
    );
  }
}

/// Step 3 while the interview runs: status line, progress bar, and the
/// streamed preview.
class EnhanceInterviewProgress extends StatelessWidget {
  const EnhanceInterviewProgress({
    super.key,
    required this.characterName,
    required this.statusText,
    required this.previewText,
  });

  final String characterName;
  final String statusText;
  final String previewText;

  @override
  Widget build(BuildContext context) {
    return EnhanceStepScroll(
      children: [
        EnhanceStepHeading(text: 'Interviewing $characterName...'),
        EnhanceStepBody(
          text:
              'The AI is studying the chat and rewriting the card. This takes a '
              'few minutes on local models.',
        ),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          backgroundColor: AppColors.surfaceContainerOf(context),
          valueColor: AlwaysStoppedAnimation<Color>(
            AppColors.porchAmberOf(context),
          ),
        ),
        const SizedBox(height: 10),
        if (previewText.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                previewText,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
