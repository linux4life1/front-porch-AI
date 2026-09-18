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

/// The local-backend panel (Draw Things / ComfyUI / A1111 + shared LoRA
/// block) for [_GenerationOptionsTabState], split out of the shell to keep
/// every file under the 500-LOC cap (mirrors the settings_page.dart `part of`
/// pattern). These methods keep direct access to the tab's private state, so
/// behavior is identical to when they lived inline. AppColors exclusive.
extension _GenerationOptionsLocalPanel on _GenerationOptionsTabState {
  Widget _buildLocalPanel(StorageService st) {
    final isDT = st.imageGenSettings.imageGenBackend == 'drawthings';
    final isComfy = st.imageGenSettings.imageGenBackend == 'comfyui';
    final backend = ImageGenBackend.fromKey(
      st.imageGenSettings.imageGenBackend,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One glanceable status line + Retry, fed by the automatic connection
        // test (on open and on backend switch). Replaces the old per-backend
        // Test buttons and status icons.
        ConnectionStatusCard(
          backendLabel: backend.label,
          connected: _connectionOk,
          testing: _testingConnection,
          modelCount: _localModels.length,
          loraCount: _localLoras.length,
          notReachableHint: isDT
              ? 'Is Draw Things running with its gRPC server enabled? '
                    'Default port 7859.'
              : isComfy
              ? 'Is ComfyUI running? It listens on http://127.0.0.1:8188 '
                    'by default.'
              : 'Is Stable Diffusion WebUI running with the --api flag?',
          onRetry: _testConnection,
        ),
        const SizedBox(height: 8),
        if (isDT) ...[
          Text(
            'gRPC Host / Port',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dtHostController,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  decoration: _deco(hint: '127.0.0.1'),
                  onChanged: (v) {
                    st.imageGenSettings.setDrawThingsGrpcHost(v.trim());
                    rebuildState(() {
                      _connectionOk = null;
                      _localModels = [];
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _dtPortController,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  keyboardType: TextInputType.number,
                  decoration: _deco(),
                  onChanged: (v) {
                    st.imageGenSettings.setDrawThingsGrpcPort(
                      int.tryParse(v) ?? 7859,
                    );
                    rebuildState(() {
                      _connectionOk = null;
                      _localModels = [];
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                widget.editScoped ? 'Edit Model' : 'Checkpoint Model',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!_loadingLocalModels)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  onPressed: _fetchLocalModels,
                  tooltip: 'Refresh model list',
                ),
            ],
          ),
          if (_loadingLocalModels)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            )
          else
            Builder(
              builder: (_) {
                // Offline fallback: show the persisted slot value so the
                // selection is visible before the server is connected.
                final slotValue = widget.editScoped
                    ? st.imageGenSettings.imageGenEditModel
                    : st.imageGenSettings.imageGenModel;
                final dtModels = _localModels.isNotEmpty
                    ? _localModels
                    : (slotValue.isNotEmpty ? [slotValue] : <String>[]);
                if (dtModels.isEmpty) {
                  return Text(
                    'Models appear here once the server is connected.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 10,
                    ),
                  );
                }
                return ModelSlotDropdown(
                  settings: st.imageGenSettings,
                  editSlot: widget.editScoped,
                  keyPrefix: 'dt-checkpoint',
                  decoration: _deco(hint: 'Select'),
                  options: [for (final m in dtModels) (value: m, label: m)],
                );
              },
            ),
          const SizedBox(height: 4),
          Text(
            'Selection is used automatically on the next generation.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
        ] else if (isComfy) ...[
          Text(
            'ComfyUI URL',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextField(
            controller: _comfyUrlController,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: _deco(hint: 'http://127.0.0.1:8188'),
            onChanged: (v) {
              st.imageGenSettings.setComfyUiUrl(v.trim());
              rebuildState(() {
                _connectionOk = null;
                _localModels = [];
              });
            },
            onSubmitted: (_) => _testConnection(),
          ),
          const SizedBox(height: 8),
          Text(
            'Checkpoint Model',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_loadingLocalModels)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            )
          else if (_localModels.isEmpty)
            Text(
              'No models found yet — Retry above once ComfyUI is running.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 10,
              ),
            )
          else
            // Always the CREATE slot — ComfyUI's edit models live in the
            // comfyEdit* workflow slots, never here.
            ModelSlotDropdown(
              settings: st.imageGenSettings,
              editSlot: false,
              keyPrefix: 'comfy-checkpoint',
              decoration: _deco(hint: 'Select'),
              options: [for (final m in _localModels) (value: m, label: m)],
            ),
          const SizedBox(height: 4),
          Text(
            'The model is applied per generation — no separate load step.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
        ] else ...[
          Text(
            'Server URL',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextField(
            controller: _localUrlController,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: _deco(hint: 'http://127.0.0.1:7860'),
            onChanged: (v) {
              st.imageGenSettings.setLocalImageGenUrl(v.trim());
              rebuildState(() => _connectionOk = null);
            },
            onSubmitted: (_) => _testConnection(),
          ),
          const SizedBox(height: 8),
          Text(
            'Checkpoint Model',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_loadingLocalModels)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            )
          else if (_localModels.isEmpty)
            Text(
              'Models appear here once the server is connected.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 10,
              ),
            )
          else
            // Always the CREATE slot — stock A1111 can't instruction-edit,
            // so an edit slot has no meaning here (img2img fallback only).
            ModelSlotDropdown(
              settings: st.imageGenSettings,
              editSlot: false,
              keyPrefix: 'a1111-checkpoint',
              decoration: _deco(hint: 'Select'),
              options: [for (final m in _localModels) (value: m, label: m)],
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (_unloadingModel || _switchingModel)
                      ? null
                      : _unloadModel,
                  child: const Text('Unload', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (_unloadingModel ||
                          _switchingModel ||
                          st.imageGenSettings.imageGenModel.isEmpty)
                      ? null
                      : _switchModel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardOf(context),
                    foregroundColor: AppColors.textPrimary(context),
                  ),
                  child: const Text('Switch', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
        // LoRA (name + weight slider). A1111 injects <lora:name:weight> into
        // the prompt; Draw Things applies it natively via the gRPC config.
        ...[
          Divider(color: AppColors.borderOf(context)),
          const SizedBox(height: 4),
          Text(
            'LoRA',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isDT
                ? 'Applied natively by Draw Things.'
                : 'Via <lora:name:weight> in prompt.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          if (_loadingLoras)
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.formMasterAccent,
              ),
            )
          else
            LoraPicker(
              loras: _localLoras,
              // Family-filter against the slot this surface generates with
              // (the Edit tab pairs LoRAs with the EDIT model on DT).
              checkpointFamily: ImageModelFamily.detectFromName(
                widget.editScoped && isDT
                    ? st.imageGenSettings.imageGenEditModel
                    : st.imageGenSettings.imageGenModel,
              ),
              selected: st.imageGenSettings.imageGenLora,
              weight: st.imageGenSettings.imageGenLoraWeight,
              onSelected: (val) => st.imageGenSettings.setImageGenLora(val),
              onWeightChanged: (v) =>
                  st.imageGenSettings.setImageGenLoraWeight(v),
            ),
        ],
        const SizedBox(height: 8),
        _buildSharedFields(st),
      ],
    );
  }
}
