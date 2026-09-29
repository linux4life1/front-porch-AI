// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/image_gen_lora_slots.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

Widget _groupTitle(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
    child: Text(
      label,
      style: TextStyle(
        color: AppColors.formMasterAccent,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Names the LoRA and the model, and lets the user keep the mismatch.
class StudioLoraMismatch extends StatelessWidget {
  const StudioLoraMismatch({
    super.key,
    required this.lora,
    required this.primary,
    required this.onAnyway,
  });

  final String lora;
  final String primary;
  final VoidCallback onAnyway;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$lora does not match $primary.',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        TextButton(onPressed: onAnyway, child: const Text('Use anyway')),
      ],
    );
  }
}

/// LoRA files from the connected backend, and the eight slots they fill.
class StudioLoraSheet extends StatefulWidget {
  const StudioLoraSheet({
    super.key,
    required this.slots,
    required this.files,
    required this.primaryFile,
    this.facts = const {},
    required this.onPick,
    this.onWeight,
  });

  final List<ImageGenLoraSlot> slots;
  final List<String> files;
  final String primaryFile;
  final Map<String, DeskLoraCheck> facts;
  final void Function(int index, String file) onPick;
  final void Function(int index, double weight)? onWeight;

  @override
  State<StudioLoraSheet> createState() => _StudioLoraSheetState();
}

class _StudioLoraSheetState extends State<StudioLoraSheet> {
  late List<ImageGenLoraSlot> _slots = widget.slots;

  void _put(int index, String file) {
    widget.onPick(index, file);
    setState(() {
      final next = [..._slots];
      next[index] = ImageGenLoraSlot(file: file, weight: _slots[index].weight);
      _slots = next;
    });
  }

  void _add(String file) {
    final empty = _slots.indexWhere((slot) => slot.file.trim().isEmpty);
    if (empty < 0) return;
    _put(empty, file);
  }

  ModelFamily _familyOf(String file) {
    return widget.facts[file]?.family ?? ImageModelFamily.detectFromName(file);
  }

  LoraCompat _compat(String file, ModelFamily primary) {
    final fact = widget.facts[file];
    return ImageModelFamily.compatibility(
      _familyOf(file),
      primary,
      metadataBacked: fact?.metadataBacked ?? false,
    );
  }

  String _strength(int index) {
    return _slots[index].weight.clamp(0.0, 1.0).toStringAsFixed(2);
  }

  Widget _slotStrength(BuildContext context, int index) {
    final strength = _strength(index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slot ${index + 1}',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _slots[index].weight.clamp(0.0, 1.0),
                label: strength,
                showValueIndicator: ShowValueIndicator.alwaysVisible,
                onChanged: (value) {
                  widget.onWeight?.call(index, value);
                  setState(() {
                    final next = [..._slots];
                    next[index] = ImageGenLoraSlot(
                      file: _slots[index].file,
                      weight: value,
                    );
                    _slots = next;
                  });
                },
              ),
            ),
            Text(
              strength,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = ImageModelFamily.detectFromName(widget.primaryFile);
    final matching = <String>[];
    final other = <String>[];
    for (final file in widget.files) {
      if (_compat(file, primary) == LoraCompat.certain) {
        other.add(file);
      } else {
        matching.add(file);
      }
    }
    final full = _slots.every((slot) => slot.file.trim().isNotEmpty);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'LoRA',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.files.isEmpty
                  ? 'No LoRA files were listed by the connected app.'
                  : 'These are the LoRA files the connected app listed. '
                        'A tap fills the first empty slot.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Slots',
              style: TextStyle(
                color: AppColors.formMasterAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (var i = 0; i < kImageGenLoraSlotCount; i++)
              if (_slots[i].file.trim().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _slots[i].file,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  trailing: IconButton(
                    tooltip: 'Clear',
                    onPressed: () => _put(i, ''),
                    icon: Icon(
                      Icons.close,
                      color: AppColors.iconSecondary(context),
                    ),
                  ),
                  subtitle: _slotStrength(context, i),
                ),
            if (_slots.every((slot) => slot.file.trim().isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No LoRA in use.',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
            if (full)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'All eight slots are full. Clear one to add another.',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (matching.isNotEmpty) ...[
                    _groupTitle(context, 'Matches this model'),
                    for (final file in matching)
                      _loraTile(context, file, primary, full),
                  ],
                  if (other.isNotEmpty) ...[
                    _groupTitle(context, 'Other bases'),
                    for (final file in other)
                      _loraTile(context, file, primary, full),
                  ],
                ],
              ),
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

  Widget _loraTile(
    BuildContext context,
    String file,
    ModelFamily primary,
    bool full,
  ) {
    final blocked = full;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        file,
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
      ),
      subtitle: Text(
        _fitLabel(file, primary),
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12),
      ),
      enabled: !blocked,
      onTap: blocked ? null : () => _add(file),
    );
  }

  String _fitLabel(String file, ModelFamily primary) {
    final fact = widget.facts[file];
    final family = fact?.family ?? ImageModelFamily.detectFromName(file);
    final compat = ImageModelFamily.compatibility(
      family,
      primary,
      metadataBacked: fact?.metadataBacked ?? false,
    );
    final name = family.label;
    switch (compat) {
      case LoraCompat.match:
        return '$name · matches this model';
      case LoraCompat.likely:
        return '$name · guessed from the name, might fit';
      case LoraCompat.certain:
        return '$name · does not match this model';
      case LoraCompat.unknown:
        return 'Family not known from the file name';
    }
  }
}
