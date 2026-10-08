// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kobold_card_note.dart';

/// The Local model card's one setting in auto mode, the context: the sizes
/// offered with the verdict on the one picked, and for a size too big for
/// this computer the largest that works well or "keep anyway".
class KoboldContextControl extends StatelessWidget {
  const KoboldContextControl({
    super.key,
    required this.facts,
    required this.contextSize,
    required this.pending,
    required this.onPick,
    required this.onApply,
  });

  final KoboldStatusFacts facts;

  /// The context in use.
  final int contextSize;

  /// A size too big for this computer, waiting for "keep anyway".
  final int? pending;

  /// A size was tapped.
  final ValueChanged<int> onPick;

  /// Put this size in use.
  final Future<void> Function(int tokens) onApply;

  @override
  Widget build(BuildContext context) {
    final picked = pending ?? contextSize;
    final verdict = facts.verdicts[picked];
    final words = verdict == null
        ? null
        : koboldContextWords(
            verdict,
            largestGood: facts.largestGood,
            isCurrent: picked == contextSize,
          );
    final kind = verdict?.outcome;
    final tint = switch (kind) {
      KoboldContextOutcome.tooBig => AppColors.alertRedOf(context),
      KoboldContextOutcome.tooSmall => AppColors.porchHoneyOf(context),
      _ => AppColors.journalAccentOf(context),
    };
    final ok =
        kind != KoboldContextOutcome.tooBig &&
        kind != KoboldContextOutcome.tooSmall;
    final best = facts.largestGood;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.insetPanelOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Context: how much chat history the character remembers',
            style: keText(context, size: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          KeChoices<int>(
            key: const ValueKey('local-model-context'),
            values: facts.choices,
            selected: picked,
            expand: false,
            label: koboldTokens,
            onSelected: onPick,
          ),
          if (words != null) ...[
            const SizedBox(height: 8),
            KoboldCardNote(
              key: const ValueKey('local-model-verdict'),
              tint: tint,
              warn: !ok,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${words.title} ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: words.text),
                  ],
                ),
                style: keText(context, size: 14, height: 1.45),
              ),
            ),
          ],
          if (pending case final big?) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (best != null)
                  KeButton(
                    'Use ${koboldTokens(best)} tokens',
                    kind: KeButtonKind.amber,
                    onPressed: () => onApply(best),
                  ),
                KeButton(
                  'Keep ${koboldTokens(big)} anyway…',
                  onPressed: () async {
                    final keep = await askKcpps(
                      context,
                      title: 'Keep ${koboldTokens(big)} tokens?',
                      text: words?.text ?? '',
                      yes: 'Keep it',
                    );
                    if (keep && context.mounted) await onApply(big);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
