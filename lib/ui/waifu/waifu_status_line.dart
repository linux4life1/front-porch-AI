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

/// "Mira is running tests…" above the composer while a turn runs. Lives in
/// the chat column so it shows with the sidebar closed.
class WaifuStatusLine extends StatelessWidget {
  const WaifuStatusLine({super.key, required this.session});

  final WaifuSession session;

  @override
  Widget build(BuildContext context) {
    final line = waifuStatusLine(session);
    if (line == null) return const SizedBox.shrink();
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: amber),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line,
              key: const Key('waifu-status-line'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
