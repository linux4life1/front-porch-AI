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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/model_manager/model_manager_empty_state.dart';
import 'package:front_porch_ai/ui/pages/model_manager/model_search_controller.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';

/// The Model Manager's "Search / Download" tab: HuggingFace search bar,
/// error strip, and the result cards with their queue-download buttons. The
/// search state lives in [controller], owned by the page.
class ModelManagerSearchTab extends StatelessWidget {
  const ModelManagerSearchTab({
    super.key,
    required this.controller,
    required this.modelManager,
    required this.availableVram,
  });

  final ModelSearchController controller;
  final ModelManager modelManager;
  final int availableVram;

  void _onDownload(BuildContext context, HFModelFile file) {
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    modelManager.queueDownload(file);
    // Downloading a model IS local intent: fetch the managed engine alongside
    // it (a no-op when installed/downloading/remote) so both finish together
    // instead of the engine wait landing right when the user starts chatting.
    Provider.of<BackendManager>(context, listen: false).ensureEngineInstalled();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            border: Border(
              bottom: BorderSide(
                color: AppColors.borderOf(context).withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: controller.focusNode.hasFocus
                          ? AppColors.porchAmberOf(context)
                          : AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                  child: TextField(
                    controller: controller.textController,
                    focusNode: controller.focusNode,
                    decoration: InputDecoration(
                      hintText: 'Search HuggingFace models...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(context),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.iconSecondary(context),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(color: AppColors.textPrimary(context)),
                    onSubmitted: (_) => controller.search(modelManager),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: controller.isSearching
                    ? null
                    : () => controller.search(modelManager),
                icon: controller.isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(controller.isSearching ? 'Searching...' : 'Search'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.porchAmberOf(context),
                  foregroundColor: AppColors.inkOn(
                    AppColors.porchAmberOf(context),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Error message
        if (controller.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.resolve(
              context,
              Colors.red.withValues(alpha: 0.1),
              Colors.red.withValues(alpha: 0.08),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Results
        Expanded(
          child: controller.isSearching
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Searching HuggingFace...',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                )
              : controller.results.isEmpty
              ? const ModelManagerEmptyState(
                  title: 'Search for models',
                  subtitle:
                      'Enter a model name or architecture to search HuggingFace',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: controller.results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final model = controller.results[index];
                    final modelWithFiles =
                        controller.modelsWithFiles[model.id] ?? model;
                    return HFModelCard(
                      model: modelWithFiles,
                      availableVramMb: availableVram,
                      onDownload: (file) => _onDownload(context, file),
                      downloadingFiles: modelManager.downloadingFiles,
                      downloadedFiles: modelManager.downloadedFilenames,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
