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

/// Stage directions under a bubble: centred italic narration, no avatar.
/// The plain technical line folds underneath and opens on tap.
class WaifuStageLines extends StatelessWidget {
  const WaifuStageLines({super.key, required this.lines});

  final List<WaifuMessage> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final m in lines) _WaifuStageLine(message: m)],
      ),
    );
  }
}

class _WaifuStageLine extends StatefulWidget {
  const _WaifuStageLine({required this.message});

  final WaifuMessage message;

  @override
  State<_WaifuStageLine> createState() => _WaifuStageLineState();
}

class _WaifuStageLineState extends State<_WaifuStageLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.message.detail?.trim() ?? '';
    final muted = AppColors.textTertiary(context);
    final line = Text(
      widget.message.text,
      key: const Key('waifu-stage-line'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        color: AppColors.textSecondary(context),
      ),
    );
    if (detail.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 2), child: line);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('waifu-stage-toggle'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: line),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                detail,
                key: const Key('waifu-stage-detail'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
