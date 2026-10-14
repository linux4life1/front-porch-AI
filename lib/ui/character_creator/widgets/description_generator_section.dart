// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_hint_field.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_input_label.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The magic-wand "Description" generator: a label + generate button (or a
/// progress spinner while running) above a description field that stays locked
/// until generated, with a tap-to-generate overlay. Restored from the
/// pre-refactor automated config step.
class DescriptionGeneratorSection extends StatelessWidget {
  final CreatorState state;
  final Color accent;

  const DescriptionGeneratorSection({
    super.key,
    required this.state,
    required this.accent,
  });

  void _generate(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    state.randomizeConcept(llmProvider: llmProvider, storage: storage);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CreatorInputLabel('Description', required: true),
            const Spacer(),
            if (state.isRandomizing)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: state.conceptGenProgress > 0
                            ? state.conceptGenProgress
                            : null,
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                    if (state.conceptGenProgress > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${(state.conceptGenProgress * 100).toInt()}%',
                        style: TextStyle(color: accent, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              )
            else
              Tooltip(
                message: 'Generate a description using all your selections',
                child: IconButton(
                  icon: Icon(Icons.auto_fix_high, color: accent, size: 20),
                  onPressed: () => _generate(context),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            CreatorHintField(
              state: state,
              controller: state.conceptController,
              hint: state.conceptGenerated
                  ? 'Edit the generated description...'
                  : 'Tap ✨ above to generate a description from your selections',
              maxLines: null,
              minLines: 4,
              readOnly: !state.conceptGenerated,
              enabled: state.conceptGenerated,
            ),
            if (!state.conceptGenerated && !state.isRandomizing)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _generate(context),
                  child: Container(
                    decoration: BoxDecoration(
                      color: StudioColors.raiseOf(
                        context,
                      ).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withValues(alpha: 0.2)),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_fix_high, color: accent, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Tap to generate description',
                            style: TextStyle(color: accent, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
