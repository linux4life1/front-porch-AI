// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_style.dart';

/// The card's memory as a bar, part by part, with its legend below.
class KcppsMemoryBar extends StatelessWidget {
  const KcppsMemoryBar({super.key, required this.segments});

  final List<KoboldBarSegment> segments;

  @override
  Widget build(BuildContext context) {
    final shown = segments.where((s) => s.mb > 0).toList();
    final total = shown.fold(0, (sum, s) => sum + s.mb);
    final label =
        'Graphics memory: ${[for (final s in segments) s.legend].join(', ')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: label,
          image: true,
          child: ExcludeSemantics(
            child: Container(
              height: 40,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairlineOf(context, 0.12)),
              ),
              child: LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    for (final s in shown)
                      Expanded(
                        flex: s.mb,
                        child: _segment(
                          context,
                          s,
                          box.maxWidth * s.mb / (total == 0 ? 1 : total),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > 640
                ? 3
                : (box.maxWidth > 360 ? 2 : 1);
            final width = (box.maxWidth - 18 * (columns - 1)) / columns;
            return Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                for (final s in segments)
                  SizedBox(width: width, child: _legend(context, s)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _segment(BuildContext context, KoboldBarSegment s, double width) {
    final (fill, ink) = _colors(context, s.part);
    final fits = s.label.isNotEmpty && width >= s.label.length * 7.0 + 12;
    final text = fits
        ? Text(
            s.label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: keText(
              context,
              size: 12,
              weight: FontWeight.w700,
              color: ink,
            ),
          )
        : null;
    final striped =
        s.part == KoboldBarPart.unused || s.part == KoboldBarPart.over;
    final centered =
        s.part == KoboldBarPart.cache || s.part == KoboldBarPart.engine;
    return CustomPaint(
      painter: striped
          ? _Stripes(
              fill,
              s.part == KoboldBarPart.over
                  ? AppColors.loadOverStripe
                  : AppColors.loadUnusedStripeOf(context),
              s.part == KoboldBarPart.over ? 6 : 4,
            )
          : null,
      child: Container(
        color: striped ? null : fill,
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        padding: EdgeInsets.only(left: centered ? 0 : 8),
        child: text,
      ),
    );
  }

  Widget _legend(BuildContext context, KoboldBarSegment s) {
    final (fill, _) = _colors(context, s.part);
    final striped =
        s.part == KoboldBarPart.unused || s.part == KoboldBarPart.over;
    final over = s.part == KoboldBarPart.over;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: striped
                  ? SizedBox(
                      width: 10,
                      height: 10,
                      child: CustomPaint(
                        painter: _Stripes(
                          over ? AppColors.loadOver : AppColors.cardOf(context),
                          over
                              ? AppColors.loadOverStripe
                              : AppColors.loadUnusedStripeOf(context),
                          2,
                        ),
                      ),
                    )
                  : KeMark(fill),
            ),
          ),
          TextSpan(text: s.legend),
        ],
      ),
      style: keText(context, size: 13, color: AppColors.slateMutedOf(context)),
    );
  }

  (Color, Color) _colors(
    BuildContext context,
    KoboldBarPart part,
  ) => switch (part) {
    KoboldBarPart.model => (AppColors.porchAmber, AppColors.onPorchAmber),
    KoboldBarPart.experts => (AppColors.loadExperts, AppColors.onLoadExperts),
    KoboldBarPart.cache => (AppColors.journalAccent, AppColors.onJournalAccent),
    KoboldBarPart.working => (AppColors.loadWorking, AppColors.slateInk),
    KoboldBarPart.engine => (AppColors.loadEngine, AppColors.onLoadEngine),
    KoboldBarPart.unused => (AppColors.cardOf(context), AppColors.slateInk),
    KoboldBarPart.over => (AppColors.loadOver, AppColors.onLoadOver),
  };
}

/// Diagonal stripes: unused memory, or memory the model would need beyond
/// what is free.
class _Stripes extends CustomPainter {
  _Stripes(this.base, this.stripe, this.width);

  final Color base;
  final Color stripe;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width + size.height; x += width * 2) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Stripes old) =>
      old.base != base || old.stripe != stripe || old.width != width;
}
