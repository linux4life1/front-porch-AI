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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat/chat.dart' show kMaxWorn;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
// Sibling in this file's OWN barrel directory — importing widgets.dart here
// would be a self-import (the structural exemption in CLAUDE.md).
import 'package:front_porch_ai/ui/widgets/chip_list_editor.dart';
import 'package:front_porch_ai/ui/widgets/plan_lines_editor.dart';
import 'package:front_porch_ai/ui/widgets/work_row.dart';

/// The install's 18+ master switch — the same one that shows or hides the
/// After Dark group in Settings — or `false` when no [StorageService] is in
/// scope.
///
/// The fallback is not defensive padding, it is the contract. Both character
/// creators render their realism step inside golden harnesses that wrap
/// nothing in a Provider, so reading storage directly from those widgets threw
/// ProviderNotFoundException and took three goldens down. An authoring toggle
/// must never be the thing that crashes a render, and "no storage in scope"
/// can only mean a harness — where hiding the adult section is also the right
/// answer.
///
/// One helper rather than a try/catch at each of the three call sites (desktop
/// editor, manual creator, AI creator).
bool adultThemesEnabledOf(BuildContext context) {
  try {
    return Provider.of<StorageService>(
      context,
      listen: false,
    ).realismSettings.adultThemesEnabled;
  } catch (_) {
    return false;
  }
}

bool plannerEnabledOf(BuildContext context) {
  try {
    return Provider.of<StorageService>(
      context,
    ).realismSettings.plannerEnabled;
  } catch (_) {
    return false;
  }
}

/// The card-authored IDENTITY lists — Ambitions, Likes & Dislikes, and the 18+
/// pair — every one of them a short list of short phrases edited as chips.
///
/// Extracted from realism_form_section.dart, which was already 856 lines and
/// could not carry three more sections. They belong together anyway: these are
/// the fields that describe who a character IS and travel with the card,
/// as opposed to the sliders above them, which seed story state.
///
/// Every section is independently optional — pass the values and the callback
/// or the section is absent. That is how the group-member card and the older
/// creator steps keep working without knowing these fields exist.
class IdentityChipLists extends StatelessWidget {
  const IdentityChipLists({
    super.key,
    this.ambitions,
    this.onAmbitionsChanged,
    this.planLines,
    this.onPlanLinesChanged,
    this.occupation,
    this.onOccupationChanged,
    this.hours,
    this.onHoursChanged,
    this.likes,
    this.onLikesChanged,
    this.dislikes,
    this.onDislikesChanged,
    this.intimateInto,
    this.onIntimateIntoChanged,
    this.intimateNotInto,
    this.onIntimateNotIntoChanged,
    this.showIntimate = false,
    this.worn,
    this.onWornChanged,
    this.carrying,
    this.onCarryingChanged,
  });

  final List<String>? ambitions;
  final ValueChanged<List<String>>? onAmbitionsChanged;

  final List<String>? planLines;
  final ValueChanged<List<String>>? onPlanLinesChanged;

  final String? occupation;
  final ValueChanged<String>? onOccupationChanged;
  final String? hours;
  final ValueChanged<String>? onHoursChanged;

  final List<String>? likes;
  final ValueChanged<List<String>>? onLikesChanged;
  final List<String>? dislikes;
  final ValueChanged<List<String>>? onDislikesChanged;

  /// The 18+ pair. Rendered ONLY when [showIntimate] — the caller passes the
  /// install's adult-themes switch, the same one that shows or hides the
  /// After Dark group in Settings. An author who has not opted into 18+
  /// content never sees these boxes; anything already typed is kept on the
  /// card, exactly as turning the master switch off elsewhere keeps state.
  final List<String>? intimateInto;
  final ValueChanged<List<String>>? onIntimateIntoChanged;
  final List<String>? intimateNotInto;
  final ValueChanged<List<String>>? onIntimateNotIntoChanged;
  final bool showIntimate;

  /// Starting Pockets & Wardrobe: what the character already has when a chat
  /// opens. Chip text is the item as it READS — `sundress (rain-soaked)` —
  /// which [PocketItem.parseDisplay] splits back into name + condition. That is
  /// the same string the sidebar, the receipts and the prompt all show, so
  /// there is nothing new to learn and no second field per item.
  final List<String>? worn;
  final ValueChanged<List<String>>? onWornChanged;
  final List<String>? carrying;
  final ValueChanged<List<String>>? onCarryingChanged;

  static Widget _header(IconData icon, String text, Color color) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );

  Widget _card(BuildContext context, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.cardOf(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderOf(context)),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final hasAmbitions = ambitions != null && onAmbitionsChanged != null;
    final hasPlanLines = plannerEnabledOf(context) &&
        planLines != null &&
        onPlanLinesChanged != null;
    final hasWork = occupation != null &&
        onOccupationChanged != null &&
        hours != null &&
        onHoursChanged != null;
    final hasTastes =
        likes != null &&
        onLikesChanged != null &&
        dislikes != null &&
        onDislikesChanged != null;
    final hasIntimate =
        showIntimate &&
        intimateInto != null &&
        onIntimateIntoChanged != null &&
        intimateNotInto != null &&
        onIntimateNotIntoChanged != null;

    final hasWardrobe =
        worn != null &&
        onWornChanged != null &&
        carrying != null &&
        onCarryingChanged != null;

    if (!hasAmbitions &&
        !hasPlanLines &&
        !hasWork &&
        !hasTastes &&
        !hasIntimate &&
        !hasWardrobe) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ambitions (approved sketch §4) ──
        // "Ambitions — long-term goals, one per chip (replaces 'Current
        // Task / Quest' in this editor)". The mountain, not the next step:
        // quests are per-chat and live in the sidebar's Objectives panel.
        if (hasAmbitions) ...[
          _header(Icons.flag, 'Ambitions', AppColors.taskAccent),
          const SizedBox(height: 12),
          _card(
            context,
            ChipListEditor(
              label: 'Long-term goals',
              accent: true,
              values: ambitions!,
              onChanged: onAmbitionsChanged!,
              hintText: 'e.g. open a bakery',
              helper:
                  'What this character is working toward across the whole '
                  'story. They colour how the character steers a scene, and '
                  'they inch forward when objectives complete. Not a to-do '
                  'list — quests live in the chat sidebar.',
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (hasPlanLines) ...[
          PlanLinesEditor(
            enabled: true,
            values: planLines!,
            onChanged: onPlanLinesChanged!,
          ),
          const SizedBox(height: 20),
        ],

        if (hasWork) ...[
          WorkRow(
            occupation: occupation!,
            hours: hours!,
            onOccupationChanged: onOccupationChanged!,
            onHoursChanged: onHoursChanged!,
          ),
          const SizedBox(height: 20),
        ],

        // ── Likes & Dislikes ──
        if (hasTastes) ...[
          _header(
            Icons.favorite_outline,
            'Likes & Dislikes',
            AppColors.formMasterAccent,
          ),
          const SizedBox(height: 12),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChipListEditor(
                  label: 'Drawn to',
                  values: likes!,
                  onChanged: onLikesChanged!,
                  hintText: 'e.g. thunderstorms',
                  helper:
                      'Small, specific things this character warms to. They '
                      'colour how the character reacts to what is already '
                      'happening — and, with the Realism Engine on, how much '
                      'a moment moves them.',
                ),
                const SizedBox(height: 16),
                ChipListEditor(
                  label: 'Put off by',
                  values: dislikes!,
                  onChanged: onDislikesChanged!,
                  hintText: 'e.g. being interrupted',
                  helper:
                      'What makes this character bristle. Phrases, not '
                      'paragraphs — one thing per chip reads best in a scene.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Pockets & Wardrobe (docs/design/pockets-and-preferences.md §1) ──
        // The authoring half of a feature that already shipped everything
        // else: the runtime seeds a chat's record from exactly this map
        // (chat_service_pockets.dart), so until now the only way a character
        // could start a chat holding anything was to hand-edit the card JSON.
        if (hasWardrobe) ...[
          _header(
            Icons.checkroom,
            'Pockets & Wardrobe',
            AppColors.porchAmberOf(context),
          ),
          const SizedBox(height: 12),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What this character already has when a chat opens. Add a '
                  'condition in brackets — "sundress (rain-soaked)" — and it '
                  'is kept and updated as the story uses the item.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 14),
                ChipListEditor(
                  label: 'Wearing',
                  values: worn!,
                  onChanged: onWornChanged!,
                  hintText: 'e.g. flour-dusted apron',
                ),
                const SizedBox(height: 16),
                ChipListEditor(
                  label: 'Carrying',
                  values: carrying!,
                  onChanged: onCarryingChanged!,
                  hintText: 'e.g. car keys',
                  helper:
                      'Tracked once Pockets & Wardrobe is switched on in '
                      'Settings → Porch Life. Up to $kMaxWorn of each; the '
                      'oldest drops off if a character picks up more.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── The 18+ pair, only for an install that asked for it ──
        if (hasIntimate) ...[
          _header(
            Icons.nightlight_round,
            'Intimate preferences',
            AppColors.lustAccent,
          ),
          const SizedBox(height: 12),
          _card(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggestive tastes for 18+ scenes. These stay out of the '
                  'prompt entirely unless 18+ themes are switched on.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 14),
                ChipListEditor(
                  label: 'Warms to',
                  values: intimateInto!,
                  onChanged: onIntimateIntoChanged!,
                  hintText: 'e.g. slow mornings',
                ),
                const SizedBox(height: 16),
                ChipListEditor(
                  label: 'Not interested in',
                  values: intimateNotInto!,
                  onChanged: onIntimateNotIntoChanged!,
                  hintText: 'e.g. an audience',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
