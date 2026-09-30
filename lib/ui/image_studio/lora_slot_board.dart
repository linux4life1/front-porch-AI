// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'lora_picker.dart';

/// Four LoRA pickers, then an accordion with the remaining slots.
class LoraSlotBoard extends StatelessWidget {
  final List<LoraOption> loras;
  final ModelFamily checkpointFamily;
  final List<ImageGenLoraSlot> slots;
  final void Function(int index, String file, double weight) onSlot;

  const LoraSlotBoard({
    super.key,
    required this.loras,
    required this.checkpointFamily,
    required this.slots,
    required this.onSlot,
  });

  @override
  Widget build(BuildContext context) {
    final filled = slots.length < kImageGenLoraSlotCount
        ? ImageGenLoraSlot.fit(slots)
        : slots;
    final extra = filled.skip(kImageGenLoraVisibleSlots).toList();
    final extraUsed = extra.where((s) => !s.isEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kImageGenLoraVisibleSlots; i++)
          _slot(context, i, filled),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(
              extraUsed == 0 ? 'More LoRAs' : 'More LoRAs ($extraUsed)',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              for (var i = kImageGenLoraVisibleSlots; i < filled.length; i++)
                _slot(context, i, filled),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slot(BuildContext context, int index, List<ImageGenLoraSlot> filled) {
    final slot = filled[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LoRA ${index + 1}',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
          LoraPicker(
            loras: loras,
            checkpointFamily: checkpointFamily,
            selected: slot.file,
            weight: slot.weight,
            onSelected: (file) => onSlot(index, file, slot.weight),
            onWeightChanged: (weight) => onSlot(index, slot.file, weight),
          ),
        ],
      ),
    );
  }
}
