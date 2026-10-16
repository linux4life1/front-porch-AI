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
import 'package:flutter/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/porch_snack_bar.dart';

/// The app version as shown in the sidebar footer. Tapping it copies the
/// exact string, so testers can paste it into a bug report.
class VersionChip extends StatelessWidget {
  const VersionChip({super.key, required this.version});

  final String version;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: version));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(porchSnackBar(context, 'Copied $version'));
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textTertiary(context);
    return Semantics(
      button: true,
      label: 'Copy app version $version',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Copy version',
        child: InkWell(
          onTap: () => _copy(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    version,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.content_copy, size: 13, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
