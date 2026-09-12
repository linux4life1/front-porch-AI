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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WaifuMcpOptIn extends StatelessWidget {
  const WaifuMcpOptIn({
    super.key,
    required this.value,
    required this.onChanged,
    this.pathMode = WaifuPathMode.folderJail,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final WaifuPathMode pathMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            key: const Key('waifu-mcp-opt-in'),
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Let them use MCP',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (value)
            Text(
              waifuMcpScopeWarning(pathMode),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}
