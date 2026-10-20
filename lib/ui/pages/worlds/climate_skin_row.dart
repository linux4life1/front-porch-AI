// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_editor_widgets.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_skin_draft.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_emoji_picker.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// One rename row from the artifact's "Rename the weather" list: a surface
/// card laid out as `Condition → [emoji] [new name / flavour] [stance pill]`.
/// A rename without a danger level turns the card's border red, dashes the
/// pill ("Pick one ▾"), and shows the picnic warning — the visual twin of
/// the mockup's Acid Mist error row.
class SkinEditRow extends StatelessWidget {
  const SkinEditRow({
    super.key,
    required this.condition,
    required this.draft,
    required this.labelController,
    required this.flavourController,
    required this.onLabel,
    required this.onEmoji,
    required this.onFlavour,
    required this.onStance,
  });

  final String condition;
  final SkinDraft draft;
  final TextEditingController labelController;
  final TextEditingController flavourController;
  final ValueChanged<String> onLabel;
  final ValueChanged<String> onEmoji;
  final ValueChanged<String> onFlavour;
  final ValueChanged<WeatherStance?> onStance;

  InputDecoration _dec(BuildContext context, String hint) => InputDecoration(
    isDense: true,
    hintText: hint,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    hintStyle: TextStyle(
      fontSize: 11.5,
      color: AppColors.textTertiary(context),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(color: AppColors.borderOf(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(color: AppColors.porchAmberOf(context)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final missingStance = draft.active && draft.stance == null;
    final stockEmoji = WeatherEngine.emoji(
      WeatherCondition.values[kWeatherConditions.indexOf(condition)],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: missingStance
              ? kClimateDanger.withValues(alpha: 0.65)
              : AppColors.borderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  '$stockEmoji ${condition[0].toUpperCase()}${condition.substring(1)} →',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ),
              // The mockup's emoji cell, as a picker: tap to choose from the
              // curated weird-weather set (or type any emoji inside it).
              Tooltip(
                message: draft.active ? 'Pick an emoji' : 'Type a rename first',
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: draft.active
                      ? () async {
                          final picked = await showClimateEmojiPicker(
                            context,
                            current: draft.emoji,
                          );
                          if (!context.mounted) return;
                          if (picked != null) onEmoji(picked);
                        }
                      : null,
                  child: Container(
                    width: 40,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Opacity(
                      opacity: draft.active && draft.emoji.isNotEmpty
                          ? 1.0
                          : 0.35,
                      child: Text(
                        draft.emoji.isNotEmpty ? draft.emoji : '🌪️',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: labelController,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _dec(context, 'rename (e.g. Dust Squall)'),
                  onChanged: onLabel,
                ),
              ),
              const SizedBox(width: 10),
              _stancePill(context, missingStance),
            ],
          ),
          if (draft.active) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 92),
              child: TextField(
                controller: flavourController,
                maxLength: 140,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                ),
                decoration: _dec(
                  context,
                  '"rust-red columns wander the plain" (optional)',
                ),
                onChanged: onFlavour,
              ),
            ),
          ],
          if (missingStance) ...[
            const SizedBox(height: 6),
            Text(
              'A renamed weather needs a danger level — otherwise characters '
              'would picnic in ${draft.label.trim()}.',
              style: TextStyle(
                fontSize: 12,
                color: StatusColors.climateDangerOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The stance selector rendered as the mockup's pill: uppercase, rounded,
  /// border tinted by stance (grey / warn / danger), dashed-red "Pick one ▾"
  /// while missing.
  Widget _stancePill(BuildContext context, bool missingStance) {
    final color = missingStance
        ? StatusColors.climateDangerOf(context)
        : stanceColor(context, draft.stance);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: draft.active
              ? color.withValues(alpha: missingStance ? 0.9 : 0.55)
              : AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<WeatherStance?>(
          value: draft.stance,
          isDense: true,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              missingStance ? 'PICK ONE' : 'DANGER',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: draft.active
                    ? color
                    : AppColors.textTertiary(context).withValues(alpha: 0.6),
              ),
            ),
          ),
          dropdownColor: AppColors.surfaceContainerOf(context),
          items: [
            for (final s in WeatherStance.values)
              DropdownMenuItem(
                value: s,
                child: Text(
                  stanceLabel(s),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
          selectedItemBuilder: (context) => [
            for (final s in WeatherStance.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    stanceLabel(s).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: stanceColor(context, s),
                    ),
                  ),
                ),
              ),
          ],
          onChanged: draft.active ? onStance : null,
        ),
      ),
    );
  }
}
