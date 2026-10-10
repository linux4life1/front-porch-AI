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
//
// Group wizard: the review step, the top step indicator, and the shared
// back/next nav buttons.
// Extracted verbatim from create_group_chat_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so every private member and the
// mandatory wizard step-indicator flow stay exactly as they were.

part of 'create_group_chat_page.dart';

extension _GroupWizardReviewStep on _CreateGroupChatPageState {
  Widget _buildReviewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review & Opening',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Scenario + First Message moved here (last step) so AI generation
          // can use the hidden relationships from the Group Dynamics step.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Scenario (optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final dynamics = _buildDynamicsContextForGeneration();
                  await _generateScenario(dynamicsContext: dynamics);
                },
                icon: _isGeneratingScenario
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: AppColors.resolve(
                          context,
                          Colors.amberAccent,
                          Colors.amber.shade700,
                        ),
                      ),
                label: Text(
                  _isGeneratingScenario
                      ? 'Generating...'
                      : 'Generate with Dynamics',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _scenarioController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'The group is...'),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  'First Message (optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final dynamics = _buildDynamicsContextForGeneration();
                  await _generateFirstMessage(dynamicsContext: dynamics);
                },
                icon: _isGeneratingFirst
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: AppColors.resolve(
                          context,
                          Colors.amberAccent,
                          Colors.amber.shade700,
                        ),
                      ),
                label: Text(
                  _isGeneratingFirst
                      ? 'Generating...'
                      : 'Generate with Dynamics',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _firstMessageController,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'The scene opens with...',
            ),
          ),
          const SizedBox(height: 8),
          if (_directorMode)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.resolve(
                  context,
                  Colors.amber.withValues(alpha: 0.08),
                  Colors.amber.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Director Mode: generated opening will be a self-contained group scene.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Single group summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.isEmpty
                      ? 'Unnamed Group'
                      : _nameController.text,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _members
                      .map((c) => Chip(label: Text(c.name)))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_members.length} members • ${_groupLoreEntries.length} lore entries • ${_worldIds.length} worlds',
                ),
                if (_chaosModeEnabled)
                  Text(
                    'Chaos Mode enabled',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        const Color(0xFFFFD166),
                        const Color(0xFFB45309),
                      ),
                    ),
                  ),
                if (_directorMode)
                  Text(
                    'Director Mode',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        Colors.amberAccent,
                        Colors.amber.shade700,
                      ),
                    ),
                  ),
                Text(
                  _realismEnabled
                      ? 'Realism Engine: Enabled for group'
                      : 'Realism Engine: Disabled for group',
                  style: TextStyle(
                    color: _realismEnabled
                        ? AppColors.resolve(
                            context,
                            Colors.tealAccent,
                            Colors.teal.shade700,
                          )
                        : AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: () => _createGroup(enterChat: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.porchAmberOf(context),
              foregroundColor: AppColors.onChaosAccent,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.check),
            label: const Text(
              'Create Group & Enter Chat',
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _createGroup(enterChat: false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Create Only (don\'t enter chat yet)'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP INDICATOR (matches Manual Character Creator style)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStepIndicator() {
    final labels = [
      'Members',
      'Identity',
      'Prompts',
      'Lore',
      'Realism',
      'Group Dynamics',
      'Opening',
      'Review',
    ];

    final children = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      final isDynamicsStep = (i == 6);
      final isAvailable = !isDynamicsStep || _members.length <= 4;

      children.add(_stepDot(i, labels[i], available: isAvailable));
      if (i < labels.length - 1) {
        children.add(_stepLine());
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _stepDot(int step, String label, {bool available = true}) {
    final isActive = available && _currentStep >= step;
    final isCurrent = _currentStep == step;

    final dotColor = !available
        ? AppColors.surfaceContainerOf(context).withValues(alpha: 0.5)
        : (isActive
              ? AppColors.porchAmberOf(context)
              : AppColors.surfaceContainerOf(context));

    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);

    final numberOrCheckColor = isActive
        ? Colors.white
        : AppColors.textTertiary(context);

    final labelColor = !available
        ? AppColors.textTertiary(context).withValues(alpha: 0.6)
        : (isActive
              ? AppColors.textSecondary(context)
              : AppColors.textTertiary(context));

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
                ? const Icon(Icons.check, size: 14, color: Colors.white)
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

  Widget _stepLine() {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  NAVIGATION BUTTONS (matches Manual Character Creator)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavButtons({required int currentStep}) {
    final effectiveNextStep = _getEffectiveNextStep(currentStep);
    final isLastStep = effectiveNextStep == null;

    String nextText;
    if (isLastStep) {
      nextText = 'Create Group';
    } else if (effectiveNextStep == 6 && _members.length > 4) {
      nextText = 'Skip to Review';
    } else {
      nextText = 'Next';
    }

    final canGoNext = _canAdvanceFromStep(currentStep);

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
                  onPressed: () => _goToPreviousStep(currentStep),
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
                        if (currentStep == 0 && !_canLeaveMembersStep) {
                          _showSnack('A group needs at least 2 characters.');
                          return;
                        }
                        if (isLastStep) {
                          _createGroup(); // defaults to enterChat: true (primary action)
                        } else {
                          rebuildState(() => _currentStep = effectiveNextStep);
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
                  foregroundColor: AppColors.onChaosAccent,
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

  bool _canAdvanceFromStep(int step) {
    if (step == 0) return _canLeaveMembersStep;
    if (step == 6) {
      return _members.length >= 2 && _nameController.text.trim().isNotEmpty;
    }
    return true;
  }

  Widget _tokenBadge() {
    final color = _contentTokenEstimate > 6000
        ? AppColors.resolve(context, Colors.redAccent, Colors.red.shade700)
        : _contentTokenEstimate > 3000
        ? AppColors.resolve(
            context,
            Colors.orangeAccent,
            Colors.orange.shade700,
          )
        : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '~$_contentTokenEstimate tokens',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}
