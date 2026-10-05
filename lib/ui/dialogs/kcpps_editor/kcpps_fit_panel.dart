// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_style.dart';
import 'kcpps_memory_bar.dart';
import 'kcpps_number_field.dart';

/// "How this loads on your card": where the model goes, what that takes,
/// and whether it fits, with the one-tap fix when it does not.
class KcppsFitPanel extends StatelessWidget {
  const KcppsFitPanel({super.key, required this.c});

  final KcppsEditorController c;

  void _place(bool manual) {
    if (manual && !c.draft.manual) {
      // Start from where KoboldCpp would put it.
      final load = c.view?.load;
      c.edit(
        (d) => d.copyWith(
          manual: true,
          gpuLayers: load?.gpuLayers ?? c.layerCount,
          moeCpuLayers: load?.moeCpuBlocks ?? 0,
        ),
      );
    } else {
      c.edit((d) => d.copyWith(manual: manual));
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = c.view;
    final amber = AppColors.porchAmberOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.insetPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'How this loads on ${c.cardName}',
                  style: keText(context, size: 17, weight: FontWeight.w600),
                ),
              ),
              Text(
                c.freeLine,
                style: keText(
                  context,
                  size: 13,
                  color: AppColors.slateMutedOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._body(context, view),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, KoboldFitView? view) {
    // What the user can act on comes first, on any machine.
    if (c.modelUnreadable) {
      return [
        _note(
          context,
          'The model file could not be read, so there is nothing to show '
          'here yet. Is it still in its folder? You can choose another '
          'model above.',
        ),
      ];
    }
    if (!c.hasCard) {
      return [
        _note(
          context,
          'This computer has no graphics card KoboldCpp can use, so the '
          'model runs on the processor.',
        ),
      ];
    }
    if (view == null) {
      return [
        _note(
          context,
          c.draft.modelPath.isEmpty
              ? 'Choose a model to see how it loads.'
              : c.modelReading
              ? 'Reading the model file…'
              : 'Still finding out what this computer can do…',
        ),
      ];
    }
    final moe = view.load.expertBlocks > 0;
    return [
      Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Placement',
            style: keText(
              context,
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.slateMutedOf(context),
            ),
          ),
          KeChoices<bool>(
            key: const ValueKey('kcpps-placement'),
            values: const [false, true],
            selected: c.draft.manual,
            expand: false,
            height: 40,
            label: (manual) =>
                manual ? 'Set it myself' : 'Automatic: KoboldCpp fits it',
            onSelected: _place,
          ),
        ],
      ),
      if (c.draft.manual) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _field(
              context,
              label: 'Layers on the card',
              value: c.draft.gpuLayers,
              most: c.layerCount,
              keyName: 'kcpps-layers',
              trailing: 'of ${c.layerCount}',
              error: view.fix != null && !moe,
              onValid: (n) => c.edit((d) => d.copyWith(gpuLayers: n)),
            ),
            if (moe)
              _field(
                context,
                label: 'Experts kept in system memory for the first',
                value: c.draft.moeCpuLayers,
                most: c.layerCount - 1,
                keyName: 'kcpps-moecpu',
                trailing:
                    'layers (the other '
                    '${(view.load.expertBlocks - c.draft.moeCpuLayers).clamp(0, view.load.expertBlocks)} on the card)',
                error: view.fix != null,
                onValid: (n) => c.edit((d) => d.copyWith(moeCpuLayers: n)),
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      KcppsMemoryBar(segments: view.segments),
      const SizedBox(height: 12),
      _verdict(context, view),
    ];
  }

  /// A number of layers, at most [most].
  Widget _field(
    BuildContext context, {
    required String label,
    required int value,
    required int most,
    required String keyName,
    required String trailing,
    required bool error,
    required ValueChanged<int> onValid,
  }) => KeNumberField(
    value: value,
    keyName: keyName,
    width: 72,
    semanticLabel: label,
    error: error,
    check: (text) {
      final n = int.tryParse(text);
      return n == null
          ? 'Type a number.'
          : n > most
          ? 'This model has $most layers.'
          : null;
    },
    onValid: (text) => onValid(int.parse(text)),
    builder: (context, box, problem) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeLabel(label, size: 13),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            box,
            const SizedBox(width: 8),
            Text(
              trailing,
              style: keText(
                context,
                size: 13,
                color: AppColors.slateFaintOf(context),
              ),
            ),
          ],
        ),
        if (problem != null) ...[
          const SizedBox(height: 4),
          Text(
            problem,
            style: keText(
              context,
              size: 12,
              color: AppColors.alertRedOf(context),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _note(BuildContext context, String text) => Text(
    text,
    style: keText(context, size: 14, color: AppColors.slateMutedOf(context)),
  );

  Widget _verdict(BuildContext context, KoboldFitView view) {
    final over = view.kind == KoboldFitKind.over;
    final tint = switch (view.kind) {
      KoboldFitKind.fits => AppColors.journalAccentOf(context),
      KoboldFitKind.reduced => AppColors.porchHoneyOf(context),
      KoboldFitKind.over => AppColors.alertRedOf(context),
    };
    final hint = view.batchHintText;
    final words = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${view.title} ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: view.text),
          if (hint != null) TextSpan(text: ' $hint'),
        ],
      ),
      style: keText(context, size: 14, height: 1.45),
    );
    return Container(
      key: const ValueKey('kcpps-verdict'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: over ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: over ? Border.all(color: tint.withValues(alpha: 0.5)) : null,
      ),
      child: Row(
        crossAxisAlignment: over
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: over
                ? Icon(Icons.warning_rounded, color: tint, size: 18)
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: KeMark(tint, round: true, size: 12),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(child: words),
          if (over && view.fix != null) ...[
            const SizedBox(width: 12),
            KeButton(
              'Use the largest that fits',
              kind: KeButtonKind.amber,
              padding: 14,
              onPressed: c.useLargestThatFits,
            ),
          ],
        ],
      ),
    );
  }
}
