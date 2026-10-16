// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/mode_card.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/template_picker_card.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Step 1: Mode selection (Automated / Guided / Quick), under the
/// `Start from a template` picker.
class ModeSelectStep extends StatefulWidget {
  final CreatorState state;

  const ModeSelectStep({super.key, required this.state});

  @override
  State<ModeSelectStep> createState() => _ModeSelectStepState();
}

class _ModeSelectStepState extends State<ModeSelectStep> {
  CreatorState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // Templates saved since the step last showed (on the phone too). With
    // no library yet this reads nothing and the built-ins show as they are.
    state.templates.refresh();
  }

  void _select(CreatorMode mode) {
    state.creatorMode = mode;
    state.saveState();
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    // One accent across the creator (docs/design/creator-ui-spec.md).
    final amber = StudioColors.amberOf(context);

    return Align(
      alignment: Alignment.topCenter,
      key: const ValueKey('mode-select'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How do you want to create?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.inkOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the creation mode that fits your workflow.',
                style: TextStyle(
                  fontSize: 14,
                  color: StudioColors.mutedOf(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              TemplatePickerCard(state: state),
              const SizedBox(height: 16),

              // Three columns, as tall as each other (the sketch's grid).
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Expanded(
                      child: ModeCard(
                        title: 'Automated Creator',
                        subtitle:
                            'Pick traits from bubbles, let AI fill the gaps',
                        description:
                            'Best when you want to explore and discover. '
                            'Select from archetypes, appearance options, backstory presets, '
                            'and personality keywords. The AI handles the rest.',
                        features: const [
                          'Archetype presets',
                          'Bubble selectors for every trait',
                          'AI generates description from selections',
                        ],
                        icon: Icons.auto_awesome,
                        accentColor: amber,
                        isSelected: state.creatorMode == CreatorMode.automated,
                        onTap: () => _select(CreatorMode.automated),
                      ),
                    ),
                    Expanded(
                      child: ModeCard(
                        title: 'Guided Creator',
                        subtitle:
                            'Write your vision, AI helps you flesh it out',
                        description:
                            'Best when you already have a character in mind but need help '
                            'getting it on paper. Describe your idea in your own words — '
                            'guided prompts and suggestions help you express your vision.',
                        features: const [
                          'Free-form text with guided prompts',
                          'Suggestion chips for inspiration',
                          '"Help me expand this" AI assist',
                        ],
                        icon: Icons.edit_note,
                        accentColor: amber,
                        isSelected: state.creatorMode == CreatorMode.guided,
                        onTap: () => _select(CreatorMode.guided),
                      ),
                    ),
                    Expanded(
                      child: ModeCard(
                        title: 'Quick Create',
                        subtitle:
                            'Name it, describe it, done — AI does the rest',
                        description:
                            'Fastest path to a finished character. '
                            'Just give a name and a one-liner. The full AI pipeline '
                            '(interview, lorebook, greetings) runs automatically.',
                        features: const [
                          'Name + concept only',
                          'NSFW toggle',
                          'Full pipeline in ~2 min',
                        ],
                        icon: Icons.bolt,
                        accentColor: amber,
                        isSelected: state.creatorMode == CreatorMode.quick,
                        onTap: () => _select(CreatorMode.quick),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
