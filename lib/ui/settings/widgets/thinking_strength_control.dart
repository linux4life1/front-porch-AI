// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Visible thinking-strength picker. Chips are this model's real levels
// (High / Max, or Minimal / Low / Medium / High, …) — not a fixed
// Low/Medium/High row that remaps two options onto the same wire value.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Segmented thinking-strength control used in Settings and per-chat settings.
class ThinkingStrengthControl extends StatelessWidget {
  const ThinkingStrengthControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.modelId = '',
    this.compact = false,
    this.showHeading = true,
    this.thinkingOn,
    this.onTurnOff,
    this.onTurnOn,
    this.offDisabled = false,
  });

  /// When [onTurnOff] is given, an Off chip leads the row so on/off and
  /// strength are one control. [thinkingOn] says whether thinking is on;
  /// picking a level while off calls [onTurnOn] first. A model with no
  /// levels of its own gets a plain On chip after Off.
  final bool? thinkingOn;
  final VoidCallback? onTurnOff;
  final VoidCallback? onTurnOn;

  /// Off is not pickable (a model that always thinks, or can never think).
  final bool offDisabled;

  /// Current pick (any ladder id: low, max, xhigh, …).
  final String value;

  final ValueChanged<String> onChanged;

  /// Active remote model id (e.g. deepseek/…:thinking). Empty = generic menu.
  final String modelId;

  /// Tighter padding for dialogs.
  final bool compact;

  /// False when an outer card/section already renders the "Thinking" title.
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final chips = reasoningEffortChipsFor(modelId);
    final withOff = onTurnOff != null;
    final off = withOff && thinkingOn == false;
    final selected =
        off ? '' : reasoningEffortDisplayedSelection(modelId, value);
    final caption = off
        ? ''
        : reasoningEffortMappingCaption(modelId, selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text(
            thinkingOn == null && onTurnOff == null
                ? 'Thinking strength'
                : 'Thinking',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13 : 14,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 360;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (withOff)
                  _StrengthChip(
                    id: 'off',
                    title: 'Off',
                    blurb: 'No thinking',
                    selected: off,
                    accent: accent,
                    wide: wide && chips.length <= 4,
                    onTap: offDisabled ? null : onTurnOff,
                  ),
                for (final id in chips)
                  _StrengthChip(
                    id: id,
                    selected: selected == id,
                    accent: accent,
                    wide: wide && chips.length <= 4,
                    onTap: () {
                      if (withOff && off) onTurnOn?.call();
                      onChanged(id);
                    },
                  ),
                if (withOff && chips.isEmpty)
                  _StrengthChip(
                    id: 'on',
                    title: 'On',
                    blurb: 'Think before replying',
                    selected: !off,
                    accent: accent,
                    wide: wide,
                    onTap: off ? onTurnOn : null,
                  ),
              ],
            );
          },
        ),
        SizedBox(height: compact ? 8 : 10),
        Text(
          caption.isEmpty
              ? 'How hard the model thinks before replying. The chips '
                    'match the levels this model actually accepts.'
              : caption,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _StrengthChip extends StatelessWidget {
  const _StrengthChip({
    required this.id,
    required this.selected,
    required this.accent,
    required this.wide,
    required this.onTap,
    this.title,
    this.blurb,
  });

  final String? title;
  final String? blurb;
  final String id;
  final bool selected;
  final Color accent;
  final bool wide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = this.title ?? reasoningEffortTitle(id);
    final blurb = this.blurb ?? reasoningEffortBlurb(id);

    return Material(
      color: selected ? accent : AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: wide ? 112 : null,
          constraints: const BoxConstraints(minWidth: 88),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : AppColors.borderOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: selected
                      ? AppColors.onAccentOf(context)
                      : AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (blurb.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  blurb,
                  style: TextStyle(
                    color: selected
                        ? AppColors.onAccentOf(context).withValues(alpha: 0.85)
                        : AppColors.textTertiary(context),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
