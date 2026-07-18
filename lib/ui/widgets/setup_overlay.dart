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
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/ui/widgets/low_perf_cpu_warning.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

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
    final backendManager = Provider.of<BackendManager>(context);

    if (setupService.currentStep == SetupStep.idle ||
        setupService.currentStep == SetupStep.complete) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.formMasterAccent.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppColors.formMasterAccent,
                size: 48,
              ),
              const SizedBox(height: 24),
              Text(
                'Starting Front Porch AI',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildStepContent(setupService, backendManager, context),
              if (setupService.currentStep == SetupStep.error) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => setupService.runAutoSetup(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.formMasterAccent,
                    foregroundColor: AppColors.onChaosAccent,
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

  Widget _buildStepContent(
    SetupService setup,
    BackendManager backend,
    BuildContext context,
  ) {
    switch (setup.currentStep) {
      case SetupStep.checkingBackend:
        return _buildStatusRow('Checking installation...', true);
      case SetupStep.downloadingBackend:
        return Column(
          children: [
            _buildStatusRow('Downloading Backend...', true),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: backend.downloadProgress,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.formMasterAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              backend.statusMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const LowPerfCpuWarning(margin: EdgeInsets.only(top: 16)),
          ],
        );
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

  Widget _buildStatusRow(String text, bool spinning) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (spinning)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.formMasterAccent,
            ),
          ),
        if (spinning) const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
