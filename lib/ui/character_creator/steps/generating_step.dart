// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

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
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                state.generationStatus.isEmpty
                    ? 'Generating character...'
                    : state.generationStatus,
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null,
                  backgroundColor: AppColors.borderOf(context),
                  valueColor: AlwaysStoppedAnimation(
                    AppColors.porchAmberOf(context),
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 24),
              // Abort button
              if (state.isGenerating)
                SizedBox(
                  width: 200,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: state.abortGeneration,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    label: const Text(
                      'Abort Generation',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.resolve(
                        context,
                        Colors.redAccent,
                        Colors.red.shade700,
                      ),
                      side: BorderSide(
                        color: AppColors.resolve(
                          context,
                          Colors.redAccent,
                          Colors.red.shade700,
                        ),
                      ),
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
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      state.generationPreview,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
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
