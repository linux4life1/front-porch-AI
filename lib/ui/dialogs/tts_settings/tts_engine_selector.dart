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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// TTS engine selector — the segmented control (Kokoro/OpenAI/ElevenLabs/
/// Piper) shown at the top of the TTS settings dialog.
class TtsEngineSelector extends StatelessWidget {
  const TtsEngineSelector({
    super.key,
    required this.selectedEngine,
    required this.onSelected,
  });

  final String selectedEngine;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _engineTab(context, 'kokoro', '🔊 Kokoro', 'Local'),
          _engineTab(context, 'openai', '☁️ OpenAI', 'Cloud API'),
          _engineTab(context, 'elevenlabs', '🎙 ElevenLabs', 'Premium'),
          _engineTab(context, 'piper', '📦 Piper', 'Lightweight'),
        ],
      ),
    );
  }

  Widget _engineTab(
    BuildContext context,
    String id,
    String label,
    String subtitle,
  ) {
    final selected = selectedEngine == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelected(id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.formMasterAccent.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: AppColors.formMasterAccent, width: 1)
                : null,
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppColors.formMasterAccent
                      : AppColors.textSecondary(context),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  // Slightly brighter when selected, matching the original
                  // white38-vs-white24 hierarchy but on the AppColors scale.
                  color: selected
                      ? AppColors.textSecondary(context)
                      : AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
