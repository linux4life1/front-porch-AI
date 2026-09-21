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

part of 'generation_options_tab.dart';

/// Backend chip row + the remote-backend panel for [_GenerationOptionsTabState],
/// split out of the shell to keep every file under the 500-LOC cap (mirrors the
/// settings_page.dart `part of` pattern). These methods keep direct access to
/// the tab's private state, so behavior is identical to when they lived
/// inline. AppColors exclusive.
extension _GenerationOptionsSource on _GenerationOptionsTabState {
  Widget _buildBackendSelector(StorageService st) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final bs = ImageGenBackend.values
        .where(
          (b) =>
              b != ImageGenBackend.drawThings ||
              isMac ||
              st.imageGenSettings.imageGenBackend == b.key,
        )
        .toList();
    final ac = AppColors.formMasterAccent;
    return Row(
      children: bs.map((b) {
        final sel = st.imageGenSettings.imageGenBackend == b.key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: b == bs.last ? 0 : 8),
            child: GestureDetector(
              onTap: () {
                st.imageGenSettings.setImageGenBackend(b.key);
                rebuildState(() {
                  _connectionOk = null;
                  _localModels = [];
                  _localLoras = [];
                  _localSamplers = [];
                  _localSchedulers = [];
                });
                // Auto-test the newly selected local backend (the status card
                // reflects progress; success populates models/LoRAs/samplers).
                if (b != ImageGenBackend.remote) _testConnection();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.cardOf(context)
                      : AppColors.surfaceContainerOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? ac : AppColors.borderOf(context),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      b == ImageGenBackend.remote
                          ? Icons.cloud_outlined
                          : b == ImageGenBackend.drawThings
                          ? Icons.apple
                          : b == ImageGenBackend.comfyUi
                          ? Icons.account_tree_outlined
                          : Icons.computer_outlined,
                      size: 16,
                      color: sel ? ac : AppColors.iconSecondary(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      b.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: sel ? ac : AppColors.textTertiary(context),
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRemotePanel(StorageService st) {
    // Keys live in Settings → Backend (the vault). Studio chips pick which
    // vault host Image Studio bills — they do not rewrite chat's mouth URL.
    final account = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: st.imageGenSettings.imageRemoteApiUrl,
      chatRemoteApiUrl: st.backendSettings.remoteApiUrl,
      keyFor: st.backendSettings.remoteApiKeyFor,
    );
    final apiKey = account.key;
    final host = Uri.tryParse(account.url)?.host ?? '';
    final selectedId = widget.editScoped
        ? st.imageGenSettings.imageGenEditModel
        : st.imageGenSettings.imageGenModel;
    ImageModelInfo? selected;
    for (final m in _models) {
      if (m.id == selectedId) {
        selected = m;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RemoteImageHostChips(
          selectedUrl: account.url,
          keyFor: st.backendSettings.remoteApiKeyFor,
          onSelect: (url) async {
            await applyImageRemoteHost(
              image: st.imageGenSettings,
              url: url,
              chatRemoteApiUrl: st.backendSettings.remoteApiUrl,
              editScoped: widget.editScoped,
            );
            await _fetchModels();
          },
        ),
        const SizedBox(height: 10),
        if (apiKey.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.logError.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.logError.withValues(alpha: 0.55),
              ),
            ),
            child: Text(
              'No Remote API key configured for this host. Remote images '
              'use the same API account as chat — nothing runs locally and '
              'nothing is free. Add your provider key under Settings → '
              'Backend → Remote API first; models will list once it\'s set.',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 11.5,
              ),
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Bills your Remote API account'
              '${host.isEmpty ? '' : ' ($host)'} per image.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
        Text(
          'Image Model',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: InkWell(
                key: const Key('remote-image-model-search'),
                onTap: _models.isEmpty
                    ? null
                    : () => _openRemoteModelSearch(st),
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _deco(
                    hint: _loadingModels
                        ? 'Loading...'
                        : (_models.isEmpty ? 'No models' : 'Search models…'),
                  ),
                  child: Text(
                    selected == null
                        ? (selectedId.isEmpty ? 'Search models…' : selectedId)
                        : imageModelListLabel(selected),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected == null && selectedId.isEmpty
                          ? AppColors.textTertiary(context)
                          : AppColors.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: _loadingModels
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.formMasterAccent,
                      ),
                    )
                  : Icon(
                      Icons.search,
                      color: AppColors.iconSecondary(context),
                      size: 18,
                    ),
              onPressed: _models.isEmpty || _loadingModels
                  ? null
                  : () => _openRemoteModelSearch(st),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: AppColors.iconSecondary(context),
                size: 18,
              ),
              onPressed: _loadingModels ? null : _fetchModels,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSharedFields(st),
      ],
    );
  }

  void _openRemoteModelSearch(StorageService st) {
    final sorted = [..._models]..sort(compareImageModelsForPicker);
    showGenericModelSearchDialog<ImageModelInfo>(
      context,
      sorted,
      title: 'Select Image Model',
      getTitle: imageModelListLabel,
      getSubtitle: (m) => m.id,
      onSelected: (m) async {
        if (widget.editScoped) {
          await st.imageGenSettings.setImageGenEditModel(m.id);
        } else {
          await st.imageGenSettings.setImageGenModel(m.id);
        }
        final url = resolveImageStudioRemoteAccount(
          imageRemoteApiUrl: st.imageGenSettings.imageRemoteApiUrl,
          chatRemoteApiUrl: st.backendSettings.remoteApiUrl,
          keyFor: st.backendSettings.remoteApiKeyFor,
        ).url;
        await st.imageGenSettings.setRemoteImageModelFor(
          url,
          m.id,
          edit: widget.editScoped,
        );
        rebuildState(() {});
      },
    );
  }
}
