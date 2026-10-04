// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_style.dart';

/// Chat length: the context, the chat memory's size, sliding window.
class KcppsChatLengthSection extends StatelessWidget {
  const KcppsChatLengthSection({super.key, required this.c});

  final KcppsEditorController c;

  static const _sizes = [KvQuant.f16, KvQuant.q8_0, KvQuant.q5_1, KvQuant.q4_0];

  @override
  Widget build(BuildContext context) {
    final d = c.draft;
    final max = c.maxContext;
    final low = d.contextSize < kKoboldContextFloor;
    final compressible = c.flashAttentionRuns && d.flashAttention;
    final sizes = [
      for (final q in [KvQuant.f16, KvQuant.q8_0, KvQuant.q4_0])
        if (c.cacheMbFor(q) case final mb?)
          '${kvQuantWords(q)} ${(mb / 1024).toStringAsFixed(1)} GB',
    ];
    final swa = c.info?.hasSlidingWindow ?? false;
    final faint = AppColors.slateFaintOf(context);
    return KeSection(
      title: 'Chat length',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KeLabel('Context: how much chat it sees at once', size: 13),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.porchAmberOf(context),
                      thumbColor: AppColors.porchAmberOf(context),
                      inactiveTrackColor: AppColors.hairlineOf(context, 0.18),
                    ),
                    child: Slider(
                      key: const ValueKey('kcpps-context'),
                      min: 2048,
                      max: max.toDouble(),
                      divisions: (max - 2048) ~/ 2048,
                      value: d.contextSize.clamp(2048, max).toDouble(),
                      semanticFormatterCallback: (v) =>
                          '${koboldTokens(v.round())} tokens',
                      onChanged: (v) => c.edit(
                        (d) =>
                            d.copyWith(contextSize: (v / 2048).round() * 2048),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    '${koboldTokens(d.contextSize)} tokens',
                    textAlign: TextAlign.right,
                    style: keText(context, size: 14),
                  ),
                ),
              ],
            ),
            Text(
              '16,384 or more. Below that is not recommended or supported: '
              'characters remember very little of the chat.',
              style: keText(
                context,
                size: 12,
                color: low ? AppColors.porchHoneyOf(context) : faint,
                weight: low ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KeLabel('Chat memory size', size: 13),
            const SizedBox(height: 6),
            KeChoices<KvQuant>(
              key: const ValueKey('kcpps-cache'),
              values: _sizes,
              selected: d.kvQuant == KvQuant.bf16 ? KvQuant.f16 : d.kvQuant,
              label: kvQuantWords,
              enabled: (q) => compressible || !q.needsFlashAttention,
              onSelected: (q) => c.edit((d) => d.copyWith(kvQuant: q)),
            ),
            const SizedBox(height: 6),
            Text(
              compressible
                  ? '${sizes.join(' · ')}${sizes.isEmpty ? '' : '. '}Smaller '
                        'remembers a little less exactly.'
                  : 'Smaller sizes need flash attention, which is off.',
              style: keText(context, size: 12, color: faint),
            ),
          ],
        ),
        if (swa)
          KeCheck(
            value: d.slidingWindow,
            label:
                'Sliding window: less chat memory, but every reply reads '
                'the whole chat again',
            onChanged: (v) => c.edit((d) => d.copyWith(slidingWindow: v)),
          )
        else
          Text(
            'This model has no sliding window, so replies start fast on '
            'long chats (fast forward stays on).',
            style: keText(context, size: 12, color: faint),
          ),
      ],
    );
  }
}

/// Speed: the batch, flash attention, MMQ, and the spare memory kept.
class KcppsSpeedSection extends StatefulWidget {
  const KcppsSpeedSection({super.key, required this.c});

  final KcppsEditorController c;

  @override
  State<KcppsSpeedSection> createState() => _KcppsSpeedSectionState();
}

class _KcppsSpeedSectionState extends State<KcppsSpeedSection> {
  final _batch = TextEditingController();
  String? _problem;

  KcppsEditorController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _batch.text = '${c.draft.batchSize}';
  }

  @override
  void didUpdateWidget(KcppsSpeedSection old) {
    super.didUpdateWidget(old);
    if (_problem == null && int.tryParse(_batch.text) != c.draft.batchSize) {
      _batch.text = '${c.draft.batchSize}';
    }
  }

  @override
  void dispose() {
    _batch.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final n = int.tryParse(text);
    setState(
      () => _problem = n == null || n < 16 || n > 8192
          ? 'A batch is 16 to 8,192 tokens.'
          : null,
    );
    if (_problem == null) c.edit((d) => d.copyWith(batchSize: n));
  }

  @override
  Widget build(BuildContext context) {
    final d = c.draft;
    final hint = c.view?.batchHint;
    final faint = AppColors.slateFaintOf(context);
    final note = c.flashAttentionNote;
    return KeSection(
      title: 'Speed',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KeLabel('Batch: tokens read at a time', size: 13),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KeBox(
                  controller: _batch,
                  keyName: 'kcpps-batch',
                  width: 120,
                  number: true,
                  error: _problem != null,
                  semanticLabel: 'Batch: tokens read at a time',
                  onChanged: _typed,
                ),
                if (_problem != null || hint != null)
                  Text(
                    _problem ?? 'Suggested ${hint!.batch}: ${hint.what}',
                    style: keText(
                      context,
                      size: 12,
                      color: _problem != null
                          ? AppColors.alertRedOf(context)
                          : faint,
                    ),
                  ),
              ],
            ),
          ],
        ),
        KeCheck(
          value: c.flashAttentionRuns && d.flashAttention,
          label: 'Flash attention (faster, less memory)',
          onChanged: c.flashAttentionRuns
              ? (v) => c.edit((d) => d.copyWith(flashAttention: v))
              : null,
        ),
        if (note != null)
          Text(note, style: keText(context, size: 12, color: faint)),
        if (c.mmqApplies)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeCheck(
                value: d.mmq ?? true,
                label:
                    'MMQ (${c.rocm ? 'ROCm' : 'NVIDIA'}): faster on some '
                    'cards, slower on others',
                onChanged: (v) => c.edit((d) => d.copyWith(mmq: v)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  KeButton(
                    c.mmqTiming ? 'Timing…' : 'Time both on this card',
                    kind: KeButtonKind.amberOutline,
                    height: 36,
                    padding: 12,
                    fontSize: 13,
                    onPressed: c.mmqTiming || c.draft.modelPath.isEmpty
                        ? null
                        : c.timeMmq,
                  ),
                  if (c.mmqStatus case final status?)
                    Text(
                      status,
                      style: keText(context, size: 12, color: faint),
                    ),
                ],
              ),
            ],
          ),
        KeCheck(
          value: d.greedy,
          label: 'Greedy: keep 32 MB spare instead of 1 GB',
          // Only KoboldCpp's own fit keeps memory spare.
          onChanged: d.manual
              ? null
              : (v) => c.edit((d) => d.copyWith(greedy: v)),
        ),
      ],
    );
  }
}
