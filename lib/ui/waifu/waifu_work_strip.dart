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

const kWaifuWorkStripMaxHeight = 180.0;
const kWaifuWorkStripMaxLines = 8;
const kWaifuWorkStripMaxChars = 400;

/// Last-write preview. Whole files must not grow the chat column.
String waifuClipWorkPreview(String raw) {
  if (raw.isEmpty) return raw;
  var t = raw;
  final lines = t.split('\n');
  if (lines.length > kWaifuWorkStripMaxLines) {
    t = '${lines.take(kWaifuWorkStripMaxLines).join('\n')}\n…';
  }
  if (t.length > kWaifuWorkStripMaxChars) {
    t = '${t.substring(0, kWaifuWorkStripMaxChars).trimRight()}…';
  }
  return t;
}

/// Last write this turn — before/after so the user can see what she did.
class WaifuWorkStrip extends StatelessWidget {
  const WaifuWorkStrip({super.key, required this.record, this.onClose});

  final WaifuWriteRecord record;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final before = record.before.isEmpty
        ? '(new file)'
        : waifuClipWorkPreview(record.before);
    final after = waifuClipWorkPreview(record.after);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: kWaifuWorkStripMaxHeight),
      child: Container(
        key: const Key('waifu-work-strip'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: amber.withValues(alpha: 0.45)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Last write: ${record.relativePath}',
                      style: TextStyle(
                        color: amber,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      key: const Key('waifu-work-strip-close'),
                      tooltip: 'Dismiss',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.iconSecondary(context),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Before',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
              Text(
                before,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'After',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
              Text(
                after,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
