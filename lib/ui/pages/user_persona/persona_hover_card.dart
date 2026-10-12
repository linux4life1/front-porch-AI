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

// ═══════════════════════════════════════════════════════════════════════════
// Hover Scale Card — glassmorphic persona card with micro-animations
// ═══════════════════════════════════════════════════════════════════════════

class PersonaHoverScaleCard extends StatefulWidget {
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  const PersonaHoverScaleCard({
    super.key,
    required this.isActive,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  @override
  State<PersonaHoverScaleCard> createState() => _PersonaHoverScaleCardState();
}

class _PersonaHoverScaleCardState extends State<PersonaHoverScaleCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _borderAnimController;
  late Animation<double> _borderAnimation;

  @override
  void initState() {
    super.initState();
    _borderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _borderAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _borderAnimController, curve: Curves.linear),
    );
    if (widget.isActive) _borderAnimController.repeat();
  }

  @override
  void didUpdateWidget(covariant PersonaHoverScaleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_borderAnimController.isAnimating) {
      _borderAnimController.repeat();
    } else if (!widget.isActive && _borderAnimController.isAnimating) {
      _borderAnimController.stop();
      _borderAnimController.reset();
    }
  }

  @override
  void dispose() {
    _borderAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.025 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedBuilder(
            animation: _borderAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _isHovered
                      ? AppColors.resolve(
                          context,
                          const Color(0xFF1E293B),
                          AppColors.lightCard,
                        )
                      : AppColors.resolve(
                          context,
                          const Color(0xFF1E293B).withValues(alpha: 0.7),
                          AppColors.lightCard.withValues(alpha: 0.85),
                        ),
                  border: Border.all(
                    color: widget.isActive
                        ? widget.accentColor.withValues(
                            alpha: 0.35 + _borderAnimation.value * 0.15,
                          )
                        : _isHovered
                        ? AppColors.borderOf(context).withValues(alpha: 0.5)
                        : AppColors.borderOf(context),
                    width: widget.isActive ? 1.5 : 1,
                  ),
                  boxShadow: [
                    if (_isHovered || widget.isActive)
                      BoxShadow(
                        color: widget.isActive
                            ? widget.accentColor.withValues(alpha: 0.08)
                            : AppColors.resolve(
                                context,
                                Colors.white.withValues(alpha: 0.02),
                                Colors.black.withValues(alpha: 0.04),
                              ),
                        blurRadius: 16,
                        spreadRadius: -4,
                      ),
                  ],
                ),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
