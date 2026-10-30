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

import 'package:front_porch_ai/ui/theme/theme.dart';

import 'create_group_chat_page.dart';

/// Page-owned side effects the wizard steps trigger (snackbars, navigation,
/// LLM generation, persistence). The page holds `context` and `mounted`.
class GroupWizardActions {
  const GroupWizardActions({
    required this.showSnack,
    required this.createGroup,
    required this.generateScenario,
    required this.generateFirstMessage,
  });

  final void Function(String message) showSnack;
  final Future<void> Function({bool enterChat}) createGroup;
  final Future<void> Function({String dynamicsContext}) generateScenario;
  final Future<void> Function({String dynamicsContext}) generateFirstMessage;
}

// ═══════════════════════════════════════════════════════════════
//  STEP INDICATOR (matches Manual Character Creator style)
// ═══════════════════════════════════════════════════════════════

class GroupWizardStepIndicator extends StatelessWidget {
  const GroupWizardStepIndicator({super.key, required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const labels = GroupWizardSteps.labels;

    final children = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      children.add(_stepDot(context, i, labels[i]));
      if (i < labels.length - 1) {
        children.add(_stepLine(context));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _stepDot(BuildContext context, int step, String label) {
    final isActive = currentStep >= step;
    final isCurrent = currentStep == step;

    final dotColor = isActive
        ? AppColors.porchAmberOf(context)
        : AppColors.surfaceContainerOf(context);

    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);

    final numberOrCheckColor = isActive
        ? StatusColors.onFill
        : AppColors.textTertiary(context);

    final labelColor = isActive
        ? AppColors.textSecondary(context)
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
                ? Border.all(color: borderColor, width: 2)
                : Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: StatusColors.onFill)
                : Text(
                    '${step + 1}',
                    style: TextStyle(fontSize: 11, color: numberOrCheckColor),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
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

// ═══════════════════════════════════════════════════════════════
//  NAVIGATION BUTTONS (matches Manual Character Creator)
// ═══════════════════════════════════════════════════════════════

class GroupWizardNavButtons extends StatelessWidget {
  const GroupWizardNavButtons({
    super.key,
    required this.draft,
    required this.actions,
    required this.currentStep,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final effectiveNextStep = draft.effectiveNextStep(currentStep);
    final isLastStep = effectiveNextStep == null;

    final nextText = isLastStep ? 'Create Group' : 'Next';

    final canGoNext = draft.canAdvanceFromStep(currentStep);

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentStep > 0)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => draft.goToPreviousStep(currentStep),
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
            if (currentStep > 0) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: canGoNext
                    ? () {
                        if (currentStep == 0 && !draft.canLeaveMembersStep) {
                          actions.showSnack(
                            'A group needs at least 2 characters.',
                          );
                          return;
                        }
                        if (isLastStep) {
                          actions
                              .createGroup(); // defaults to enterChat: true (primary action)
                        } else {
                          draft.goToStep(effectiveNextStep);
                        }
                      }
                    : null,
                icon: Icon(
                  isLastStep ? Icons.check : Icons.arrow_forward,
                  size: 20,
                ),
                label: Text(nextText, style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.porchAmberOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: AppColors.borderOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GroupTokenBadge extends StatelessWidget {
  const GroupTokenBadge({super.key, required this.estimate});

  final int estimate;

  @override
  Widget build(BuildContext context) {
    final color = estimate > 6000
        ? StatusColors.dangerOf(context)
        : estimate > 3000
        ? StatusColors.warningOf(context)
        : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '~$estimate tokens',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}
