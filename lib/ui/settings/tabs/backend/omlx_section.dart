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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/vision_projector_field.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';

/// oMLX configuration (macOS Apple-Silicon local inference at the fixed
/// localhost:8000 URL). Extracted from settings_page's Backend tab. Owns its
/// own fetch spinner; the fetched list is lifted to the page (shared with the
/// Voice tab) via [onModelsFetched]. AppColors + warm-porch accents.
class OmlxSection extends StatefulWidget {
  const OmlxSection({
    super.key,
    required this.availableModels,
    required this.onModelsFetched,
  });

  final List<RemoteModelInfo> availableModels;
  final ValueChanged<List<RemoteModelInfo>> onModelsFetched;

  @override
  State<OmlxSection> createState() => _OmlxSectionState();
}

class _OmlxSectionState extends State<OmlxSection> {
  bool _isFetchingModels = false;

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);
    final accent = AppColors.porchAmberOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('oMLX Configuration'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Model picker.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Model', style: theme.textTheme.bodySmall),
                  TextButton.icon(
                    onPressed: _isFetchingModels
                        ? null
                        : () async {
                            setState(() => _isFetchingModels = true);
                            final openRouter = Provider.of<OpenRouterService>(
                              context,
                              listen: false,
                            );
                            final models = await openRouter
                                .fetchAvailableModels(
                                  apiUrl: 'http://localhost:8000/v1',
                                  apiKey: storageService.remoteApiKey,
                                );
                            if (mounted) {
                              setState(() => _isFetchingModels = false);
                              widget.onModelsFetched(models);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    models.isEmpty
                                        ? 'No models found. Make sure oMLX is running and has models loaded.'
                                        : 'Found ${models.length} available models.',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: _isFetchingModels
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(
                      _isFetchingModels ? 'Loading...' : 'Fetch Models',
                    ),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (widget.availableModels.isNotEmpty)
                InkWell(
                  onTap: () => showModelSearchDialog(
                    context,
                    storageService,
                    widget.availableModels,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            storageService.remoteModelName.isNotEmpty
                                ? storageService.remoteModelName
                                : 'Tap to select a model...',
                            style: TextStyle(
                              fontSize: 13,
                              color: storageService.remoteModelName.isNotEmpty
                                  ? null
                                  : AppColors.textTertiary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.iconSecondary(context),
                        ),
                      ],
                    ),
                  ),
                )
              else
                TextFormField(
                  initialValue: storageService.remoteModelName,
                  decoration: InputDecoration(
                    hintText: 'e.g. mlx-community/Llama-3-8B-Instruct',
                    filled: true,
                    fillColor: theme.scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: const Icon(Icons.smart_toy, size: 18),
                  ),
                  onChanged: (val) =>
                      storageService.setRemoteModelName(val.trim()),
                ),
              // Vision-capability pill for the selected model.
              if (storageService.remoteModelName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  // oMLX lives at its fixed local URL — probing the
                  // Remote API URL here asked the WRONG server (e.g.
                  // OpenRouter) about an oMLX model and always said none.
                  child: RemoteVisionPill(
                    apiUrl: 'http://localhost:8000/v1',
                    apiKey: storageService.remoteApiKey,
                    modelName: storageService.remoteModelName,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'oMLX runs locally on your Mac. Install via brew '
                        'install jundot/omlx/omlx and run omlx serve.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
