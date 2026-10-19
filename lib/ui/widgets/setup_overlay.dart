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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/low_perf_cpu_warning.dart';

class SetupOverlay extends StatefulWidget {
  const SetupOverlay({super.key});

  @override
  State<SetupOverlay> createState() => _SetupOverlayState();
}

class _SetupOverlayState extends State<SetupOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SetupService>(context, listen: false).runAutoSetup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final setupService = Provider.of<SetupService>(context);

    if (setupService.currentStep == SetupStep.idle ||
        setupService.currentStep == SetupStep.complete) {
      return const SizedBox.shrink();
    }

    final isChoice = setupService.currentStep == SetupStep.firstRunChoice;
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          width: isChoice ? 460 : 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.formAccentOf(context).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.formAccentOf(context).withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                color: AppColors.formAccentOf(context),
                size: 48,
              ),
              const SizedBox(height: 24),
              Text(
                isChoice
                    ? 'How will you run your AI?'
                    : 'Starting Front Porch AI',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildStepContent(setupService, context),
              if (setupService.currentStep == SetupStep.error) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => setupService.runAutoSetup(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.formAccentOf(context),
                    foregroundColor: AppColors.onAccentOf(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Retry Setup'),
                ),
                TextButton(
                  onPressed: () => setupService.reset(),
                  child: const Text(
                    'Continue to App anyway',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(SetupService setup, BuildContext context) {
    switch (setup.currentStep) {
      case SetupStep.checkingBackend:
        return _buildStatusRow('Checking installation...', true);
      case SetupStep.firstRunChoice:
        return _buildFirstRunChoice(setup, context);
      case SetupStep.startingBackend:
        return _buildStatusRow('Booting Backend...', true);
      case SetupStep.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
            const SizedBox(height: 8),
            Text(
              setup.errorMessage ?? 'Unknown error occurred',
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// The one-time first-launch choice. One tap, then the overlay dismisses —
  /// picking the managed engine (or "Not sure") starts its download in the
  /// BACKGROUND so it's ready by the time a model is downloaded and a chat
  /// begins; nothing blocks the app and nothing downloads without consent.
  Widget _buildFirstRunChoice(SetupService setup, BuildContext context) {
    return Column(
      children: [
        const Text(
          'You can change this any time in Settings → Backend.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _choiceButton(
          context,
          icon: Icons.rocket_launch,
          title: 'KoboldCpp — managed by Front Porch AI (recommended)',
          subtitle:
              'We download and run the AI engine for you. Starts fetching '
              'now in the background while you set things up.',
          highlighted: true,
          onTap: () => setup.chooseManagedEngine(),
        ),
        const SizedBox(height: 10),
        _choiceButton(
          context,
          icon: Icons.cloud_outlined,
          title: 'I have my own backend',
          subtitle:
              'OpenRouter, Nano-GPT, oMLX, LM Studio, or any OpenAI-'
              'compatible API — local or cloud. Configure it in '
              'Settings → Backend. Nothing is downloaded.',
          highlighted: false,
          onTap: () => setup.chooseOwnBackend(),
        ),
        const SizedBox(height: 10),
        _choiceButton(
          context,
          icon: Icons.help_outline,
          title: 'Not sure yet',
          subtitle:
              'We\'ll quietly fetch the engine in the background so '
              'everything just works when you\'re ready.',
          highlighted: false,
          onTap: () => setup.chooseManagedEngine(),
        ),
        // Low-AVX2/no-NVIDIA machines should know local will be slow BEFORE
        // choosing it (renders nothing on capable hardware).
        const LowPerfCpuWarning(margin: EdgeInsets.only(top: 14)),
      ],
    );
  }

  Widget _choiceButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool highlighted,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.formAccentOf(context).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlighted
                ? AppColors.formAccentOf(context).withValues(alpha: 0.6)
                : Colors.white24,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: highlighted
                  ? AppColors.formAccentOf(context)
                  : Colors.white70,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String text, bool spinning) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (spinning)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.formAccentOf(context),
            ),
          ),
        if (spinning) const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
