// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';

// Field name keys for the needs baselines map (and the card's needsOff list).
const kGroupNeedHunger = 'hunger';
const kGroupNeedBladder = 'bladder';
const kGroupNeedEnergy = 'energy';
const kGroupNeedSocial = 'social';
const kGroupNeedFun = 'fun';
const kGroupNeedHygiene = 'hygiene';
const kGroupNeedComfort = 'comfort';

const kGroupNeedFields = [
  kGroupNeedHunger,
  kGroupNeedBladder,
  kGroupNeedEnergy,
  kGroupNeedSocial,
  kGroupNeedFun,
  kGroupNeedHygiene,
  kGroupNeedComfort,
];

const _kNeedLabels = [
  ('Hunger', kGroupNeedHunger),
  ('Bladder', kGroupNeedBladder),
  ('Energy', kGroupNeedEnergy),
  ('Social', kGroupNeedSocial),
  ('Fun', kGroupNeedFun),
  ('Hygiene', kGroupNeedHygiene),
  ('Comfort', kGroupNeedComfort),
];

/// One member's card on the Group Settings Needs tab: starting values,
/// per-need on/off, Pace, and "enjoys low hygiene".
class GroupMemberNeedsCard extends StatelessWidget {
  final int index;
  final CharacterCard char;
  final Map<String, int> baselines;
  final List<String> needsOff;
  final String pace;
  final bool enjoysLowHygiene;
  final void Function(String field, int value) onBaselineChanged;
  final ValueChanged<List<String>> onNeedsOffChanged;
  final ValueChanged<String> onPaceChanged;
  final ValueChanged<bool> onEnjoysLowHygieneChanged;
  final VoidCallback onReset;

  const GroupMemberNeedsCard({
    super.key,
    required this.index,
    required this.char,
    required this.baselines,
    required this.needsOff,
    required this.pace,
    required this.enjoysLowHygiene,
    required this.onBaselineChanged,
    required this.onNeedsOffChanged,
    required this.onPaceChanged,
    required this.onEnjoysLowHygieneChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name + reset
          Row(
            children: [
              // No portrait (or only the flat placeholder): the initial.
              RealPortrait(
                file: char.imagePath != null ? File(char.imagePath!) : null,
                portrait: (_, file) => CircleAvatar(
                  radius: 16,
                  backgroundColor: groupCharAccentColor(index),
                  backgroundImage: FileImage(file),
                ),
                noPortrait: (_) => CircleAvatar(
                  radius: 16,
                  backgroundColor: groupCharAccentColor(index),
                  child: Text(
                    char.name.isNotEmpty ? char.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: StatusColors.onFill,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  char.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Reset',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.porchAmberOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          for (final (label, key) in _kNeedLabels)
            _needsSlider(
              context,
              label,
              key,
              baselines[key] ?? 80,
              (v) => onBaselineChanged(key, v),
            ),

          const SizedBox(height: 8),
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 8),
          Text(
            'Pace',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How fast needs drop as time passes. A meal or a bath stays the same.',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sloth', label: Text('Sloth')),
              ButtonSegment(value: 'normal', label: Text('Normal')),
              ButtonSegment(value: 'fast', label: Text('Fast')),
            ],
            selected: {pace},
            onSelectionChanged: (next) => onPaceChanged(next.first),
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 8),

          // Enjoys low hygiene
          Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 14,
                color: AppColors.porchAmberOf(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enjoys low hygiene',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
              SizedBox(
                height: 20,
                width: 20,
                child: Checkbox(
                  value: enjoysLowHygiene,
                  onChanged: (v) {
                    if (v != null) {
                      onEnjoysLowHygieneChanged(v);
                    }
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _needsSlider(
    BuildContext context,
    String label,
    String needKey,
    int value,
    ValueChanged<int> onChanged,
  ) {
    final off = needsOff;
    final alive = !off.contains(needKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary(context),
              ),
            ),
            Switch(
              value: alive,
              onChanged: (next) {
                final nextOff = [...off];
                if (next) {
                  nextOff.remove(needKey);
                } else if (!nextOff.contains(needKey)) {
                  nextOff.add(needKey);
                }
                onNeedsOffChanged(nextOff);
              },
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.porchAmberOf(context),
            inactiveTrackColor: AppColors.borderOf(context),
            thumbColor: AppColors.porchAmberOf(context),
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ],
    );
  }
}
