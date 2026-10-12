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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Live captions. While they speak, the EXACT sentence the speaker is
/// voicing right now ([TtsService.nowSpeaking] — published by the
/// streaming consumer as it plays, not as text generates, so the caption
/// never runs ahead of the audio). Otherwise, what the mic last heard
/// from you — so a bad transcription is visible before the reply lands.
class CallCaptionArea extends StatelessWidget {
  const CallCaptionArea({super.key, required this.stt, required this.tts});

  final SttService stt;
  final TtsService tts;

  @override
  Widget build(BuildContext context) {
    final speaking = tts.nowSpeaking;
    final heard = stt.lastTranscription;
    final Widget child;
    if (speaking != null && speaking.isNotEmpty) {
      child = _captionCard(
        context,
        key: const ValueKey('caption_speaking'),
        icon: Icons.graphic_eq,
        color: AppColors.porchTerracottaOf(context),
        text: speaking,
      );
    } else if (heard != null && heard.isNotEmpty) {
      child = _captionCard(
        context,
        key: const ValueKey('caption_heard'),
        icon: Icons.record_voice_over,
        color: AppColors.textTertiary(context),
        text: '"$heard"',
      );
    } else {
      child = const SizedBox(key: ValueKey('caption_none'), height: 40);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
    );
  }

  Widget _captionCard(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context).withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
