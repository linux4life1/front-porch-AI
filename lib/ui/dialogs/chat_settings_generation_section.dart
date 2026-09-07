import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

class ChatSettingsGenerationSection extends StatelessWidget {
  const ChatSettingsGenerationSection({
    super.key,
    required this.gen,
    required this.storage,
    required this.llmProvider,
    required this.isRemote,
    required this.onChanged,
    this.hideOutputTokenLimits = false,
  });

  final ChatGenerationSettings gen;
  final StorageService storage;
  final LLMProvider llmProvider;
  final bool isRemote;
  final VoidCallback onChanged;

  /// Waifu Coder fills the remaining context window. Chat Max/Min Output
  /// Tokens would cut a tool call mid-file.
  final bool hideOutputTokenLimits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Generation',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.formMasterAccent,
          ),
        ),
        const SizedBox(height: 8),
        SliderWithInput(
          label: 'Temperature',
          value: gen.resolveTemperature(storage),
          min: 0.0,
          max: 2.0,
          divisions: 20,
          tooltip:
              'Controls randomness. Low = predictable and focused. High = creative and surprising. 0.7 is a good default.',
          context: context,
          onChanged: (val) {
            gen.temperature = val;
            onChanged();
          },
        ),
        SliderWithInput(
          label: 'Min-P',
          value: gen.resolveMinP(storage),
          min: 0.0,
          max: 1.0,
          divisions: 100,
          tooltip:
              'Filters out unlikely words. Higher = only the most probable words are kept. Start around 0.05–0.1.',
          context: context,
          onChanged: (val) {
            gen.minP = val;
            onChanged();
          },
        ),
        SliderWithInput(
          label: 'Top-P',
          value: gen.resolveTopP(storage),
          min: 0.1,
          max: 1.0,
          divisions: 90,
          tooltip:
              'Keeps only the most probable words up to this cumulative probability. 1.0 = off (let Min-P do the filtering). 0.9 is the classic default.',
          context: context,
          onChanged: (val) {
            gen.topP = val;
            onChanged();
          },
        ),
        SliderWithInput(
          label: 'Top-K',
          value: gen.resolveTopK(storage).toDouble(),
          min: 0,
          max: 200,
          divisions: 200,
          isInteger: true,
          tooltip:
              'Limits choices to the K most likely words. 0 = off. 40–100 are typical values when used.',
          context: context,
          onChanged: (val) {
            gen.topK = val.toInt();
            onChanged();
          },
        ),
        SliderWithInput(
          label: 'Repeat Penalty',
          value: gen.resolveRepeatPenalty(storage),
          min: 1.0,
          max: 3.0,
          divisions: 200,
          tooltip:
              'Discourages the AI from repeating the same words. Higher = less repetition. 1.1 is a safe default.',
          context: context,
          onChanged: (val) {
            gen.repeatPenalty = val;
            onChanged();
          },
        ),
        SliderWithInput(
          label: 'Rep Pen Tokens',
          value: gen.resolveRepeatPenaltyTokens(storage).toDouble(),
          min: 0,
          max: 2048,
          divisions: 256,
          isInteger: true,
          tooltip:
              'How far back the AI checks for repetition (in tokens). Higher = checks more of the conversation history.',
          context: context,
          onChanged: (val) {
            gen.repeatPenaltyTokens = val.toInt();
            onChanged();
          },
        ),
        if (llmProvider.activeBackend == BackendType.kobold) ...[
          SliderWithInput(
            label: 'XTC Threshold',
            value: gen.resolveXtcThreshold(storage),
            min: 0.0,
            max: 0.5,
            divisions: 50,
            tooltip:
                'Exclude Top Choices — removes the most obvious/cliché word choices. Lower = stronger effect. Try 0.1 for more creative writing.',
            context: context,
            onChanged: (val) {
              gen.xtcThreshold = val;
              onChanged();
            },
          ),
          SliderWithInput(
            label: 'XTC Probability',
            value: gen.resolveXtcProbability(storage),
            min: 0.0,
            max: 1.0,
            divisions: 20,
            tooltip:
                'How often XTC activates. 0 = never, 1 = always. Try 0.5 for a balance between creativity and coherence.',
            context: context,
            onChanged: (val) {
              gen.xtcProbability = val;
              onChanged();
            },
          ),
          SliderWithInput(
            label: 'DRY Strength',
            value: gen.resolveDryMultiplier(storage),
            min: 0.0,
            max: 3.0,
            divisions: 60,
            tooltip:
                'DRY ("Don\'t Repeat Yourself") — the modern anti-repetition sampler; catches repeated phrases, not just words. 0 = off, 0.8 is the usual dose.',
            context: context,
            onChanged: (val) {
              gen.dryMultiplier = val;
              onChanged();
            },
          ),
        ],
        if (!hideOutputTokenLimits) ...[
          SliderWithInput(
            label: 'Max Output Tokens',
            value: gen.resolveMaxLength(storage).toDouble(),
            min: 16,
            max: 16384,
            isInteger: true,
            tooltip:
                'Maximum number of tokens the AI can write in one response. Thinking models need higher values since reasoning tokens count toward this limit.',
            context: context,
            onChanged: (val) {
              gen.maxLength = val.toInt();
              onChanged();
            },
          ),
          SliderWithInput(
            label: 'Min Output Tokens',
            value: gen.resolveMinLength(storage).toDouble(),
            min: 0,
            max: 512,
            divisions: 512,
            isInteger: true,
            tooltip:
                'Minimum tokens the AI must write before it can stop. Increase for longer responses.',
            context: context,
            onChanged: (val) {
              gen.minLength = val.toInt();
              onChanged();
            },
          ),
        ],
        IgnorePointer(
          ignoring:
              storage.activeKcppsPath != null &&
              storage.activeKcppsPath!.isNotEmpty,
          child: Opacity(
            opacity:
                storage.activeKcppsPath != null &&
                    storage.activeKcppsPath!.isNotEmpty
                ? 0.5
                : 1.0,
            child: Tooltip(
              message:
                  storage.activeKcppsPath != null &&
                      storage.activeKcppsPath!.isNotEmpty
                  ? 'Context size is controlled by the active .kcpps preset and cannot be edited here.'
                  : '',
              child: SliderWithInput(
                label: 'Context Size',
                value: gen
                    .resolveContextSize(storage)
                    .toDouble()
                    .clamp(512, isRemote ? 500000 : 131072),
                min: 512,
                max: isRemote ? 500000.0 : 131072.0,
                isInteger: true,
                divisions: ((isRemote ? 500000.0 : 131072.0) - 512) ~/ 512,
                context: context,
                onChanged: (val) {
                  gen.contextSize = val.toInt();
                  onChanged();
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Dynamic Temperature',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            Tooltip(
              message:
                  'Varies temperature randomly within a range each generation for more varied outputs.',
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
            const Spacer(),
            Switch(
              value: gen.resolveDynamicTempEnabled(storage),
              onChanged: (val) {
                gen.dynamicTempEnabled = val;
                onChanged();
              },
              activeTrackColor: AppColors.formMasterAccent,
            ),
          ],
        ),
        if (gen.resolveDynamicTempEnabled(storage))
          SliderWithInput(
            label: 'Dynatemp Range',
            value: gen.resolveDynamicTempRange(storage),
            min: 0.0,
            max: 2.0,
            divisions: 20,
            tooltip:
                'How much the temperature can vary around the base temperature.',
            context: context,
            onChanged: (val) {
              gen.dynamicTempRange = val;
              onChanged();
            },
          ),
      ],
    );
  }
}
