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

import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../widgets/eval_pill.dart';

class ObjectiveCheckOverlay extends StatefulWidget {
  final ChatService chatService;

  const ObjectiveCheckOverlay({super.key, required this.chatService});

  @override
  State<ObjectiveCheckOverlay> createState() => ObjectiveCheckOverlayState();
}

class ObjectiveCheckOverlayState extends State<ObjectiveCheckOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;
  late final Animation<double> _pulse;
  late final Animation<double> _rotate;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _rotate = CurvedAnimation(parent: _rotateController, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Colors.greenAccent;
    const accentColorDim = Color(0xFF16A34A);

    final pills = <EvalPill>[
      EvalPill(
        label: 'Objective',
        icon: Icons.flag,
        color: AppColors.resolve(
          context,
          Colors.greenAccent,
          AppColors.resolve(
            context,
            const Color(0xFF16A34A),
            const Color(0xFF15803D),
          ),
        ),
      ),
      EvalPill(
        label: 'Progress',
        icon: Icons.trending_up,
        color: AppColors.resolve(
          context,
          Colors.tealAccent,
          const Color(0xFF0D9488),
        ),
      ),
      EvalPill(
        label: 'Completion',
        icon: Icons.check_circle_outline,
        color: AppColors.resolve(
          context,
          Colors.lightGreenAccent,
          const Color(0xFF4ADE80),
        ),
      ),
    ];

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          type: MaterialType.transparency,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 680,
                    maxHeight: 580,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0F1729).withValues(alpha: 0.97),
                          const Color(0xFF080D1A).withValues(alpha: 0.99),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.18),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.7),
                          blurRadius: 60,
                          offset: const Offset(0, 24),
                        ),
                        BoxShadow(
                          color: accentColorDim.withValues(alpha: 0.12),
                          blurRadius: 80,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header ───────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: accentColor.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Animated orb with spinning ring
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, _) => Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        accentColor.withValues(
                                          alpha: 0.45 + 0.2 * _pulse.value,
                                        ),
                                        accentColorDim.withValues(alpha: 0.06),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withValues(
                                          alpha: 0.2 + 0.18 * _pulse.value,
                                        ),
                                        blurRadius: 20 + 12 * _pulse.value,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      RotationTransition(
                                        turns: _rotate,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: accentColor.withValues(
                                                alpha: 0.3,
                                              ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.flag,
                                        color: accentColor,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Objective Engine',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Evaluating objective & task completion',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white38,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: accentColor.withValues(alpha: 0.6),
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Eval Pills ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: pills
                                .map(
                                  (p) => AnimatedEvalPill(
                                    pill: p,
                                    pulseAnimation: _pulse,
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                        // ── Body ──────────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, _) => Text(
                              'Reviewing recent conversation to determine\nif objectives or tasks have been fulfilled...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(
                                  alpha: 0.22 + 0.12 * _pulse.value,
                                ),
                                height: 1.65,
                              ),
                            ),
                          ),
                        ),
                        // Stops only this check; the reply still comes.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                          child: OutlinedButton.icon(
                            onPressed: widget.chatService.skipObjectiveCheck,
                            icon: const Icon(Icons.skip_next, size: 18),
                            label: const Text('Skip goal check'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.formMasterAccent,
                              side: BorderSide(
                                color: AppColors.formMasterAccent.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
