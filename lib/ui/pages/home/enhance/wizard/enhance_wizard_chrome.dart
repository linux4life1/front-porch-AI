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

// Wizard chrome for EnhanceWizardPage: the creator-pattern step indicator +
// per-step nav buttons, and the shared step scaffolding (scroll frame,
// headings, callouts) the step bodies compose.

/// The centered, width-capped scrolling column every text step sits in.
class EnhanceStepScroll extends StatelessWidget {
  const EnhanceStepScroll({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A step's title line.
class EnhanceStepHeading extends StatelessWidget {
  const EnhanceStepHeading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }
}

/// A step's explanatory paragraph.
class EnhanceStepBody extends StatelessWidget {
  const EnhanceStepBody({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

/// A tinted, bordered note with a leading icon; amber unless [accent].
class EnhanceCallout extends StatelessWidget {
  const EnhanceCallout({
    super.key,
    required this.icon,
    required this.text,
    this.accent,
  });

  final IconData icon;
  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.porchAmberOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step indicator — exact pattern from character_creator_page.dart
/// (horizontal dots + labels + connecting lines in the AppBar, driven by
/// the current step int; the mandated wizard chrome).
class EnhanceStepIndicator extends StatelessWidget {
  const EnhanceStepIndicator({
    super.key,
    required this.labels,
    required this.currentStep,
  });

  final List<String> labels;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) _stepLine(context),
          _stepDot(context, i, labels[i]),
        ],
      ],
    );
  }

  Widget _stepDot(BuildContext context, int step, String label) {
    final isActive = currentStep >= step;
    final isCurrent = currentStep == step;
    final dotColor = isActive
        ? AppColors.porchAmberOf(context)
        : AppColors.surfaceContainerOf(context);
    final numberOrCheckColor = isActive
        ? AppColors.onChaosAccent
        : AppColors.textTertiary(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: isCurrent
                ? Border.all(color: AppColors.textPrimary(context), width: 2)
                : Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? Icon(Icons.check, size: 14, color: numberOrCheckColor)
                : Text(
                    '${step + 1}',
                    style: TextStyle(fontSize: 11, color: numberOrCheckColor),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive
                ? AppColors.textSecondary(context)
                : AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _stepLine(BuildContext context) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }
}

/// The only control while the interview runs: Cancel.
class EnhanceWizardCancelBar extends StatelessWidget {
  const EnhanceWizardCancelBar({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Center(
        child: SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancel', style: TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              side: BorderSide(color: AppColors.borderOf(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom nav — modeled exactly on character_creator_page.dart: an optional
/// Back and the step's primary action ([nextLabel] / [nextIcon] / [onNext],
/// null greys it out). [saving] swaps the primary icon for a spinner.
class EnhanceWizardNavBar extends StatelessWidget {
  const EnhanceWizardNavBar({
    super.key,
    required this.showBack,
    required this.onBack,
    required this.saving,
    required this.nextLabel,
    required this.nextIcon,
    required this.onNext,
  });

  final bool showBack;
  final VoidCallback onBack;
  final bool saving;
  final String nextLabel;
  final IconData nextIcon;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (showBack) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onNext,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(nextIcon, size: 20),
                label: Text(nextLabel, style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.porchAmberOf(context),
                  foregroundColor: AppColors.onChaosAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
