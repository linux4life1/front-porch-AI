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
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'model_settings_text_field.dart';

/// Remote-API (OpenRouter / oMLX / other provider) settings: URL and key
/// boxes, the SuperGrok card for xAI, the model field, and the ready /
/// connection-test line.
class RemoteBackendSettings extends StatelessWidget {
  const RemoteBackendSettings({
    super.key,
    this.isOmLx = false,
    required this.apiUrlController,
    required this.apiKeyController,
    required this.modelName,
    required this.showKeyEditor,
    required this.xaiKeyOpen,
    required this.connectionStatus,
    required this.isTesting,
    required this.onSave,
    required this.onKeySubmitted,
    required this.onOpenXaiKey,
    required this.onEditKey,
    required this.onPickModel,
    required this.onTest,
  });

  final bool isOmLx;
  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final String modelName;

  /// The key box is open over a saved key.
  final bool showKeyEditor;

  /// xAI: the user asked for the key box instead of the SuperGrok sign-in.
  final bool xaiKeyOpen;
  final String? connectionStatus;
  final bool isTesting;

  /// The API URL box was submitted.
  final VoidCallback onSave;

  /// The API key box was submitted.
  final VoidCallback onKeySubmitted;
  final VoidCallback onOpenXaiKey;
  final VoidCallback onEditKey;
  final VoidCallback onPickModel;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
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
    final isXai = kind == RemoteProviderKind.xai;
    final viaSuperGrok = isXai && llm.superGrok.isSignedIn;
    final needsKey = remoteProviderNeedsApiKey(kind) && !viaSuperGrok;
    final hasKey = storage.backendSettings.remoteApiKey.isNotEmpty;
    // xAI: sign-in first; the key box only once asked for or already saved.
    final showKey = needsKey && (!isXai || hasKey || xaiKeyOpen);
    final model = modelName.trim();
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
          ModelSettingsTextField(
            label: 'API URL',
            controller: apiUrlController,
            onEditingComplete: onSave,
          ),
          const SizedBox(height: 12),
        ],
        if (isXai) ...[
          SuperGrokCard(
            auth: llm.superGrok,
            onUseApiKey: showKey ? null : onOpenXaiKey,
          ),
          const SizedBox(height: 12),
        ],
        if (showKey) ...[
          if (hasKey && !showKeyEditor)
            SavedApiKeyRow(onChange: onEditKey)
          else
            ModelSettingsTextField(
              label: hasKey ? 'API Key' : 'Paste API key',
              controller: apiKeyController,
              isObscured: true,
              onEditingComplete: onKeySubmitted,
            ),
          const SizedBox(height: 12),
        ],
        InkWell(
          onTap: () => onPickModel(),
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
        if (connectionStatus != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              connectionStatus!,
              style: TextStyle(
                color: connectionStatus!.contains('successful')
                    ? StatusColors.successOf(context)
                    : StatusColors.dangerOf(context),
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
                  color: ready
                      ? StatusColors.successOf(context)
                      : AccentColors.goldOf(context),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                ready
                    ? 'Ready'
                    : needsKey && !hasKey
                    ? (isXai
                          ? 'Sign in with SuperGrok or add a key'
                          : 'Needs an API key')
                    : 'Needs a model',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: isTesting ? null : onTest,
                child: Text(isTesting ? 'Testing…' : 'Test'),
              ),
            ],
          ),
      ],
    );
  }
}

/// Stands in for the API key box once a key is saved.
class SavedApiKeyRow extends StatelessWidget {
  const SavedApiKeyRow({super.key, required this.onChange});

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
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
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}
