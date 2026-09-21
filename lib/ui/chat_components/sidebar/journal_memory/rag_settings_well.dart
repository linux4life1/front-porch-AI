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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_tokens.dart';

/// Friendly RAG retrieval sliders for the Memory sidebar Settings well.
/// Labels say what the user gets, not the implementation name.
class RagSettingsWell extends StatefulWidget {
  final Color accent;

  const RagSettingsWell({super.key, required this.accent});

  @override
  State<RagSettingsWell> createState() => _RagSettingsWellState();
}

class _RagSettingsWellState extends State<RagSettingsWell> {
  double? _dragCount;
  double? _dragWindow;

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final accent = widget.accent;
    final count =
        (_dragCount ?? storage.memorySettings.ragRetrievalCount.toDouble())
            .round();
    final window =
        (_dragWindow ?? storage.memorySettings.ragWindowSize.toDouble())
            .round();

    return Container(
      padding: SidebarTokens.wellPadding,
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sliderHeader(
            context,
            title: 'Past moments per reply',
            valueLabel: count == 0 ? 'All' : '$count',
            hint: count == 0
                ? 'Bring back every strong match (can get long).'
                : 'How many old moments to weave into each reply.',
          ),
          SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value:
                  _dragCount ??
                  storage.memorySettings.ragRetrievalCount.toDouble(),
              min: 0,
              max: 50,
              divisions: 50,
              activeColor: accent,
              inactiveColor: AppColors.borderOf(context),
              onChanged: (val) => setState(() => _dragCount = val),
              onChangeEnd: (val) {
                _dragCount = null;
                storage.memorySettings.setRagRetrievalCount(val.round());
              },
            ),
          ),
          const SizedBox(height: 6),
          _sliderHeader(
            context,
            title: 'How much of a moment to keep',
            valueLabel: '$window messages',
            hint:
                'Each saved memory is a short stretch of chat. Larger keeps '
                'more of the original scene; smaller is tighter.',
          ),
          SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value:
                  _dragWindow ??
                  storage.memorySettings.ragWindowSize.toDouble(),
              min: 3,
              max: 10,
              divisions: 7,
              activeColor: accent,
              inactiveColor: AppColors.borderOf(context),
              onChanged: (val) => setState(() => _dragWindow = val),
              onChangeEnd: (val) {
                _dragWindow = null;
                storage.memorySettings.setRagWindowSize(val.round());
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 12, color: accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Private on this computer — uses a local embedding model, '
                  'not the cloud.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.35,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderHeader(
    BuildContext context, {
    required String title,
    required String valueLabel,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: widget.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(
            fontSize: 10,
            height: 1.3,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) =>
      SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      );
}
