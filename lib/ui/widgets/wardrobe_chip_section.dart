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

import 'package:front_porch_ai/services/chat/chat.dart'
    show PocketItem, isEmptyWardrobeRef, kMaxWorn;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
// Sibling in this file's OWN barrel directory — importing widgets.dart here
// would be a self-import (the structural exemption in CLAUDE.md).
import 'package:front_porch_ai/ui/widgets/chip_list_editor.dart';

/// Porch Life's global Pockets switch — or `false` when no [StorageService]
/// is in scope (golden / widget harnesses). Same contract as
/// [adultThemesEnabledOf]: a missing provider must not crash authoring.
bool porchLifePocketsEnabledOf(BuildContext context) {
  try {
    return Provider.of<StorageService>(context).realismSettings.pocketsEnabled;
  } catch (_) {
    return false;
  }
}

/// Starting kit (Wearing / Carrying) plus the optional per-character enable.
///
/// The toggle belongs on this panel — not under Edit Character → Details
/// Optional Features. When the pair is omitted (greeting seed, group-member
/// editors), the chip lists behave as they always have.
class WardrobeChipSection extends StatelessWidget {
  const WardrobeChipSection({
    super.key,
    required this.worn,
    required this.onWornChanged,
    required this.carrying,
    required this.onCarryingChanged,
    this.pocketsEnabled,
    this.onPocketsEnabledChanged,
  });

  final List<String> worn;
  final ValueChanged<List<String>> onWornChanged;
  final List<String> carrying;
  final ValueChanged<List<String>> onCarryingChanged;
  final bool? pocketsEnabled;
  final ValueChanged<bool>? onPocketsEnabledChanged;

  static const Key panelKey = Key('character-pockets-panel');
  static const Key enableKey = Key('character-pockets-enabled');

  bool get _hasToggle =>
      pocketsEnabled != null && onPocketsEnabledChanged != null;

  /// Kit editors stay up unless this character's switch is explicitly off.
  bool get _editKit => !_hasToggle || pocketsEnabled!;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final globalOn = porchLifePocketsEnabledOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checkroom, size: 18, color: amber),
            const SizedBox(width: 8),
            Text(
              'Pockets & Wardrobe',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: amber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          key: panelKey,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasToggle) ...[
                _enableRow(context, amber),
                const SizedBox(height: 14),
              ],
              if (_editKit) ...[
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
                if (!globalOn) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Porch Life has Pockets off. This starting kit is saved; '
                    'tracking stays off until Settings → Porch Life turns '
                    'Pockets on.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                ChipListEditor(
                  label: 'Wearing',
                  values: worn,
                  onChanged: (v) => onWornChanged([
                    for (final s in v)
                      if (!isEmptyWardrobeRef(PocketItem.parseDisplay(s).name))
                        s,
                  ]),
                  hintText: 'e.g. flour-dusted apron',
                ),
                const SizedBox(height: 16),
                ChipListEditor(
                  label: 'Carrying',
                  values: carrying,
                  onChanged: onCarryingChanged,
                  hintText: 'e.g. car keys',
                  helper:
                      'Tracked once Pockets & Wardrobe is switched on in '
                      'Settings → Porch Life and this character\'s switch is '
                      'on. Up to $kMaxWorn of each; the oldest drops off if a '
                      'character picks up more.',
                ),
              ] else
                Text(
                  'Wearing and carrying stay on the card. Turn this on to '
                  'edit the starting kit.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondary(context),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _enableRow(BuildContext context, Color amber) {
    return Row(
      children: [
        Icon(
          Icons.checkroom_outlined,
          color: pocketsEnabled! ? amber : AppColors.iconSecondary(context),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pockets & Wardrobe',
                style: TextStyle(
                  color: pocketsEnabled!
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'When off, this character skips inventory tracking even if '
                'Porch Life has Pockets on. Old cards stay on.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          key: enableKey,
          value: pocketsEnabled!,
          onChanged: onPocketsEnabledChanged!,
          activeTrackColor: amber.withValues(alpha: 0.5),
          activeThumbColor: amber,
        ),
      ],
    );
  }
}
