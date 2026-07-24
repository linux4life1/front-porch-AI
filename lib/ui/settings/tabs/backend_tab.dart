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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend_mode_selector.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/remote_api_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/omlx_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/managed_backend_section.dart';

/// Backend tab: backend-mode selector followed by the config section for the
/// active backend (remote OpenAI-compatible, oMLX, or managed KoboldCPP).
/// Extracted from settings_page's _buildBackendTab. Shared launch state
/// (selected model, presets, controllers, model list) is owned by the page
/// and threaded through; the state-mutating callbacks stay in the page's
/// State so launch behavior is unchanged.
class BackendTab extends StatelessWidget {
  const BackendTab({
    super.key,
    required this.apiUrlController,
    required this.apiKeyController,
    required this.availableModels,
    required this.onModelsFetched,
    required this.selectedModelPath,
    required this.localPresets,
    required this.onModelSelected,
    required this.onVisionChanged,
    required this.onScanPresets,
    required this.onKcppsChanged,
    required this.onKcppsExternalClear,
    required this.onKcppsBrowsePicked,
    required this.onKcppsModelStatusChanged,
    required this.onGenerateKcppsDone,
    required this.onToggleBackend,
  });

  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final List<RemoteModelInfo> availableModels;
  final ValueChanged<List<RemoteModelInfo>> onModelsFetched;
  final String? selectedModelPath;
  final List<File> localPresets;
  final ValueChanged<String?> onModelSelected;
  final VoidCallback onVisionChanged;
  final VoidCallback onScanPresets;
  final ValueChanged<String?> onKcppsChanged;
  final VoidCallback onKcppsExternalClear;
  final ValueChanged<String> onKcppsBrowsePicked;
  final ValueChanged<bool> onKcppsModelStatusChanged;
  final VoidCallback onGenerateKcppsDone;
  final VoidCallback onToggleBackend;

  @override
  Widget build(BuildContext context) {
    final backendManager = Provider.of<BackendManager>(context);
    final llmProvider = Provider.of<LLMProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BackendModeSelector(),
          if (llmProvider.activeBackend == BackendType.openRouter)
            RemoteApiSection(
              apiUrlController: apiUrlController,
              apiKeyController: apiKeyController,
              availableModels: availableModels,
              onModelsFetched: onModelsFetched,
            ),
          if (llmProvider.activeBackend == BackendType.omlx)
            OmlxSection(
              availableModels: availableModels,
              onModelsFetched: onModelsFetched,
            ),
          if (llmProvider.hasManagedProcess && !backendManager.isIntelMac)
            ManagedBackendSection(
              selectedModelPath: selectedModelPath,
              localPresets: localPresets,
              onModelSelected: onModelSelected,
              onVisionChanged: onVisionChanged,
              onScanPresets: onScanPresets,
              onKcppsChanged: onKcppsChanged,
              onKcppsExternalClear: onKcppsExternalClear,
              onKcppsBrowsePicked: onKcppsBrowsePicked,
              onKcppsModelStatusChanged: onKcppsModelStatusChanged,
              onGenerateKcppsDone: onGenerateKcppsDone,
              onToggleBackend: onToggleBackend,
            ),
        ],
      ),
    );
  }
}
