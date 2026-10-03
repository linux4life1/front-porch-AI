// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart';
import 'package:front_porch_ai/ui/widgets/slider_with_input.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

part 'greeting_seed_form.sections.dart';

/// Opening-state editor for one alternate greeting.
///
/// Visual twin of [RealismFormSection] + Needs (same section cards and
/// headers). Off (null) = this alt still gets reading-the-room. On = authored
/// seed: empty fields inherit the card/group defaults at chat start.
class GreetingSeedForm extends StatefulWidget {
  final GreetingRealismSeed? seed;
  final ValueChanged<GreetingRealismSeed?> onChanged;

  /// Kept so callers can hide Needs. Default on — alt openings seed hunger
  /// the same way they seed bond (audit: half-baked without it).
  final bool showNeeds;
  final bool showInventory;

  const GreetingSeedForm({
    super.key,
    required this.seed,
    required this.onChanged,
    this.showNeeds = true,
    this.showInventory = false,
  });

  @override
  State<GreetingSeedForm> createState() => _GreetingSeedFormState();
}

class _GreetingSeedFormState extends State<GreetingSeedForm> {
  GreetingRealismSeed? _stash;
  bool _uiOn = false;

  @override
  void initState() {
    super.initState();
    _stash = widget.seed;
    _uiOn = widget.seed != null;
  }

  @override
  void didUpdateWidget(covariant GreetingSeedForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seed != null) {
      _stash = widget.seed;
      _uiOn = true;
    }
  }

  static const _times = [
    'dawn',
    'morning',
    'late_morning',
    'afternoon',
    'evening',
    'night',
  ];
  static const _intensities = ['mild', 'moderate', 'strong'];

  @override
  Widget build(BuildContext context) {
    final enabled = _uiOn || widget.seed != null;
    final s = widget.seed ?? const GreetingRealismSeed();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _masterToggle(context, enabled),
        if (enabled) ...[
          const SizedBox(height: 20),
          _timeSection(s),
          const SizedBox(height: 20),
          _relationshipSection(s),
          const SizedBox(height: 20),
          _emotionSection(s),
          if (widget.showNeeds) ...[
            const SizedBox(height: 20),
            _needsSection(s),
          ],
          if (widget.showInventory) ...[
            const SizedBox(height: 20),
            IdentityChipLists(
              worn: _wornOf(s),
              onWornChanged: (v) => _setWardrobe(s, worn: v),
              carrying: _carryingOf(s),
              onCarryingChanged: (v) => _setWardrobe(s, carrying: v),
            ),
          ],
        ],
      ],
    );
  }

  Widget _masterToggle(BuildContext context, bool enabled) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? AppColors.formMasterAccent.withValues(alpha: 0.4)
              : AppColors.borderOf(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enabled
                  ? AppColors.formMasterAccent.withValues(alpha: 0.2)
                  : AppColors.surfaceContainerOf(
                      context,
                    ).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.tune,
              color: enabled
                  ? AppColors.formMasterAccent
                  : AppColors.iconSecondary(context),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom opening state',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Blank fields inherit the card defaults. This alt '
                            'will not read the room.'
                      : 'No seed — the engine reads the room from this '
                            'greeting.',
                  style: TextStyle(
                    color: enabled
                        ? AppColors.formMasterAccent
                        : AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (on) {
              if (on) {
                setState(() => _uiOn = true);
                widget.onChanged(_stash);
              } else {
                _stash = widget.seed ?? _stash;
                setState(() => _uiOn = false);
                widget.onChanged(null);
              }
            },
            activeTrackColor: AppColors.formMasterAccent.withValues(alpha: 0.5),
            activeThumbColor: AppColors.formMasterAccent,
          ),
        ],
      ),
    );
  }

  static final _needs =
      <
        (
          String,
          int? Function(GreetingRealismSeed),
          GreetingRealismSeed Function(GreetingRealismSeed, int),
          GreetingRealismSeed Function(GreetingRealismSeed),
        )
      >[
        (
          'Hunger',
          (s) => s.needsBaselineHunger,
          (s, v) => s.copyWith(needsBaselineHunger: v),
          (s) => s.copyWith(needsBaselineHunger: null),
        ),
        (
          'Bladder',
          (s) => s.needsBaselineBladder,
          (s, v) => s.copyWith(needsBaselineBladder: v),
          (s) => s.copyWith(needsBaselineBladder: null),
        ),
        (
          'Bowels',
          (s) => s.needsBaselineBowels,
          (s, v) => s.copyWith(needsBaselineBowels: v),
          (s) => s.copyWith(needsBaselineBowels: null),
        ),
        (
          'Energy',
          (s) => s.needsBaselineEnergy,
          (s, v) => s.copyWith(needsBaselineEnergy: v),
          (s) => s.copyWith(needsBaselineEnergy: null),
        ),
        (
          'Social',
          (s) => s.needsBaselineSocial,
          (s, v) => s.copyWith(needsBaselineSocial: v),
          (s) => s.copyWith(needsBaselineSocial: null),
        ),
        (
          'Fun',
          (s) => s.needsBaselineFun,
          (s, v) => s.copyWith(needsBaselineFun: v),
          (s) => s.copyWith(needsBaselineFun: null),
        ),
        (
          'Hygiene',
          (s) => s.needsBaselineHygiene,
          (s, v) => s.copyWith(needsBaselineHygiene: v),
          (s) => s.copyWith(needsBaselineHygiene: null),
        ),
        (
          'Comfort',
          (s) => s.needsBaselineComfort,
          (s, v) => s.copyWith(needsBaselineComfort: v),
          (s) => s.copyWith(needsBaselineComfort: null),
        ),
      ];

  List<String> _wornOf(GreetingRealismSeed s) {
    final inv = s.inventory;
    if (inv == null) return const [];
    return Pockets.fromJson(inv).worn.map((e) => e.display).toList();
  }

  List<String> _carryingOf(GreetingRealismSeed s) {
    final inv = s.inventory;
    if (inv == null) return const [];
    return Pockets.fromJson(inv).carrying.map((e) => e.display).toList();
  }

  void _setWardrobe(
    GreetingRealismSeed s, {
    List<String>? worn,
    List<String>? carrying,
  }) {
    final next = Pockets.cardJsonFrom(
      worn: worn ?? _wornOf(s),
      carrying: carrying ?? _carryingOf(s),
    );
    widget.onChanged(s.copyWith(inventory: next.isEmpty ? null : next));
  }
}
