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

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Remote host tiles: Nano-GPT, OpenRouter and xAI, each with a line
/// saying whether a key or a sign-in is ready. Every tile can be picked;
/// a host with no key shows the key field on the panel instead.
class RemoteImageHostChips extends StatelessWidget {
  const RemoteImageHostChips({
    super.key,
    required this.tiles,
    required this.onSelect,
  });

  final List<RemoteHostTile> tiles;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Remote host',
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _HostTile(tile: tiles[i], onSelect: onSelect),
            ),
          ],
        ],
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({required this.tile, required this.onSelect});

  final RemoteHostTile tile;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final selected = tile.selected;
    final fg = selected
        ? AppColors.onAccentOf(context)
        : AppColors.textPrimary(context);
    final sub = selected
        ? AppColors.onAccentOf(context)
        : tile.usable
        ? AppColors.textSecondary(context)
        : accent;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? accent : AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('image-remote-host-${tile.host.id}'),
          onTap: () => onSelect(tile.host.url),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : AppColors.borderOf(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tile.host.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(tile.sub, style: TextStyle(color: sub, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
