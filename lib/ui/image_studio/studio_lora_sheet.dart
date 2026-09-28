// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/image_gen_lora_slots.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_search_sheet.dart';

/// Eight LoRA slots. An empty slot is skipped when the image is built.
class StudioLoraSheet extends StatefulWidget {
  const StudioLoraSheet({
    super.key,
    required this.slots,
    required this.files,
    required this.onPick,
  });

  final List<ImageGenLoraSlot> slots;
  final List<String> files;
  final void Function(int index, String file) onPick;

  @override
  State<StudioLoraSheet> createState() => _StudioLoraSheetState();
}

class _StudioLoraSheetState extends State<StudioLoraSheet> {
  late List<ImageGenLoraSlot> _slots = widget.slots;

  Future<void> _choose(int index) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StudioSearchSheet(
        title: 'LoRA ${index + 1}',
        items: widget.files,
        onPick: (file) {
          widget.onPick(index, file);
          setState(() {
            final next = [..._slots];
            next[index] = ImageGenLoraSlot(
              file: file,
              weight: _slots[index].weight,
            );
            _slots = next;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'LoRA search',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < kImageGenLoraSlotCount; i++)
              ListTile(
                title: Text(
                  _slots[i].file.trim().isEmpty
                      ? 'LoRA ${i + 1}'
                      : _slots[i].file,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                trailing: IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    widget.onPick(i, '');
                    setState(() {
                      final next = [..._slots];
                      next[i] = ImageGenLoraSlot(weight: _slots[i].weight);
                      _slots = next;
                    });
                  },
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
                onTap: () => _choose(i),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
