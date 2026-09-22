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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Honest library-tools opt-in. Not Docker, not extra MCP servers.
class WaifuLibraryToolsTile extends StatelessWidget {
  const WaifuLibraryToolsTile({
    super.key,
    required this.session,
    this.onChanged,
  });

  final WaifuSession session;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    String toolsPath = 'tools';
    String skillsPath = 'skills';
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      if (storage.rootPath != null) {
        toolsPath = '${storage.rootPath}/tools';
        skillsPath = '${storage.rootPath}/skills';
      }
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: const Key('waifu-tools-opt-in'),
            value: session.mcpOptIn,
            onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Use library tools',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            subtitle: Text(
              'Same JSON recipe cards as character chat, from $toolsPath. '
              'Takes effect at the next sit-down.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4, bottom: 4),
            child: Text(
              'Waifu-only skills live in $skillsPath as '
              '<name>/SKILL.md folders. Chat does not load them. Skill '
              'permission follows Ask, or Allow in Yolo.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
