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

/// `/` palette above the composer. Matching prefix is amber; blurb is the
/// tooltip-style description.
class WaifuSlashMenu extends StatelessWidget {
  const WaifuSlashMenu({
    super.key,
    required this.matches,
    required this.prefix,
    required this.onPick,
  });

  final List<WaifuSlashCommand> matches;
  final String prefix;
  final ValueChanged<WaifuSlashCommand> onPick;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    final amber = AppColors.porchAmberOf(context);
    return Container(
      key: const Key('waifu-slash-menu'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.55)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: matches.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: AppColors.borderOf(context).withValues(alpha: 0.35),
        ),
        itemBuilder: (context, i) {
          final c = matches[i];
          return Tooltip(
            message: c.blurb,
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              key: Key('waifu-slash-${c.name}'),
              onTap: () => onPick(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 148,
                      child: _hint(c.hint, prefix, amber, context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.blurb,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hint(String hint, String prefix, Color amber, BuildContext context) {
    final body = hint.startsWith('/') ? hint.substring(1) : hint;
    final p = prefix.toLowerCase();
    final name = body.split(' ').first;
    final rest = body.substring(name.length);
    final hi = name.length >= p.length ? p.length : name.length;
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppColors.textPrimary(context),
        ),
        children: [
          const TextSpan(text: '/'),
          TextSpan(
            text: name.substring(0, hi),
            style: TextStyle(color: amber),
          ),
          TextSpan(text: name.substring(hi) + rest),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
