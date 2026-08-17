// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/alternate_greetings_slider.dart';
import 'package:front_porch_ai/ui/widgets/avatar_art_style_selector.dart';
import 'package:front_porch_ai/ui/widgets/description_detail_chip_row.dart';
import 'package:front_porch_ai/ui/widgets/first_message_length_dropdown.dart';
import 'package:front_porch_ai/ui/widgets/greeting_tone_selector.dart';
import 'package:front_porch_ai/ui/widgets/persona_selector_dropdown.dart';

/// The "Output Settings" card of the guided creator: persona, greeting tones,
/// first-message length, alternate greetings, art style, description detail,
/// and the auto-generate world lore toggle with depth chips. Extracted from
/// the guided config step to keep that file under the size cap.
class GuidedOutputSettings extends StatelessWidget {
  final CreatorState state;

  const GuidedOutputSettings({super.key, required this.state});

  void _save() {
    state.saveState();
    state.notify();
  }

  Widget _inputLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final guidedAccent = AppColors.resolve(
      context,
      Colors.tealAccent,
      const Color(0xFF0D7377),
    );

    return CreatorSectionCard(
      title: 'Output Settings',
      subtitle: 'Greeting style, art style, lorebook, and detail level.',
      icon: Icons.tune,
      accentColor: guidedAccent,
      children: [
        // Persona selector
        _inputLabel(context, '{{user}} Persona for Greetings'),
        const SizedBox(height: 4),
        Text(
          'Select a persona to tailor greetings, or "None" for public cards.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        PersonaSelectorDropdown(
          selectedPersonaId: state.selectedPersonaId,
          onChanged: (value) {
            state.selectedPersonaId = value ?? '';
            _save();
          },
        ),
        const SizedBox(height: 16),

        // Greeting tones
        _inputLabel(context, 'Greeting Tones'),
        const SizedBox(height: 4),
        GreetingToneSelector(
          selectedTones: state.selectedTones.toList(),
          greetingCount: state.altGreetingCount,
          nsfwEnabled: state.nsfwEnabled,
          accentColor: accent,
          onChanged: (tones) {
            state.selectedTones = tones.toSet();
            _save();
          },
        ),
        const SizedBox(height: 16),

        // Greeting length + alt count
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _inputLabel(context, 'First Message Length'),
                  const SizedBox(height: 8),
                  FirstMessageLengthDropdown(
                    value: state.greetingLength,
                    onChanged: (value) {
                      if (value != null) {
                        state.greetingLength = value;
                        _save();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _inputLabel(context, 'Alternate Greetings'),
                  const SizedBox(height: 8),
                  AlternateGreetingsSlider(
                    value: state.altGreetingCount,
                    accentColor: accent,
                    onChanged: (val) {
                      state.altGreetingCount = val;
                      final maxTones = state.altGreetingCount + 1;
                      while (state.selectedTones.length > maxTones) {
                        state.selectedTones.remove(state.selectedTones.last);
                      }
                      _save();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _inputLabel(context, 'Greeting voice'),
        const SizedBox(height: 4),
        Text(
          'Perspective and tense for the first message, alternates, and example dialogue.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        NarrativeVoiceSelector(
          perspective: state.narrativePerspective,
          tense: state.narrativeTense,
          accentColor: accent,
          onPerspectiveChanged: (v) {
            state.narrativePerspective = v;
            _save();
          },
          onTenseChanged: (v) {
            state.narrativeTense = v;
            _save();
          },
        ),
        const SizedBox(height: 16),

        // Art style
        _inputLabel(context, 'Avatar Art Style'),
        const SizedBox(height: 8),
        AvatarArtStyleSelector(
          selectedStyle: state.artStyle,
          accentColor: accent,
          onChanged: (style) {
            state.artStyle = style;
            _save();
          },
        ),
        const SizedBox(height: 16),

        // Description detail
        _inputLabel(context, 'Description Detail'),
        const SizedBox(height: 8),
        DescriptionDetailChipRow(
          options: CreatorState.generationDetailOptions.keys.toList(),
          selectedDetail: state.generationDetail,
          accentColor: accent,
          onChanged: (label) {
            state.generationDetail = label;
            _save();
          },
        ),
        const SizedBox(height: 16),

        // Lorebook toggle
        Row(
          children: [
            Icon(Icons.menu_book, color: accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Auto-generate World Lore',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: state.generateLorebook,
              activeTrackColor: accent,
              onChanged: (val) {
                state.generateLorebook = val;
                _save();
              },
            ),
          ],
        ),
        if (state.generateLorebook) ...[
          const SizedBox(height: 8),
          _depthChips(context, accent),
        ],
        const SizedBox(height: 16),
        DynamicMacrosToggle(
          value: state.includeDynamicMacros,
          accentColor: accent,
          onChanged: (val) {
            state.includeDynamicMacros = val;
            _save();
          },
        ),
      ],
    );
  }

  Widget _depthChips(BuildContext context, Color accent) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(
          'Depth:',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        Tooltip(
          message:
              'Controls how many consecutive generation steps the Lore Engine processes. '
              'Deep = more expansive lore structure but longer wait time.',
          child: Icon(
            Icons.info_outline,
            size: 14,
            color: AppColors.textTertiary(context),
          ),
        ),
        ...CreatorState.loreDepths.map((depth) {
          final isSelected = state.loreDepth == depth;
          final count = depth == 'Light'
              ? '3-4'
              : depth == 'Deep'
              ? '10-15'
              : '5-8';
          return ChoiceChip(
            label: Text(
              '$depth ($count)',
              style: const TextStyle(fontSize: 11),
            ),
            selected: isSelected,
            onSelected: (_) {
              state.loreDepth = depth;
              _save();
            },
            selectedColor: AppColors.resolve(
              context,
              AppColors.formMasterAccent.withValues(alpha: 0.25),
              AppColors.formMasterAccent.withValues(alpha: 0.12),
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            labelStyle: TextStyle(
              color: isSelected
                  ? AppColors.resolve(context, Colors.white, Colors.black87)
                  : AppColors.textSecondary(context),
            ),
            side: BorderSide(
              color: isSelected ? accent : AppColors.borderOf(context),
            ),
            visualDensity: VisualDensity.compact,
          );
        }),
      ],
    );
  }
}
