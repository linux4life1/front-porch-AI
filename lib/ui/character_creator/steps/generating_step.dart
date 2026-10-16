// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Generating step: spinning icon, status, progress bar, abort, live preview.
class GeneratingStep extends StatefulWidget {
  final CreatorState state;

  const GeneratingStep({super.key, required this.state});

  @override
  State<GeneratingStep> createState() => _GeneratingStepState();
}

class _GeneratingStepState extends State<GeneratingStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Center(
      key: const ValueKey('generating'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // Animated icon
              RotationTransition(
                turns: _spin,
                child: Icon(
                  Icons.auto_awesome,
                  size: 64,
                  color: StudioColors.amberOf(context),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                state.generationStatus.isEmpty
                    ? 'Generating character...'
                    : state.generationStatus,
                style: TextStyle(
                  fontSize: 18,
                  color: StudioColors.inkOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null,
                  backgroundColor: StudioColors.lineOf(context),
                  valueColor: AlwaysStoppedAnimation(
                    StudioColors.amberOf(context),
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 24),
              // Abort button
              if (state.isGenerating)
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: state.abortGeneration,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text(
                      'Abort Generation',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // The outlined action's shape in `bad`, like Stop.
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StudioColors.badOf(context),
                      side: BorderSide(
                        color: StudioColors.badOf(context),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Live preview of generation
              if (state.generationPreview.isNotEmpty)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: StudioColors.bgOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StudioColors.lineOf(context)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      state.generationPreview,
                      style: TextStyle(
                        color: StudioColors.proseOf(context),
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
