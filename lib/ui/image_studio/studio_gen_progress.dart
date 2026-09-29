// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Sampling progress on the stove. Comfy reports step fraction; the
/// remaining time is estimated from how long that fraction took.
class StudioGenProgress extends StatefulWidget {
  const StudioGenProgress({super.key});

  @override
  State<StudioGenProgress> createState() => _StudioGenProgressState();
}

class _StudioGenProgressState extends State<StudioGenProgress> {
  DateTime? _started;

  String _eta(double progress) {
    final started = _started;
    if (started == null || progress <= 0.02 || progress >= 1) return '';
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    final leftMs = (elapsed / progress) - elapsed;
    if (leftMs < 1000) return 'Almost done';
    final left = Duration(milliseconds: leftMs.round());
    if (left.inMinutes >= 1) {
      return 'About ${left.inMinutes} min ${left.inSeconds % 60} s left';
    }
    return 'About ${left.inSeconds} s left';
  }

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondary(context);
    return Consumer<ImageGenService>(
      builder: (context, igs, _) {
        if (igs.isGenerating) {
          _started ??= DateTime.now();
        } else {
          _started = null;
        }
        final progress = igs.genProgress;
        final eta = progress == null ? '' : _eta(progress);
        final label = progress == null
            ? (igs.statusMessage.isEmpty
                  ? 'Sending the graph to ComfyUI…'
                  : igs.statusMessage)
            : 'Painting… ${(progress * 100).round()}%';
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  color: AppColors.formMasterAccent,
                ),
              ),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(color: secondary, fontSize: 13)),
              if (eta.isNotEmpty)
                Text(eta, style: TextStyle(color: secondary, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
