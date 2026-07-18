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
import 'package:front_porch_ai/ui/settings/widgets/api_preset_chip.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';

/// Remote OpenAI-compatible API configuration (OpenRouter / Nano-GPT / any
/// local server). Extracted from settings_page's Backend tab. Owns its own
/// transient fetch/check spinners; the fetched model list is lifted to the
/// page (shared with the Voice tab) via [onModelsFetched]. AppColors +
/// warm-porch accents.
class RemoteApiSection extends StatefulWidget {
  const RemoteApiSection({
    super.key,
    required this.apiUrlController,
    required this.apiKeyController,
    required this.availableModels,
    required this.onModelsFetched,
  });

  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final List<RemoteModelInfo> availableModels;
  final ValueChanged<List<RemoteModelInfo>> onModelsFetched;

  @override
  State<RemoteApiSection> createState() => _RemoteApiSectionState();
}

class _RemoteApiSectionState extends State<RemoteApiSection> {
  bool _isFetchingModels = false;
  bool _isCheckingConnection = false;

  Future<void> _selectPreset(String label, String url) async {
    final storageService = Provider.of<StorageService>(context, listen: false);
    // Always preserve the API key in storage — just change the URL. LM Studio
    // won't use an API key since it's local, and when we switch back to
    // Nano-GPT/OpenRouter the key will still be there.
    storageService.setRemoteApiUrl(url);
    widget.apiUrlController.text = url;

    // setRemoteApiUrl above already triggered LLMProvider's storage sync,
    // which applies the live config per active backend; the picker fetch
    // targets the new URL explicitly instead of clobbering live state.
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    setState(() => _isFetchingModels = true);
    try {
      final models = await openRouter.fetchAvailableModels(
        apiUrl: url,
        apiKey: storageService.remoteApiKey,
      );
      if (!mounted) return;
      setState(() => _isFetchingModels = false);
      widget.onModelsFetched(models);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            models.isEmpty
                ? '$label connected — no models found yet.'
                : '$label connected — found ${models.length} models.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);
    final accent = AppColors.porchAmberOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('API Configuration'),
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
              // Quick-connect presets.
              Text('Quick Connect', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ApiPresetChip(
                    label: '🖥️ LM Studio',
                    active:
                        storageService.remoteApiUrl ==
                        'http://localhost:1234/v1',
                    onPressed: () =>
                        _selectPreset('LM Studio', 'http://localhost:1234/v1'),
                  ),
                  ApiPresetChip(
                    label: '🌐 OpenRouter',
                    active:
                        storageService.remoteApiUrl ==
                        'https://openrouter.ai/api/v1',
                    onPressed: () => _selectPreset(
                      'OpenRouter',
                      'https://openrouter.ai/api/v1',
                    ),
                  ),
                  ApiPresetChip(
                    label: '⚡ Nano-GPT',
                    active:
                        storageService.remoteApiUrl ==
                        'https://nano-gpt.com/api/v1',
                    onPressed: () => _selectPreset(
                      'Nano-GPT',
                      'https://nano-gpt.com/api/v1',
                    ),
                  ),
                  // No oMLX chip here on purpose: oMLX has its own dedicated
                  // Backend Mode radio above (with oMLX-specific handling),
                  // so a second way to reach it through the generic client
                  // was a redundant, subtly-different path. Use the radio.
                ],
              ),
              const SizedBox(height: 16),
              Text('API URL', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              TextFormField(
                controller: widget.apiUrlController,
                decoration: InputDecoration(
                  hintText: 'https://openrouter.ai/api/v1',
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (val) => storageService.setRemoteApiUrl(val.trim()),
              ),
              const SizedBox(height: 16),
              Text('API Key', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              TextFormField(
                controller: widget.apiKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'sk-or-...',
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  suffixIcon: const Icon(Icons.key, size: 18),
                ),
                onChanged: (val) => storageService.setRemoteApiKey(val.trim()),
              ),
              const SizedBox(height: 12),
              // ── Check Connection Button ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingConnection
                      ? null
                      : () async {
                          setState(() => _isCheckingConnection = true);
                          final openRouter = Provider.of<OpenRouterService>(
                            context,
                            listen: false,
                          );
                          final result = await openRouter.testConnection(
                            apiUrl: storageService.remoteApiUrl,
                            apiKey: storageService.remoteApiKey,
                          );
                          if (mounted) {
                            setState(() => _isCheckingConnection = false);
                            final isSuccess = result.contains('successful');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(
                                      isSuccess
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color: isSuccess
                                          ? AppColors.bondHighOf(context)
                                          : AppColors.negativeAccentOf(context),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(result)),
                                  ],
                                ),
                              ),
                            );
                          }
                        },
                  icon: _isCheckingConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(
                    _isCheckingConnection ? 'Checking...' : 'Check Connection',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.85),
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // ── Model Selection ──
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
                                  apiUrl: storageService.remoteApiUrl,
                                  apiKey: storageService.remoteApiKey,
                                );
                            if (mounted) {
                              setState(() => _isFetchingModels = false);
                              widget.onModelsFetched(models);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    models.isEmpty
                                        ? 'No models found. Check your API URL and key.'
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
                      _isFetchingModels ? 'Loading...' : 'Refresh Models',
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                storageService.remoteModelName.isNotEmpty
                                    ? storageService.remoteModelName
                                    : 'Tap to select a model...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      storageService.remoteModelName.isNotEmpty
                                      ? null
                                      : AppColors.textTertiary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (storageService
                                  .remoteModelName
                                  .isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Builder(
                                  builder: (context) {
                                    final match = widget.availableModels
                                        .where(
                                          (m) =>
                                              m.id ==
                                              storageService.remoteModelName,
                                        )
                                        .toList();
                                    if (match.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      match.first.pricingLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary(context),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
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
                    hintText: 'e.g. nousresearch/hermes-3-llama-3.1-405b',
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
              // Vision-capability pill for the selected remote model.
              // OpenRouter / Nano-GPT resolve automatically from free
              // /models metadata; generic backends expose a manual "Check
              // vision" button so the runtime probe never costs a token
              // unasked.
              if (storageService.remoteModelName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: RemoteVisionPill(
                    apiUrl: storageService.remoteApiUrl,
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
                        'Works with OpenRouter, Nano-GPT, or any '
                        'OpenAI-compatible endpoint.',
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
