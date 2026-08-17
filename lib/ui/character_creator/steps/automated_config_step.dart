// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/alternate_greetings_slider.dart';
import 'package:front_porch_ai/ui/widgets/avatar_art_style_selector.dart';
import 'package:front_porch_ai/ui/widgets/age_gender_row.dart';
import 'package:front_porch_ai/ui/widgets/character_name_input.dart';
import 'package:front_porch_ai/ui/widgets/description_detail_chip_row.dart';
import 'package:front_porch_ai/ui/widgets/first_message_length_dropdown.dart';
import 'package:front_porch_ai/ui/widgets/greeting_tone_selector.dart';
import 'package:front_porch_ai/ui/widgets/nsfw_toggle.dart';
import 'package:front_porch_ai/ui/widgets/persona_selector_dropdown.dart';

/// Automated (structured) config step. Restores the pre-refactor
/// `_buildConfigStep` as a guided set of accent-themed cards and chip rows that
/// feed the AI a rich character brief. Loose fields are card-grouped to match
/// the Guided creator's `CreatorSectionCard` look. Navigation + generation are
/// owned by the wizard shell.
class AutomatedConfigStep extends StatelessWidget {
  final CreatorState state;

  const AutomatedConfigStep({super.key, required this.state});

  void _save() {
    state.saveState();
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.resolve(
      context,
      Colors.amberAccent,
      const Color(0xFFB45309),
    );
    final pink = AppColors.resolve(
      context,
      Colors.pinkAccent,
      const Color(0xFF9D174D),
    );
    return Center(
      key: const ValueKey('automated-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bring Your Character to Life',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Give us a name and a concept — the AI will do the rest. '
                'It will generate a complete character card with personality, '
                'backstory, dialogue examples, and a custom avatar.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              NsfwToggle(
                value: state.nsfwEnabled,
                accentColor: pink,
                subtitle: 'Unlock spicy appearance & relationship options',
                onChanged: (val) {
                  state.nsfwEnabled = val;
                  _save();
                },
              ),
              const SizedBox(height: 16),

              ArchetypePresetCard(state: state, accent: amber),
              const SizedBox(height: 16),

              // ── The Basics ──
              CreatorSectionCard(
                title: 'The Basics',
                subtitle: 'Name, age, gender, and personality keywords.',
                icon: Icons.badge_outlined,
                accentColor: amber,
                initiallyExpanded: true,
                children: [
                  CharacterNameInput(
                    controller: state.nameController,
                    onRandomize: () {
                      state.randomizeName(
                        llmProvider: Provider.of<LLMProvider>(
                          context,
                          listen: false,
                        ),
                        storage: Provider.of<StorageService>(
                          context,
                          listen: false,
                        ),
                      );
                    },
                    tooltip: 'Generate a random character name',
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
                  AgeGenderRow(
                    ageController: state.ageController,
                    genderController: state.sexController,
                    onChanged: _save,
                  ),
                  const SizedBox(height: 16),
                  const CreatorInputLabel('Personality Keywords'),
                  const SizedBox(height: 8),
                  CreatorHintField(
                    state: state,
                    controller: state.keywordsController,
                    hint: 'e.g. witty, secretive, bookish, brave, loyal...',
                  ),
                ],
              ),

              AppearanceBuilderCard(state: state, accent: amber),
              const SizedBox(height: 16),

              // ── Relationship ──
              CreatorSectionCard(
                title: 'Relationship to {{user}}',
                subtitle: 'How do they know {{user}}?',
                icon: Icons.favorite_border,
                accentColor: amber,
                initiallyExpanded: true,
                children: [
                  RelationshipSelectSection(state: state, accent: amber),
                ],
              ),

              if (state.nsfwEnabled) ...[
                SexualTraitsCard(state: state, accent: pink),
                const SizedBox(height: 16),
              ],

              BackstoryCard(state: state, accent: amber),
              const SizedBox(height: 16),

              // ── Description ──
              CreatorSectionCard(
                title: 'Description',
                subtitle: 'Detail level + the AI-generated description.',
                icon: Icons.auto_fix_high,
                accentColor: amber,
                initiallyExpanded: true,
                children: [
                  const CreatorInputLabel('Description Detail'),
                  const SizedBox(height: 4),
                  DescriptionDetailChipRow(
                    options: CreatorOptions.generationDetailOptions.keys
                        .toList(),
                    selectedDetail: state.generationDetail,
                    accentColor: amber,
                    subtitle:
                        'Controls how detailed the character description '
                        'will be',
                    onChanged: (label) {
                      state.generationDetail = label;
                      _save();
                    },
                  ),
                  const SizedBox(height: 16),
                  DescriptionGeneratorSection(state: state, accent: amber),
                ],
              ),

              LorebookGenerationCard(state: state, accent: amber),
              const SizedBox(height: 16),

              // ── Greetings & Output ──
              CreatorSectionCard(
                title: 'Greetings & Output',
                subtitle:
                    'Persona, greeting tones, message length, and avatar art.',
                icon: Icons.tune,
                accentColor: amber,
                initiallyExpanded: true,
                children: [
                  const CreatorInputLabel('{{user}} Persona for Greetings'),
                  const SizedBox(height: 4),
                  Text(
                    'Select a persona to tailor greetings, or "None" for '
                    'public cards.',
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
                  const SizedBox(height: 24),
                  const CreatorInputLabel('Greeting Tones'),
                  const SizedBox(height: 4),
                  GreetingToneSelector(
                    selectedTones: state.selectedTones.toList(),
                    greetingCount: state.altGreetingCount,
                    nsfwEnabled: state.nsfwEnabled,
                    accentColor: amber,
                    subtitle: state.altGreetingCount == 0
                        ? 'Tone for the first message.'
                        : 'Select up to ${state.altGreetingCount + 1} — '
                              'one per greeting (first message + '
                              '${state.altGreetingCount} '
                              'alternate${state.altGreetingCount == 1 ? '' : 's'}).',
                    onChanged: (tones) {
                      state.selectedTones = tones.toSet();
                      _save();
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CreatorInputLabel('First Message Length'),
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
                            const CreatorInputLabel('Alternate Greetings'),
                            const SizedBox(height: 8),
                            AlternateGreetingsSlider(
                              value: state.altGreetingCount,
                              accentColor: amber,
                              onChanged: (val) {
                                state.altGreetingCount = val;
                                final maxTones = state.altGreetingCount + 1;
                                while (state.selectedTones.length > maxTones) {
                                  state.selectedTones.remove(
                                    state.selectedTones.last,
                                  );
                                }
                                _save();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const CreatorInputLabel('Greeting voice'),
                  const SizedBox(height: 4),
                  Text(
                    'Perspective and tense for the first message, alternates, '
                    'and example dialogue.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  NarrativeVoiceSelector(
                    perspective: state.narrativePerspective,
                    tense: state.narrativeTense,
                    accentColor: amber,
                    onPerspectiveChanged: (v) {
                      state.narrativePerspective = v;
                      _save();
                    },
                    onTenseChanged: (v) {
                      state.narrativeTense = v;
                      _save();
                    },
                  ),
                  const SizedBox(height: 24),
                  const CreatorInputLabel('Avatar Art Style'),
                  const SizedBox(height: 8),
                  AvatarArtStyleSelector(
                    selectedStyle: state.artStyle,
                    accentColor: amber,
                    onChanged: (style) {
                      state.artStyle = style;
                      _save();
                    },
                  ),
                ],
              ),

              // ── World Lore ──
              CreatorSectionCard(
                title: 'World Lore',
                subtitle: 'Optional setting and lore notes for the AI.',
                icon: Icons.menu_book,
                accentColor: amber,
                initiallyExpanded: true,
                children: [LoreInputSection(state: state, accentColor: amber)],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
