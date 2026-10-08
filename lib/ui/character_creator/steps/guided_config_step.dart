// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/steps/guided_output_settings.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/age_gender_row.dart';
import 'package:front_porch_ai/ui/widgets/character_name_input.dart';
import 'package:front_porch_ai/ui/widgets/nsfw_toggle.dart';

/// Guided creator config step. Faithfully restores the pre-refactor
/// `_buildGuidedConfigStep` UI: header, basic info, collapsible appearance /
/// personality / backstory / relationship cards, lore input, gated intimate
/// details, the AI "Character Vision" panel, and the output settings card.
/// Navigation buttons are owned by the wizard shell — not built here.
class GuidedConfigStep extends StatelessWidget {
  final CreatorState state;

  const GuidedConfigStep({super.key, required this.state});

  void _save() {
    state.saveState();
    state.notify();
  }

  /// Typing: redraw at once (the vision panel reads the name), save on pause.
  void _saveSoon() {
    state.scheduleSave();
    state.notify();
  }

  /// Section heading used for the (non-collapsible) basic-info block.
  Widget _sectionHeading(BuildContext context, String title, String helper) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary(context),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final guidedAccent = AppColors.resolve(
      context,
      Colors.tealAccent,
      const Color(0xFF0D7377),
    );
    final nsfwAccent = AppColors.resolve(
      context,
      Colors.pinkAccent,
      const Color(0xFF9D174D),
    );

    return Center(
      key: const ValueKey('guided-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  Icon(Icons.edit_note, color: guidedAccent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guided Character Creator',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Describe your character — we'll help you flesh them out.",
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Basic info ──
              _sectionHeading(
                context,
                "What's your character like?",
                "Don't worry about perfect writing — a few sentences, a scene, bullet points, whatever comes naturally.",
              ),
              const SizedBox(height: 16),
              CharacterNameInput(
                controller: state.nameController,
                tooltip: 'Generate a random name',
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
                onChanged: (_) => _saveSoon(),
              ),
              const SizedBox(height: 16),
              AgeGenderRow(
                ageController: state.ageController,
                genderController: state.sexController,
                genderLabel: 'Sex',
                onChanged: _saveSoon,
              ),
              const SizedBox(height: 4),

              // ── Appearance ──
              CreatorSectionCard(
                title: 'Appearance',
                subtitle: 'Already described their look above? Skip this.',
                icon: Icons.person_outline,
                accentColor: guidedAccent,
                children: [
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Build / Body Type',
                    controller: state.guidedAppearanceController,
                    hint: "Or describe: 'tall and lanky with long legs'",
                    suggestions: CreatorOptions.guidedBuildSuggestions,
                    maxLines: 2,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Hair',
                    controller: state.guidedHairController,
                    hint: "e.g. 'waist-length silver hair, usually messy'",
                    suggestions: CreatorOptions.guidedHairSuggestions,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Distinguishing Features',
                    controller: state.guidedFeaturesController,
                    hint:
                        "e.g. 'a jagged scar across their left eye, pointed elf ears'",
                    suggestions: CreatorOptions.guidedFeatureSuggestions,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Race / Species',
                    controller: state.guidedRaceController,
                    hint: "e.g. 'half-dragon shapeshifter'",
                    suggestions: CreatorOptions.guidedRaceSuggestions,
                    onChanged: _saveSoon,
                  ),
                ],
              ),

              // ── Personality & Vibe ──
              CreatorSectionCard(
                title: 'Personality & Vibe',
                subtitle: "What's it like to spend time with them?",
                icon: Icons.psychology,
                accentColor: guidedAccent,
                children: [
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Personality',
                    controller: state.guidedPersonalityController,
                    hint:
                        "What are they like? e.g. 'Sharp wit, never shows vulnerability, but secretly writes poetry'",
                    suggestions: CreatorOptions.guidedPersonalitySuggestions,
                    maxLines: 3,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'How They Talk',
                    controller: state.guidedSpeechController,
                    hint:
                        "e.g. 'Formal and old-fashioned' or 'Lots of slang, drops F-bombs'",
                    suggestions: CreatorOptions.guidedSpeechSuggestions,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Secret / Hidden Depth',
                    controller: state.guidedSecretController,
                    hint:
                        "What's beneath the surface? e.g. 'Seems cold but is terrified of being alone'",
                    onChanged: _saveSoon,
                  ),
                ],
              ),

              // ── Backstory ──
              CreatorSectionCard(
                title: 'Backstory',
                subtitle:
                    'Even a sentence helps the AI build a richer history.',
                icon: Icons.auto_stories,
                accentColor: guidedAccent,
                children: [
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Origin / Background',
                    controller: state.guidedOriginController,
                    hint:
                        "e.g. 'Grew up on the streets after their parents disappeared'",
                    suggestions: CreatorOptions.guidedOriginSuggestions,
                    maxLines: 2,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Setting / Era',
                    controller: state.guidedSettingController,
                    hint:
                        "When and where? e.g. 'Cyberpunk megacity' or 'Medieval fantasy kingdom'",
                    suggestions: CreatorOptions.guidedSettingSuggestions,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Tone',
                    controller: state.guidedToneController,
                    hint:
                        "Overall feel? e.g. 'Dark and gritty but with moments of warmth'",
                    suggestions: CreatorOptions.guidedToneSuggestions,
                    onChanged: _saveSoon,
                  ),
                ],
              ),

              // ── Relationship ──
              CreatorSectionCard(
                title: 'Relationship to {{user}}',
                subtitle: 'How do they know {{user}}?',
                icon: Icons.favorite_border,
                accentColor: guidedAccent,
                children: [
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Dynamic',
                    controller: state.guidedRelDynamicController,
                    hint:
                        "e.g. 'Coworkers who secretly like each other' or 'They're my bodyguard'",
                    suggestions: CreatorOptions.guidedRelSuggestions,
                    maxLines: 2,
                    onChanged: _saveSoon,
                  ),
                  SuggestionChipField(
                    accent: guidedAccent,
                    label: 'Opening Scenario',
                    controller: state.guidedRelScenarioController,
                    hint:
                        "Where does the story start? e.g. 'First day at a new school'",
                    onChanged: _saveSoon,
                  ),
                ],
              ),

              // ── Lore input ──
              LoreInputSection(state: state, accentColor: guidedAccent),
              const SizedBox(height: 32),

              // ── NSFW toggle + gated intimate details ──
              NsfwToggle(
                value: state.nsfwEnabled,
                accentColor: nsfwAccent,
                subtitle: 'Unlock intimate character details',
                onChanged: (val) {
                  state.nsfwEnabled = val;
                  _save();
                },
              ),
              if (state.nsfwEnabled)
                CreatorSectionCard(
                  title: 'Intimate Details',
                  subtitle: 'Guided prompts for romantic and sexual traits.',
                  icon: Icons.local_fire_department,
                  accentColor: nsfwAccent,
                  children: [
                    SuggestionChipField(
                      accent: guidedAccent,
                      label: 'Body (intimate details)',
                      controller: state.guidedNsfwBodyController,
                      hint:
                          "Describe specifics if you want: 'modest chest, wide hips, thick thighs'",
                      suggestions: CreatorOptions.guidedNsfwBodySuggestions,
                      isNsfw: true,
                      onChanged: _saveSoon,
                    ),
                    SuggestionChipField(
                      accent: guidedAccent,
                      label: 'Experience Level',
                      controller: state.guidedNsfwExpController,
                      hint:
                          "How experienced are they? e.g. 'First time, nervous but eager'",
                      suggestions: CreatorOptions.guidedNsfwExpSuggestions,
                      isNsfw: true,
                      onChanged: _saveSoon,
                    ),
                    SuggestionChipField(
                      accent: guidedAccent,
                      label: 'Dominance',
                      controller: state.guidedNsfwDomController,
                      hint:
                          "Who takes the lead? e.g. 'Dominant in public, submissive behind closed doors'",
                      suggestions: CreatorOptions.guidedNsfwDomSuggestions,
                      isNsfw: true,
                      onChanged: _saveSoon,
                    ),
                    SuggestionChipField(
                      accent: guidedAccent,
                      label: 'Turn-ons & Kinks',
                      controller: state.guidedNsfwKinksController,
                      hint:
                          "What are they into? e.g. 'Loves being praised, goes weak when you grab their hair'",
                      suggestions: CreatorOptions.guidedNsfwKinkSuggestions,
                      maxLines: 2,
                      isNsfw: true,
                      onChanged: _saveSoon,
                    ),
                    SuggestionChipField(
                      accent: guidedAccent,
                      label: 'Clothing / Aesthetic',
                      controller: state.guidedNsfwClothingController,
                      hint:
                          "What do they wear? e.g. 'Always wears thigh-highs and an oversized shirt at home'",
                      suggestions: CreatorOptions.guidedNsfwClothingSuggestions,
                      isNsfw: true,
                      onChanged: _saveSoon,
                    ),
                    SuggestionChipField(
                      accent: guidedAccent,
                      label: 'Sexual Personality',
                      controller: state.guidedNsfwPersonalityController,
                      hint:
                          "How do they act during intimacy? e.g. 'Giggly and playful, hides their face when embarrassed'",
                      maxLines: 2,
                      isNsfw: true,
                      onChanged: _saveSoon,
                    ),
                  ],
                ),

              // ── Character Vision panel ──
              const SizedBox(height: 8),
              GuidedVisionPanel(state: state),
              const SizedBox(height: 16),

              // ── Output settings ──
              GuidedOutputSettings(state: state),

              const SizedBox(height: 24),

              // ── Validation hint ──
              if (state.guidedVisionController.text.trim().isNotEmpty &&
                  state.guidedVisionController.text.trim().length < 20)
                _validationTip(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _validationTip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          context,
          Colors.amber.withValues(alpha: 0.15),
          Colors.amber.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.resolve(
            context,
            Colors.amber.withValues(alpha: 0.4),
            Colors.amber.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline,
            color: Colors.amberAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Tip: The more detail you provide, the better the AI can capture your vision.',
              style: TextStyle(color: Colors.amberAccent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
