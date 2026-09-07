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

/// Grid tile that starts the folder → character wizard.
class WaifuNewPorchCard extends StatefulWidget {
  const WaifuNewPorchCard({super.key, required this.onTap, this.index = 0});

  final VoidCallback onTap;
  final int index;

  @override
  State<WaifuNewPorchCard> createState() => _WaifuNewPorchCardState();
}

class _WaifuNewPorchCardState extends State<WaifuNewPorchCard> {
  var _hot = false;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    final terra = AppColors.porchTerracottaOf(context);
    final delay = widget.index * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 480 + delay),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        final v = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: 0.86 + v * 0.14, child: child),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hot = true),
        onExit: (_) => setState(() => _hot = false),
        child: AnimatedScale(
          scale: _hot ? 1.05 : 1,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: amber.withValues(alpha: _hot ? 0.62 : 0.32),
                  blurRadius: _hot ? 28 : 16,
                  spreadRadius: _hot ? 2 : 0,
                ),
                BoxShadow(
                  color: honey.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _DashFramePainter(
                color: _hot ? amber : honey,
                fill: [
                  amber.withValues(alpha: _hot ? 0.38 : 0.22),
                  terra.withValues(alpha: 0.16),
                  AppColors.cardOf(context),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('waifu-sit-down'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: widget.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [amber, honey, terra],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: amber.withValues(alpha: 0.55),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            size: 44,
                            color: AppColors.onChaosAccent,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'New porch',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Folder, then character',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: honey,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
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

class _DashFramePainter extends CustomPainter {
  const _DashFramePainter({required this.color, required this.fill});

  final Color color;
  final List<Color> fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fill,
        ).createShader(rect),
    );
    final path = Path()..addRRect(rrect.deflate(1.2));
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        dashed.addPath(metric.extractPath(d, d + 9), Offset.zero);
        d += 16;
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DashFramePainter old) =>
      old.color != color || old.fill != fill;
}
