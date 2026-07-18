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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One glanceable card answering "can this feature talk to the AI right now?"
/// — backend name, loaded model, live ready state — with a button into the
/// existing [ModelSettingsDialog] (the same backend/model picker chat uses).
///
/// Born from a support report: Porch Stories had no backend/model surface at
/// all, so running a stage without an engine died with a raw socket error.
/// Placed on the story home header ([compact]) and the project dashboard
/// (full), and reusable by any feature that needs the LLM.
class AiEngineStatusCard extends StatelessWidget {
  /// Compact renders a single-row chip for headers; full adds the helper line.
  final bool compact;

  const AiEngineStatusCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    // LLMProvider re-notifies for kobold/pseudo lifecycle; OpenRouterService
    // notifies on remote config changes; StorageService covers model-path and
    // backend-type edits saved from the dialog.
    final llm = context.watch<LLMProvider>();
    context.watch<OpenRouterService>();
    final storage = context.watch<StorageService>();

    final active = llm.activeService;
    final ready = active.isReady;

    // Live state label + color.
    String stateLabel;
    Color stateColor;
    bool busy = false;
    if (ready) {
      stateLabel = 'Ready';
      stateColor = AppColors.resolve(
        context,
        AppColors.logReady,
        AppColors.bondHighLight,
      );
    } else if (llm.hasManagedProcess) {
      final k = llm.koboldService;
      final starting = k.isStarting;
      final loading = k.isRunning && !k.modelReady;
      busy = starting || loading;
      stateLabel = starting
          ? 'Starting…'
          : loading
          ? 'Loading model…'
          : 'Not running';
      stateColor = busy
          ? AppColors.porchAmberOf(context)
          : AppColors.negativeAccentOf(context);
    } else {
      stateLabel = 'Not configured';
      stateColor = AppColors.negativeAccentOf(context);
    }

    // What's loaded / selected.
    String modelLabel;
    switch (llm.activeBackend) {
      case BackendType.kobold:
        final path = storage.lastUsedModelPath;
        if (path != null && path.isNotEmpty) {
          modelLabel = p.basename(path);
        } else {
          // A .kcpps preset can own the model instead of a picker selection.
          final preset = storage.activeKcppsPath;
          modelLabel = (preset == null || preset.isEmpty)
              ? 'No model selected'
              : p.basename(preset);
        }
      case BackendType.openRouter:
      case BackendType.omlx:
        modelLabel = storage.remoteModelName.isEmpty
            ? 'No model selected'
            : storage.remoteModelName;
    }

    final dot = busy
        ? SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 2, color: stateColor),
          )
        : Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor),
          );

    final button = TextButton(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => const ModelSettingsDialog(),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.porchHoneyOf(context),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(ready ? 'Change' : 'Set Up'),
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2, right: 2),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot,
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                ready
                    ? '${active.backendName} · $modelLabel'
                    : '${active.backendName} · $stateLabel',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                ),
              ),
            ),
            button,
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready
              ? AppColors.borderOf(context).withValues(alpha: 0.4)
              : stateColor.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.memory,
            size: 22,
            color: ready ? AppColors.porchHoneyOf(context) : stateColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Engine — ${active.backendName}',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    dot,
                    const SizedBox(width: 5),
                    Text(
                      stateLabel,
                      style: TextStyle(color: stateColor, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  ready
                      ? modelLabel
                      : 'Stories use the same AI engine as chat — '
                            '$modelLabel.',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          button,
        ],
      ),
    );
  }
}

/// Surface a generation failure with a way out: red snackbar with the plain
/// message, plus a "Set Up AI" action into [ModelSettingsDialog] when the
/// failure is the AI backend being unavailable ([LlmUnavailableException]
/// already carries a user-facing message). Story pages call this from every
/// pipeline catch instead of hand-rolling `SnackBar(Text('Error: $e'))`.
void showAiErrorSnackBar(BuildContext context, Object error) {
  final isEngineDown = error is LlmUnavailableException;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(isEngineDown ? '$error' : 'Error: $error'),
      backgroundColor: AppColors.negativeAccentOf(context),
      duration: const Duration(seconds: 6),
      action: isEngineDown
          ? SnackBarAction(
              label: 'Set Up AI',
              textColor: AppColors.porchHoney,
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ModelSettingsDialog(),
              ),
            )
          : null,
    ),
  );
}
