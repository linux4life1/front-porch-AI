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
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final remote = Provider.of<OpenRouterService>(context);
    final theme = Theme.of(context);
    final accent = AppColors.porchAmberOf(context);
    final kind = resolveRemoteProviderKind(
      backendType: storageService.backendSettings.backendType,
      url: storageService.backendSettings.remoteApiUrl,
    );
    final showUrl = remoteProviderShowsUrlField(kind);
    final needsKey = remoteProviderNeedsApiKey(kind);

    final fields = <Widget>[
      RemoteReadyBadge(service: remote),
      const SizedBox(height: 12),
      if (showUrl) ...[
        Text('API URL', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        TextFormField(
          controller: widget.apiUrlController,
          decoration: InputDecoration(
            hintText: 'https://your-server.example/v1',
            filled: true,
            fillColor: theme.scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          onChanged: (val) =>
              storageService.backendSettings.setRemoteApiUrl(val.trim()),
        ),
        const SizedBox(height: 16),
      ],
      if (needsKey) ...[
        Text('API Key', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        TextFormField(
          controller: widget.apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            hintText: storageService.backendSettings.remoteApiKey.isNotEmpty
                ? '•••••• (leave blank to keep)'
                : 'paste your API key',
            filled: true,
            fillColor: theme.scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            suffixIcon: const Icon(Icons.key, size: 18),
          ),
          onChanged: (val) {
            if (val.trim().isNotEmpty) {
              storageService.backendSettings.setRemoteApiKey(val.trim());
            }
          },
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isCheckingConnection ? null : () => _check(context),
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
      RemoteModelPickerField(
        availableModels: widget.availableModels,
        selectedId: storageService.backendSettings.remoteModelName,
        fetching: _isFetchingModels,
        onRefresh: () => _refreshModels(context),
        onSelected: (m) =>
            storageService.backendSettings.setRemoteModelName(m.id),
        onTyped: storageService.backendSettings.setRemoteModelName,
      ),
      if (storageService.backendSettings.remoteModelName.isNotEmpty) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: RemoteVisionPill(
            apiUrl: storageService.backendSettings.remoteApiUrl,
            apiKey: storageService.backendSettings.remoteApiKey,
            modelName: storageService.backendSettings.remoteModelName,
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
                style: theme.textTheme.bodySmall?.copyWith(color: accent),
              ),
            ),
          ],
        ),
      ),
    ];

    return Column(
      key: const Key('chat-api-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }

  Future<void> _check(BuildContext context) async {
    setState(() => _isCheckingConnection = true);
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    final storageService = Provider.of<StorageService>(context, listen: false);
    final result = await openRouter.testConnection(
      apiUrl: storageService.backendSettings.remoteApiUrl,
      apiKey: storageService.backendSettings.remoteApiKey,
    );
    if (!mounted) return;
    setState(() => _isCheckingConnection = false);
    final isSuccess = result.contains('successful');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
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

  Future<void> _refreshModels(BuildContext context) async {
    setState(() => _isFetchingModels = true);
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    final storageService = Provider.of<StorageService>(context, listen: false);
    final models = await openRouter.fetchAvailableModels(
      apiUrl: storageService.backendSettings.remoteApiUrl,
      apiKey: storageService.backendSettings.remoteApiKey,
    );
    if (!mounted) return;
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
}
