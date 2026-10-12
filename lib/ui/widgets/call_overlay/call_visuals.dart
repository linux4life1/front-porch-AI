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

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/call_overlay/call_status_chip.dart';

/// The character's portrait in a status-coloured ring that pulses with the
/// mic amplitude while listening or speaking.
class CallAvatar extends StatelessWidget {
  const CallAvatar({
    super.key,
    required this.pulse,
    required this.character,
    required this.status,
    required this.amp,
    required this.size,
  });

  final Animation<double> pulse;
  final CharacterCard character;
  final CallStatus status;
  final double amp;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isActive =
        status == CallStatus.listening || status == CallStatus.speaking;
    final ring = callStatusColor(context, status);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final pulseScale = isActive
            ? 1.0 + (pulse.value * 0.04) + (amp * 0.08)
            : 1.0;
        return Transform.scale(
          scale: pulseScale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ring.withValues(alpha: isActive ? 0.3 : 0.1),
                  blurRadius: isActive ? 40 + amp * 20 : 20,
                  spreadRadius: isActive ? 4 + amp * 8 : 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    ring.withValues(alpha: 0.6),
                    ring.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CircleAvatar(
                radius: size / 2 - 4,
                backgroundColor: AppColors.surfaceContainerOf(context),
                backgroundImage: character.imagePath != null
                    ? FileImage(File(character.imagePath!))
                    : null,
                child: character.imagePath == null
                    ? Text(
                        character.name.isNotEmpty
                            ? character.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: size * 0.3,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary(context),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Nine bars that ride the mic amplitude while listening and a gentle sine
/// while speaking.
class CallWaveform extends StatelessWidget {
  const CallWaveform({
    super.key,
    required this.wave,
    required this.amp,
    required this.status,
  });

  final Animation<double> wave;
  final double amp;
  final CallStatus status;

  @override
  Widget build(BuildContext context) {
    final isListening = status == CallStatus.listening;
    final color = callStatusColor(context, status);
    const barCount = 9;
    return AnimatedBuilder(
      animation: wave,
      builder: (context, _) {
        return SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(barCount, (i) {
              final phase = (i / barCount * 2 * pi) + (wave.value * 2 * pi);
              final waveHeight = isListening
                  ? 0.3 + (sin(phase) * 0.3 + 0.3) * amp
                  : (status == CallStatus.speaking)
                  ? 0.2 + sin(phase) * 0.3
                  : 0.15;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 4,
                  height: 8 + (waveHeight * 52),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        color.withValues(alpha: 0.8),
                        color.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
