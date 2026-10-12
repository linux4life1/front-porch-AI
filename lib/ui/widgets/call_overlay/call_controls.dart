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

/// Mute, Send (only while listening with the mic open) and End.
class CallControls extends StatelessWidget {
  const CallControls({super.key, required this.stt, required this.onEnd});

  final SttService stt;

  /// Tears the call down and leaves the overlay.
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final isMuted = stt.call.isMuted;
    final canSend = stt.call.status == CallStatus.listening && stt.isRecording;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _controlButton(
          context,
          icon: isMuted ? Icons.mic_off : Icons.mic,
          label: isMuted ? 'Unmute' : 'Mute',
          color: isMuted
              ? AppColors.porchHoneyOf(context)
              : AppColors.textSecondary(context),
          onTap: () => stt.call.toggleMute(),
        ),
        const SizedBox(width: 32),
        if (canSend) ...[
          _controlButton(
            context,
            icon: Icons.send,
            label: 'Send',
            color: AppColors.porchAmberOf(context),
            size: 64,
            onTap: () => stt.call.sendNow(),
          ),
          const SizedBox(width: 32),
        ],
        _controlButton(
          context,
          icon: Icons.call_end,
          label: 'End',
          // End-call red rides the shared AppColors red accent (bondNeg) —
          // universal live-call semantics, not new off-palette chrome.
          color: AppColors.bondNegOf(context),
          onTap: onEnd,
        ),
      ],
    );
  }

  Widget _controlButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
