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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart'
    show pocketsEnabledOf;
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// The Pockets & Wardrobe on/off line for one tracked character of this
/// chat — the 1:1 leaf header and each group member card's pockets block
/// (docs/design/pockets-wardrobe-chat-toggle.md). NeedsLine's shape: the
/// switch sits on the line it controls, greys with an explanatory note
/// while Porch Life vetoes, and keeps the chat's own choice meanwhile.
///
/// Turning OFF is the only guarded direction: there is no catch-up
/// mechanic, so the user confirms the freeze first (same popup in groups
/// as 1:1, with the member's name in it) and the switch flips only on
/// Yes. The Switch is value-bound, so a dismissed dialog needs no
/// rollback. Turning ON is instant: enabling seeds the card's starting kit
/// once when the chat holds no record (the setter's rule), and never
/// retro-scan the history.
class PocketsGateLine extends StatelessWidget {
  const PocketsGateLine({
    super.key,
    required this.chat,
    required this.characterId,
    required this.characterName,
    this.compact = false,
  });

  final ChatService chat;
  final String characterId;
  final String characterName;

  /// Member-card spacing (the roster card keeps its rows tight).
  final bool compact;

  Future<void> _confirmOff(BuildContext context) async {
    final named = characterName.trim();
    final whose = named.isEmpty ? 'your character' : "$named’s";
    final confirmed = await showWarmDialog<bool>(
      context,
      title: named.isEmpty
          ? 'Turn off Pockets & Wardrobe?'
          : 'Turn off Pockets & Wardrobe for $named?',
      icon: Icons.inventory_2_outlined,
      destructive: true,
      content: WarmDialogText(
        'There is no catch-up mechanic implemented. If you turn this off, '
        "$whose current inventory and wardrobe will be retained but no "
        'longer tracked — changes in the chat will not be reflected when '
        'you turn it back on. Are you sure you want to do this?',
      ),
      actions: [
        Builder(
          builder: (ctx) =>
              warmDialogCancel(ctx, label: 'No, keep on', value: false),
        ),
        Builder(
          builder: (ctx) => warmDialogConfirm(
            ctx,
            label: 'Yes, turn off',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    await _write(false);
  }

  Future<void> _write(bool on) async {
    // The instance the parent mounted this line with (it watches the
    // provider); Provider.of here would throw on the provider-less pumps
    // this card survives, for nothing — `chat` is the live service.
    if (chat.isGroupMode) {
      await chat.setMemberPocketsEnabled(characterId, on);
    } else {
      await chat.setPocketsEnabled(on);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Shared forgiving read (bare member-card pumps have no
    // StorageService above them; identity_chip_lists.pocketsEnabledOf).
    final allowed = pocketsEnabledOf(context);
    final accent = AppColors.porchTerracottaOf(context);
    final on = chat.pocketsSwitchFor(characterId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 14,
              color: allowed ? accent : AppColors.textTertiary(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pockets & Wardrobe',
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: allowed
                      ? AppColors.textPrimary(context)
                      : AppColors.textTertiary(context),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  // The STORED switch, not the live gate: under a Porch
                  // Life veto the checkbox shows the chat's own choice,
                  // greyed, exactly like Needs.
                  value: on,
                  activeThumbColor: accent,
                  onChanged: !allowed || chat.isGenerating
                      ? null
                      : (val) =>
                            val ? _write(true) : _confirmOff(context),
                ),
              ),
            ),
          ],
        ),
        if (!allowed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Pockets & Wardrobe is off in Porch Life. This chat keeps its '
              'own choice for when it comes back.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          )
        else if (!on)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              characterName.trim().isEmpty
                  ? 'Inventory retained, not tracked. Turn it back on to '
                        'follow the story again.'
                  : '$characterName\'s inventory is retained, not tracked. '
                        'Turn it back on to follow the story again.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
      ],
    );
  }
}
