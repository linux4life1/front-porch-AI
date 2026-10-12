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

import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/wizard/enhance_wizard_chrome.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Step 0 of the AI Enhance wizard: what Enhance is, how it works, and
/// whether the character has a chat to learn from.
class EnhanceAboutStep extends StatelessWidget {
  const EnhanceAboutStep({
    super.key,
    required this.characterName,
    required this.sessions,
  });

  final String characterName;

  /// The character's 1:1 chats; null while still loading.
  final List<Map<String, dynamic>>? sessions;

  @override
  Widget build(BuildContext context) {
    final name = characterName;
    final howItWorks = [
      (
        Icons.memory,
        'Pick a model',
        'Any AI backend works — the one you chat with, or a bigger one just '
            'for this.',
      ),
      (
        Icons.chat_bubble_outline,
        'Pick a chat',
        'One real conversation becomes the source of truth. The story\'s '
            'recap and $name\'s journal memories come along too.',
      ),
      (
        Icons.record_voice_over,
        'The interview',
        'The AI studies the chat and rewrites the parts of the character '
            'card you choose — description, personality, example dialogue '
            'and more — grounded in what actually happened.',
      ),
      (
        Icons.fact_check_outlined,
        'You review everything',
        'Every change is shown next to the original, editable, with a '
            'per-field "use this" switch. Nothing is saved until you say so.',
      ),
      (
        Icons.library_add_outlined,
        'A NEW character is born',
        'Saving creates "$name (Enhanced)" in your library — and you can '
            'bring your existing chats along. The original $name is never '
            'touched.',
      ),
    ];

    return EnhanceStepScroll(
      children: [
        EnhanceStepHeading(text: 'What is AI Enhance?'),
        EnhanceStepBody(
          text:
              'Character cards are written before the first hello — but after a '
              'few real conversations, $name has become someone more specific '
              'than the card ever described. AI Enhance closes that gap: it reads '
              'a real chat and rewrites the card so the character on paper matches '
              'the character you actually know.',
        ),
        const SizedBox(height: 8),
        EnhanceStepHeading(text: 'How it works'),
        for (final (icon, title, body) in howItWorks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: AppColors.porchAmberOf(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (sessions == null)
          EnhanceCallout(
            icon: Icons.hourglass_empty,
            text: 'Checking $name\'s chats...',
          )
        else if (sessions!.isEmpty)
          EnhanceCallout(
            icon: Icons.chat_bubble_outline,
            text:
                'AI Enhance grows $name from a real conversation — the chat is '
                'what teaches the AI their true voice. Have a chat with $name '
                'first, then come back.',
            accent: AppColors.porchHoneyOf(context),
          )
        else
          EnhanceCallout(
            icon: Icons.check_circle_outline,
            text: sessions!.length == 1
                ? '$name has 1 chat to learn from — ready when you are.'
                : '$name has ${sessions!.length} chats to learn from — ready '
                      'when you are.',
          ),
      ],
    );
  }
}

/// Step 1: the creator wizard's real Backend & Model [SetupStep].
class EnhanceModelStep extends StatelessWidget {
  const EnhanceModelStep({super.key, required this.creatorState});

  final CreatorState creatorState;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            'The interview is real AI work, so it needs a backend — the same '
            'choices as chatting. A stronger model writes a sharper card; the '
            'chat itself is untouched either way.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        // The creator wizard's FULL Backend & Model step (KoboldCpp local
        // with .gguf pick/launch, Remote API, oMLX) — the identical picker,
        // not a cut-down row.
        Expanded(child: SetupStep(state: creatorState)),
      ],
    );
  }
}

/// Step 2: which chat grounds the rewrite.
class EnhanceChatPickStep extends StatelessWidget {
  const EnhanceChatPickStep({
    super.key,
    required this.characterName,
    required this.sessions,
    required this.selectedSessionId,
    required this.onSelectSession,
  });

  final String characterName;
  final List<Map<String, dynamic>>? sessions;
  final String? selectedSessionId;
  final ValueChanged<String> onSelectSession;

  @override
  Widget build(BuildContext context) {
    final sessions = this.sessions ?? const [];
    return EnhanceStepScroll(
      children: [
        EnhanceStepHeading(text: 'Which chat should teach the AI?'),
        EnhanceStepBody(
          text: sessions.length == 1
              ? 'This chat becomes the source of truth for the rewrite — '
                    'it\'s already selected.'
              : 'The conversation you pick becomes the source of truth for '
                    'the rewrite. Pick the one where '
                    '$characterName felt most like themselves.',
        ),
        for (final s in sessions) _sessionTile(context, s),
      ],
    );
  }

  Widget _sessionTile(BuildContext context, Map<String, dynamic> s) {
    final id = s['id'] as String;
    final selected = id == selectedSessionId;
    final date = s['date'] as DateTime?;
    final dateStr = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, "0")}-'
              '${date.day.toString().padLeft(2, "0")}';
    final messageCount = s['message_count'] ?? 0;
    final userMessageCount = s['user_message_count'] ?? 0;
    final amber = AppColors.porchAmberOf(context);

    return Card(
      color: selected
          ? amber.withValues(alpha: 0.12)
          : AppColors.cardOf(context),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? amber : AppColors.borderOf(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 20,
          color: selected ? amber : AppColors.textTertiary(context),
        ),
        title: Text(
          s['preview'] as String? ?? '',
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$dateStr · $messageCount messages · $userMessageCount yours',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        onTap: () => onSelectSession(id),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
