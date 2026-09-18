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

part of 'model_settings_dialog.dart';

/// Remote-API (OpenRouter / oMLX) settings: save, connection test, and the
/// content builder. Split out of `model_settings_dialog.dart` — verbatim
/// except `setState` -> `rebuildState` (extensions can't call a State's
/// protected members).
extension _ModelSettingsRemoteSection on _ModelSettingsDialogState {
  void _saveRemoteSettings({bool snackbar = false}) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    // Never overwrite the user's remote API URL when oMLX is active (it uses a fixed localhost URL)
    if (llmProvider.activeBackend != BackendType.omlx) {
      storage.backendSettings.setRemoteApiUrl(_apiUrlController.text.trim());
    }
    if (_apiKeyController.text.trim().isNotEmpty) {
      storage.backendSettings.setRemoteApiKey(_apiKeyController.text.trim());
    }
    storage.backendSettings.setRemoteModelName(
      _modelNameController.text.trim(),
    );
    if (snackbar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API settings saved.')));
    }
  }

  Future<void> _testConnection() async {
    rebuildState(() {
      _isTesting = true;
      _connectionStatus = null;
    });
    _saveRemoteSettings();
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    // Force oMLX localhost URL when oMLX backend is active (ignores whatever is in the URL field)
    final apiUrl = llmProvider.activeBackend == BackendType.omlx
        ? _omlxLocalhostUrl
        : _apiUrlController.text.trim();
    // Override form — NEVER configure() the live service just to probe
    // (that silently re-routes active chat traffic; see the service's own
    // fetchAvailableModels doc note).
    final result = await openRouter.testConnection(
      apiUrl: apiUrl,
      apiKey: _apiKeyController.text.trim(),
    );
    if (mounted) {
      rebuildState(() {
        _isTesting = false;
        _connectionStatus = result;
      });
    }
  }

  Widget _buildRemoteSettings({bool isOmLx = false}) {
    final storage = Provider.of<StorageService>(context);
    final llm = Provider.of<LLMProvider>(context);
    final kind = resolveRemoteProviderKind(
      backendType: switch (llm.activeBackend) {
        BackendType.kobold => 'kobold',
        BackendType.omlx => 'omlx',
        BackendType.openRouter => 'openRouter',
      },
      url: storage.backendSettings.remoteApiUrl,
    );
    final showUrl = remoteProviderShowsUrlField(kind);
    final needsKey = remoteProviderNeedsApiKey(kind);
    final hasKey = storage.backendSettings.remoteApiKey.isNotEmpty;
    final model = _modelNameController.text.trim();
    final ready = model.isNotEmpty && (!needsKey || hasKey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isOmLx)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Apple Silicon via oMLX. URL is http://localhost:8000/v1. '
              'oMLX must be running (`omlx serve`).',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
        if (showUrl) ...[
          _buildTextField(
            label: 'API URL',
            controller: _apiUrlController,
            onEditingComplete: _saveRemoteSettings,
          ),
          const SizedBox(height: 12),
        ],
        if (needsKey) ...[
          if (hasKey && !_showKeyEditor)
            _savedKeyRow()
          else
            _buildTextField(
              label: hasKey ? 'API Key' : 'Paste API key',
              controller: _apiKeyController,
              isObscured: true,
              onEditingComplete: () {
                _saveRemoteSettings();
                rebuildState(() => _showKeyEditor = false);
              },
            ),
          const SizedBox(height: 12),
        ],
        InkWell(
          onTap: () => _showModelPicker(),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Model',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.isEmpty ? 'Tap to select a model...' : model,
                        style: TextStyle(
                          color: model.isEmpty
                              ? AppColors.textTertiary(context)
                              : AppColors.textPrimary(context),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
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
        ),
        const SizedBox(height: 12),
        if (_connectionStatus != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _connectionStatus!,
              style: TextStyle(
                // theme-keep: success/failure status semantics
                color: _connectionStatus!.contains('successful')
                    ? Colors.greenAccent
                    : Colors.redAccent,
                fontSize: 13,
              ),
            ),
          )
        else
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // theme-keep: ready/needs-setup status
                  color: ready ? Colors.greenAccent : Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                ready
                    ? 'Ready'
                    : needsKey && !hasKey
                    ? 'Needs an API key'
                    : 'Needs a model',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _isTesting ? null : _testConnection,
                child: Text(_isTesting ? 'Testing…' : 'Test'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _savedKeyRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'API key',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Key saved',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => rebuildState(() => _showKeyEditor = true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
