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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_scope_badge.dart';

/// Always-visible AppBar title: mode, jail/disk, basename, and full path.
class WaifuSessionChrome extends StatelessWidget {
  const WaifuSessionChrome({super.key, required this.session});

  final WaifuSession session;

  @override
  Widget build(BuildContext context) {
    final folderName = p.basename(session.folderRoot);
    final title = session.title.isEmpty ? session.coworker.name : session.title;
    return Column(
      key: const Key('waifu-session-chrome'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WaifuModeBadge(
              key: const Key('waifu-appbar-mode'),
              mode: session.mode,
            ),
            IgnorePointer(
              child: WaifuScopeBadge(
                key: const Key('waifu-appbar-scope'),
                pathMode: session.pathMode,
              ),
            ),
            Text(
              folderName,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        Text(
          session.folderRoot,
          key: const Key('waifu-appbar-path'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }
}

/// Honest tools-unsupported strip. Send still fail-closes if they try.
class WaifuToolsUnsupportedBanner extends StatelessWidget {
  const WaifuToolsUnsupportedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('waifu-tools-unsupported-banner'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        kWaifuToolsUnsupported,
        style: TextStyle(
          color: AppColors.negativeAccentOf(context),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
