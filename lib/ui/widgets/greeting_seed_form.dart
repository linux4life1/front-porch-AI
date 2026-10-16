// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart';

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
          GreetingSeedTimeSection(seed: s, onChanged: widget.onChanged),
          const SizedBox(height: 20),
          GreetingSeedRelationshipSection(seed: s, onChanged: widget.onChanged),
          const SizedBox(height: 20),
          GreetingSeedEmotionSection(seed: s, onChanged: widget.onChanged),
          if (widget.showNeeds) ...[
            const SizedBox(height: 20),
            GreetingSeedNeedsSection(seed: s, onChanged: widget.onChanged),
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
        color: context.creatorPalette?.card ?? AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? (context.creatorPalette?.amber ?? AppColors.formMasterAccent)
                    .withValues(alpha: 0.4)
              : context.creatorPalette?.line ?? AppColors.borderOf(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enabled
                  ? (context.creatorPalette?.amber ??
                            AppColors.formMasterAccent)
                        .withValues(alpha: 0.2)
                  : (context.creatorPalette?.raise ??
                            AppColors.surfaceContainerOf(context))
                        .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.tune,
              color: enabled
                  ? context.creatorPalette?.amber ?? AppColors.formMasterAccent
                  : context.creatorPalette?.muted ??
                        AppColors.iconSecondary(context),
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
                    color:
                        context.creatorPalette?.ink ??
                        AppColors.textPrimary(context),
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
                        ? context.creatorPalette?.amber ??
                              AppColors.formMasterAccent
                        : context.creatorPalette?.muted ??
                              AppColors.textTertiary(context),
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
            activeTrackColor:
                (context.creatorPalette?.amber ?? AppColors.formMasterAccent)
                    .withValues(alpha: 0.5),
            activeThumbColor:
                context.creatorPalette?.amber ?? AppColors.formMasterAccent,
          ),
        ],
      ),
    );
  }

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
