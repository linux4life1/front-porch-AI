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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Settings → Generation: organized into 4 distinct functional categories:
/// 1. Preset & Reasoning (model intelligence, presets, and thinking effort)
/// 2. Generation Parameters (dual-column studio rack with danger zones)
/// 3. Output Limits (context window size & max output token reserve)
/// 4. Output Pipeline & Diagnostics (stops, banned phrases, sanitizer,
///    and advanced Model transport & display buffer options).
class GenerationTab extends StatefulWidget {
  const GenerationTab({super.key, required this.bannedPhrasesController});

  final TextEditingController bannedPhrasesController;

  @override
  State<GenerationTab> createState() => _GenerationTabState();
}

class _GenerationTabState extends State<GenerationTab> {
  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final isRemote = !llmProvider.isLocal;
    final accent = AppColors.porchAmberOf(context);
    // Only what this backend's requests carry; a hidden value is kept.
    final knobs = samplerKnobsFor(
      llmProvider.activeBackend,
      remoteApiUrl: storage.backendSettings.remoteApiUrl,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Category 1: Preset & Reasoning ─────────────────────────────
          const GenerationPresetBar(),
          const SizedBox(height: 16),
          GenerationSectionCard(
            title: 'Thinking',
            children: [
              ThinkingSettingsBlock(
                showHeading: false,
                enabled: storage.backendSettings.reasoningEnabled,
                onEnabledChanged: storage.backendSettings.setReasoningEnabled,
                effort: storage.backendSettings.reasoningEffort,
                onEffortChanged: storage.backendSettings.setReasoningEffort,
                modelId: storage.backendSettings.remoteModelName,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Category 2: Generation Parameters (Studio Console) ─────────
          GenerationSectionCard(
            title: 'Generation Parameters',
            children: [
              GenerationSamplerSliders(
                storage: storage,
                knobs: knobs,
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Category 3: Output Limits & Context Budgets ────────────────
          GenerationSectionCard(
            title: 'Output Limits & Context Budgets',
            children: [
              RecommendedSamplersBuilder(
                storage: storage,
                builder: (context, rec) => SliderSetting(
                  label: 'Max Output Tokens',
                  value: storage.generationSettings.maxLength.toDouble(),
                  min: 64,
                  max: 65536,
                  defaultVal: 2048,
                  dangerMin: 128,
                  divisions: (65536 - 64) ~/ 64,
                  isInteger: true,
                  studioStyle: true,
                  reset: resetTargetFor(rec, (v) => v.maxLength),
                  onChanged: (val) =>
                      storage.generationSettings.setMaxLength(val.toInt()),
                  tooltip:
                      'Maximum tokens generated in a single reply. 2,048 is standard; higher values allow deep reasoning chains.',
                ),
              ),
              const SizedBox(height: 10),
              // Context size — wider range for remote backends.
              PresetContextLock(
                locked: storage.backendSettings.presetOwnsContext,
                child: SliderSetting(
                  label: 'Context Size',
                  value: storage.backendSettings.contextSize.toDouble(),
                  min: 512,
                  max: isRemote ? 500000.0 : 131072.0,
                  defaultVal: 16384,
                  divisions: isRemote ? null : ((131072 - 512) ~/ 512),
                  isInteger: true,
                  studioStyle: true,
                  onChanged: (val) =>
                      storage.backendSettings.setContextSize(val.toInt()),
                  tooltip:
                      'Total working memory buffer for character, chat history, and system instructions.',
                ),
              ),
              ContextSizeWarnings(
                contextSize: storage.backendSettings.contextSize,
                maxOutput: storage.generationSettings.maxLength,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Category 4: Output Pipeline & Diagnostics ──────────────────
          GenerationSectionCard(
            title: 'Output Pipeline & Rules',
            children: [
              const SectionHeader('Stop Sequences'),
              const SizedBox(height: 8),
              StopSequenceList(
                sequences: storage.generationSettings.stopSequences,
                onSequencesChanged: (newList) =>
                    storage.generationSettings.setStopSequences(newList),
              ),
              const SizedBox(height: 20),

              // Banned Phrases (KoboldCpp only)
              if (knobs.contains(SamplerKnob.bannedPhrases)) ...[
                const SectionHeader('Banned Phrases'),
                const SizedBox(height: 8),
                BannedPhrasesEditor(
                  controller: widget.bannedPhrasesController,
                  onChanged: (phrases) =>
                      storage.realismSettings.setBannedPhrases(phrases),
                  phraseCount: storage.realismSettings.bannedPhrases.length,
                ),
                const SizedBox(height: 20),
              ],

              // Output Sanitizer
              const SectionHeader('Output Sanitizer'),
              const SizedBox(height: 4),
              Text(
                'Replace specific character sequences in model output before '
                'saving to chat history.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Enable Output Sanitizer',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  const Spacer(),
                  Switch(
                    value: storage.generationSettings.outputSanitizerEnabled,
                    onChanged: (val) =>
                        storage.generationSettings.setOutputSanitizerEnabled(val),
                    activeTrackColor: accent,
                  ),
                ],
              ),
              if (storage.generationSettings.outputSanitizerEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sanitise Existing History',
                            style: TextStyle(color: AppColors.textPrimary(context)),
                          ),
                          Text(
                            'When enabled, opening a chat will permanently '
                            'apply the rules below to the AI messages already '
                            'saved in that chat\'s history — your own messages '
                            'are never touched. This cannot be undone.',
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: storage.generationSettings.sanitiseExistingHistory,
                      onChanged: (val) async {
                        if (val) {
                          final confirmed = await showWarmDialog<bool>(
                            context,
                            title: 'Rewrite saved chat history?',
                            icon: Icons.warning_amber_rounded,
                            destructive: true,
                            content: const WarmDialogText(
                              'Every chat you open while this is on will have '
                              'the rules applied to its saved AI messages — '
                              'permanently, on that chat\'s next save. Your own '
                              'messages are never touched. This cannot be '
                              'undone (automatic local backups are your safety '
                              'net — Settings → General).',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Rewrite on open'),
                              ),
                            ],
                          );
                          if (confirmed != true) return;
                        }
                        storage.generationSettings.setSanitiseExistingHistory(val);
                        if (val && mounted) {
                          final chatService = Provider.of<ChatService>(
                            context,
                            listen: false,
                          );
                          await chatService.reloadCurrentSession();
                        }
                      },
                      activeTrackColor: accent,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutputSanitizerRuleEditor(
                  rules: storage.generationSettings.outputSanitizerRules,
                  onRulesChanged: (newRules) =>
                      storage.generationSettings.setOutputSanitizerRules(newRules),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
          const SizedBox(height: 16),
          // ── Model transport & Display Output (Advanced Engine Options) ─
          GenerationSectionCard(
            title: 'Engine & Display Options',
            children: [
              GenerationAdvancedSection(storage: storage, accent: accent),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
