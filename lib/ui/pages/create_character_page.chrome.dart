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
// Manual creator chrome: step dots, nav buttons, token badge. Extracted
// so create_character_page.dart stays under the 500-line ratchet after
// the per-character Pockets & Wardrobe field landed on the shell.

part of 'create_character_page.dart';

extension _CreateCharacterChrome on _CreateCharacterPageState {
  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(0, 'Identity'),
        _stepLine(),
        _stepDot(1, 'Personality'),
        _stepLine(),
        _stepDot(2, 'Dialogue'),
        _stepLine(),
        _stepDot(3, 'Lorebook'),
        _stepLine(),
        _stepDot(4, 'Porch Life'),
        _stepLine(),
        _stepDot(5, 'Review'),
        _stepLine(),
        _stepDot(6, 'Portrait & Avatars'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    final dotColor = isActive
        ? AppColors.porchAmberOf(context)
        : AppColors.surfaceContainerOf(context);

    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);

    final numberOrCheckColor = isActive
        ? AppColors.resolve(context, Colors.white, Colors.white)
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
                ? Icon(Icons.check, size: 14, color: numberOrCheckColor)
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

  Widget _buildTokenBadge(int estimatedTokens) {
    final color = estimatedTokens > 4000
        ? Colors.redAccent
        : estimatedTokens > 2000
        ? Colors.orangeAccent
        : AppColors.formMasterAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.token, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '~$estimatedTokens tokens',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons({
    required int currentStep,
    String? nextLabel,
    VoidCallback? onNext,
    bool showBack = true,
  }) {
    final labels = [
      'Personality',
      'Dialogue',
      'Lorebook',
      'Porch Life',
      'Review & Create',
    ];
    final nextText =
        nextLabel ??
        (currentStep < labels.length ? 'Next: ${labels[currentStep]}' : 'Save');

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack && currentStep > 0)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      rebuildState(() => _currentStep = currentStep - 1),
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
            if (showBack && currentStep > 0) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    onNext ??
                    () {
                      if (currentStep == 0) {
                        if (_nameController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Character name is required'),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                      }
                      rebuildState(() => _currentStep = currentStep + 1);
                    },
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: Text(nextText, style: const TextStyle(fontSize: 16)),
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
