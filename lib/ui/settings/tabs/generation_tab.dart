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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Generation-settings tab extracted from settings_page (Stage 5, remaining
/// tabs). Pure lift of _buildGenerationTab: reasoning, sampling parameters,
/// output limits, smooth-output display buffer, stop sequences, and (local
/// backends only) banned phrases. Reads storage/LLM state via Provider; the
/// banned-phrases controller is the only shared state, passed via ctor.
/// AppColors exclusive, warm-porch accents.
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Reasoning (thinking models — local KoboldCpp & remote) ─────
          const SectionHeader('Thinking'),
          const SizedBox(height: 8),
          ThinkingSettingsBlock(
            enabled: storage.reasoningEnabled,
            onEnabledChanged: storage.setReasoningEnabled,
            effort: storage.reasoningEffort,
            onEffortChanged: storage.setReasoningEffort,
            modelId: storage.remoteModelName,
          ),
          const SizedBox(height: 24),

          // ── Generation Parameters ──────────────────────────────────────
          const SectionHeader('Generation Parameters'),
          const SizedBox(height: 8),
          SliderSetting(
            label: 'Temperature',
            value: storage.generationSettings.temperature,
            min: 0.0,
            max: 2.0,
            onChanged: (val) => storage.setTemperature(val),
            divisions: 20,
            showInput: true,
            decimalPlaces: 1,
          ),
          SliderSetting(
            label: 'Min-P',
            value: storage.generationSettings.minP,
            min: 0.0,
            max: 1.0,
            onChanged: (val) => storage.setMinP(val),
            divisions: 100,
            showInput: true,
            decimalPlaces: 2,
          ),
          SliderSetting(
            label: 'Top-P',
            value: storage.topP,
            min: 0.1,
            max: 1.0,
            onChanged: (val) => storage.setTopP(val),
            divisions: 90,
            showInput: true,
            decimalPlaces: 2,
          ),
          SliderSetting(
            label: 'Top-K',
            value: storage.topK.toDouble(),
            min: 0,
            max: 200,
            onChanged: (val) => storage.setTopK(val.toInt()),
            divisions: 200,
            showInput: true,
            isInteger: true,
          ),
          SliderSetting(
            label: 'Repeat Penalty',
            value: storage.generationSettings.repeatPenalty,
            min: 1.0,
            max: 3.0,
            onChanged: (val) => storage.setRepeatPenalty(val),
            divisions: 200,
            showInput: true,
            decimalPlaces: 2,
          ),
          SliderSetting(
            label: 'Repeat Penalty Tokens',
            value: storage.repeatPenaltyTokens.toDouble(),
            min: 0,
            max: 2048,
            onChanged: (val) => storage.setRepeatPenaltyTokens(val.toInt()),
            divisions: 256,
            showInput: true,
            isInteger: true,
          ),
          // XTC and DRY are llama.cpp samplers — only the KoboldCpp
          // backend honors them, so they are hidden (not just annotated)
          // on oMLX/remote (maintainer request 2026-07-15).
          if (llmProvider.activeBackend == BackendType.kobold) ...[
            SliderSetting(
              label: 'XTC Threshold',
              value: storage.xtcThreshold,
              min: 0.0,
              max: 0.5,
              onChanged: (val) => storage.setXtcThreshold(val),
              divisions: 50,
              showInput: true,
              decimalPlaces: 2,
            ),
            SliderSetting(
              label: 'XTC Probability',
              value: storage.xtcProbability,
              min: 0.0,
              max: 1.0,
              onChanged: (val) => storage.setXtcProbability(val),
              divisions: 20,
              showInput: true,
              decimalPlaces: 2,
            ),
            SliderSetting(
              label: 'DRY Strength',
              value: storage.dryMultiplier,
              min: 0.0,
              max: 3.0,
              onChanged: (val) => storage.setDryMultiplier(val),
              divisions: 60,
              showInput: true,
              decimalPlaces: 2,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Dynamic Temperature',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const Spacer(),
              Switch(
                value: storage.dynamicTempEnabled,
                onChanged: (val) => storage.setDynamicTempEnabled(val),
                activeTrackColor: accent,
              ),
            ],
          ),
          if (storage.dynamicTempEnabled)
            SliderSetting(
              label: 'Dynatemp Range',
              value: storage.dynamicTempRange,
              min: 0.0,
              max: 2.0,
              onChanged: (val) => storage.setDynamicTempRange(val),
              divisions: 20,
              showInput: true,
              decimalPlaces: 1,
            ),
          const SizedBox(height: 24),

          // ── Output Limits ──────────────────────────────────────────────
          const SectionHeader('Output Limits'),
          const SizedBox(height: 8),
          SliderSetting(
            label: 'Max Output Tokens',
            value: storage.maxLength.toDouble(),
            min: 16,
            max: 16384,
            onChanged: (val) => storage.setMaxLength(val.toInt()),
            showInput: true,
            isInteger: true,
          ),
          SliderSetting(
            label: 'Min Output Tokens',
            value: storage.minLength.toDouble(),
            min: 0,
            max: 512,
            onChanged: (val) => storage.setMinLength(val.toInt()),
            divisions: 512,
            showInput: true,
            isInteger: true,
          ),
          // Context size — wider range for remote backends.
          SliderSetting(
            label: 'Context Size',
            value: storage.contextSize.toDouble().clamp(
              512,
              isRemote ? 500000.0 : 131072.0,
            ),
            min: 512,
            max: isRemote ? 500000.0 : 131072.0,
            onChanged: (val) => storage.setContextSize(val.toInt()),
            divisions: isRemote ? null : ((131072 - 512) ~/ 512),
            showInput: true,
            isInteger: true,
          ),
          const SizedBox(height: 24),

          // ── Model transport ────────────────────────────────────────────
          const SectionHeader('Model transport'),
          const SizedBox(height: 8),
          Text(
            'How the engine evaluations (Realism, Journal, Growth Rings) '
            'talk to the model.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Native tool calling',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const Spacer(),
              Switch(
                value: !storage.preferTextEvals,
                onChanged: (val) => storage.setPreferTextEvals(!val),
                activeTrackColor: accent,
              ),
            ],
          ),
          Text(
            'When on, Realism, Journal and Growth use native tool calls if '
            'this model supports them — cleaner structured results, and on '
            'the common local templates no slower than the JSON floor. When '
            'off, every eval uses the JSON/XML floor even if the model can '
            'speak tools. The sidebar pill still shows whether the model '
            'can. Default on.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 24),

          // ── Display Output ─────────────────────────────────────────────
          const SectionHeader('Display Output'),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Smooth Output Buffer',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const Spacer(),
              Switch(
                value: storage.displayBufferEnabled,
                onChanged: (val) => storage.setDisplayBufferEnabled(val),
                activeTrackColor: accent,
              ),
            ],
          ),
          if (storage.displayBufferEnabled) ...[
            SliderSetting(
              label: 'Target Display Speed (t/s)',
              value: storage.targetDisplayTps,
              min: 5.0,
              max: 60.0,
              onChanged: (val) => storage.setTargetDisplayTps(val),
              divisions: 55,
            ),
            SliderSetting(
              label: 'Buffer Duration (seconds)',
              value: storage.bufferDurationSeconds,
              min: 1.0,
              max: 10.0,
              onChanged: (val) => storage.setBufferDurationSeconds(val),
              divisions: 9,
            ),
          ],
          const SizedBox(height: 24),

          // ── Stop Sequences ─────────────────────────────────────────────
          const SectionHeader('Stop Sequences'),
          const SizedBox(height: 8),
          StopSequenceList(
            sequences: storage.stopSequences,
            onSequencesChanged: (newList) => storage.setStopSequences(newList),
          ),
          const SizedBox(height: 24),

          // ── Banned Phrases (KoboldCpp only) ────────────────────────────
          if (!isRemote) ...[
            const SectionHeader('Banned Phrases'),
            BannedPhrasesEditor(
              controller: widget.bannedPhrasesController,
              onChanged: (phrases) => storage.setBannedPhrases(phrases),
              phraseCount: storage.bannedPhrases.length,
            ),
          ],

          const SizedBox(height: 24),

          // ── Output Sanitizer ───────────────────────────────────────────
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
                style: TextStyle(color: AppColors.textSecondary(context)),
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
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
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
                    // Enabling is a destructive, global commitment (every
                    // chat opened while ON gets its saved AI messages
                    // rewritten on its next save) — confirm before arming.
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

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
