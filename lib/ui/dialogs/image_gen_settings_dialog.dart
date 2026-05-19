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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';

/// Dialog for configuring image generation settings.
class ImageGenSettingsDialog extends StatefulWidget {
  const ImageGenSettingsDialog({super.key});

  @override
  State<ImageGenSettingsDialog> createState() => _ImageGenSettingsDialogState();
}

class _ImageGenSettingsDialogState extends State<ImageGenSettingsDialog> {
  List<ImageModelInfo> _models = [];
  bool _loadingModels = false;
  final _negativePromptController = TextEditingController();

  // Local backend state
  final _localUrlController = TextEditingController();
  List<String> _localModels = [];
  bool _loadingLocalModels = false;
  bool? _connectionOk;      // null = untested, true = ok, false = failed
  bool _testingConnection = false;
  bool _unloadingModel    = false;
  bool _switchingModel    = false;
  String _modelActionStatus = ''; // feedback message for unload/switch

  // LoRA state (A1111/Forge/SDNext only)
  List<String> _localLoras = [];
  bool _loadingLoras = false;

  // Advanced generation params
  List<String> _localSamplers = [];
  bool _loadingSamplers = false;
  final _seedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _negativePromptController.text = storage.imageGenNegativePrompt;
    _localUrlController.text = storage.localImageGenUrl;
    _seedController.text = storage.imageGenSeed.toString();
    _fetchModels();
    // Pre-fetch local models if already on a local backend
    if (storage.imageGenBackend != 'remote') {
      _fetchLocalModels(storage.localImageGenUrl);
      _fetchLocalSamplers(storage.localImageGenUrl);
    }
  }

  @override
  void dispose() {
    _negativePromptController.dispose();
    _localUrlController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    setState(() => _loadingModels = true);
    final service = Provider.of<ImageGenService>(context, listen: false);
    final models = await service.fetchImageModels();
    if (mounted) {
      setState(() {
        _models = models;
        _loadingModels = false;
      });
    }
  }

  Future<void> _fetchLocalModels(String url) async {
    if (url.isEmpty) return;
    setState(() => _loadingLocalModels = true);
    final service = Provider.of<ImageGenService>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    // Use the backend-specific fetch method so Draw Things gets the right call
    final List<String> models;
    if (storage.imageGenBackend == 'drawthings') {
      models = await service.fetchDrawThingsModels(url);
    } else {
      models = await service.fetchA1111Models(url);
    }
    if (mounted) {
      setState(() {
        _localModels = models;
        _loadingLocalModels = false;
      });
    }
  }

  Future<void> _fetchLocalLoras(String url) async {
    if (url.isEmpty) return;
    setState(() => _loadingLoras = true);
    final service = Provider.of<ImageGenService>(context, listen: false);
    final loras = await service.fetchA1111Loras(url);
    if (mounted) {
      setState(() {
        _localLoras = loras;
        _loadingLoras = false;
      });
    }
  }

  Future<void> _fetchLocalSamplers(String url) async {
    if (url.isEmpty) return;
    setState(() => _loadingSamplers = true);
    final service = Provider.of<ImageGenService>(context, listen: false);
    final samplers = await service.fetchA1111Samplers(url);
    if (mounted) {
      setState(() {
        _localSamplers = samplers;
        _loadingSamplers = false;
      });
    }
  }

  void _randomizeSeed() {
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    _seedController.text = seed.toString();
    Provider.of<StorageService>(context, listen: false).setImageGenSeed(seed);
  }

  Future<void> _testConnection() async {
    final url = _localUrlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testingConnection = true;
      _connectionOk = null;
    });
    final service = Provider.of<ImageGenService>(context, listen: false);
    final ok = await service.testLocalConnection(url);
    if (mounted) {
      setState(() {
        _connectionOk = ok;
        _testingConnection = false;
      });
      if (ok) {
        _fetchLocalModels(url);
        _fetchLocalSamplers(url);
        // Fetch LoRAs for A1111-compatible backends (not Draw Things)
        final storage = Provider.of<StorageService>(context, listen: false);
        if (storage.imageGenBackend != 'drawthings') _fetchLocalLoras(url);
      }
    }
  }

  Future<void> _unloadModel() async {
    final url = _localUrlController.text.trim();
    if (url.isEmpty) return;
    setState(() { _unloadingModel = true; _modelActionStatus = ''; });
    final service = Provider.of<ImageGenService>(context, listen: false);
    final ok = await service.unloadLocalModel(url);
    if (mounted) {
      setState(() {
        _unloadingModel = false;
        _modelActionStatus = ok
            ? '✓ Model unloaded from memory'
            : '⚠ Unload not supported — model may still be in memory';
      });
    }
  }

  Future<void> _switchModel() async {
    final url = _localUrlController.text.trim();
    final storage = Provider.of<StorageService>(context, listen: false);
    final model = storage.imageGenModel;
    if (url.isEmpty || model.isEmpty) return;
    setState(() { _switchingModel = true; _modelActionStatus = 'Unloading current model…'; });
    final service = Provider.of<ImageGenService>(context, listen: false);
    final isDrawThings = storage.imageGenBackend == 'drawthings';
    late bool ok;
    if (isDrawThings) {
      // Draw Things gRPC loads model during generation via FlatBuffer config.
      // No separate switch call needed — just succeed immediately.
      ok = true;
    } else {
      // switchLocalModel() already calls unload then options internally
      ok = await service.switchLocalModel(url, model);
    }
    if (mounted) {
      setState(() {
        _switchingModel = false;
        _modelActionStatus = ok
            ? (isDrawThings ? '✓ Model will be loaded during generation' : '✓ Switched to: $model')
            : '✗ Failed to switch — check the server logs';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        return Dialog(
          backgroundColor: const Color(0xFF1F2937),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 540,
            constraints: const BoxConstraints(maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white10)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                      const SizedBox(width: 12),
                      const Text('Image Generation Settings',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Enable toggle ─────────────────────────────
                        SwitchListTile(
                          title: const Text('Enable Image Generation',
                              style: TextStyle(color: Colors.white)),
                          subtitle: const Text(
                              'Add image generation button to chat toolbar',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          value: storage.imageGenEnabled,
                          activeTrackColor: Colors.purpleAccent,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => storage.setImageGenEnabled(val),
                        ),

                        const SizedBox(height: 16),

                        // ── Backend selector ──────────────────────────
                        const Text('Image Source',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _buildBackendSelector(storage),

                        const SizedBox(height: 20),

                        // ── Per-backend config panel ──────────────────
                        if (storage.imageGenBackend == 'remote')
                          _buildRemotePanel(storage)
                        else
                          _buildLocalPanel(storage),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Backend selector ────────────────────────────────────────────────

  Widget _buildBackendSelector(StorageService storage) {
    final backends = ImageGenBackend.values;
    return Row(
      children: backends.map((b) {
        final isSelected = storage.imageGenBackend == b.key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                right: b == backends.last ? 0 : 8),
            child: GestureDetector(
              onTap: () {
                storage.setImageGenBackend(b.key);
                // Load local models when switching to a local backend
                if (b != ImageGenBackend.remote) {
                  _fetchLocalModels(storage.localImageGenUrl);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.purpleAccent.withValues(alpha: 0.25)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Colors.purpleAccent
                        : Colors.white10,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      b == ImageGenBackend.remote
                          ? Icons.cloud_outlined
                          : b == ImageGenBackend.drawThings
                              ? Icons.apple
                              : Icons.computer_outlined,
                      size: 18,
                      color: isSelected
                          ? Colors.purpleAccent
                          : Colors.white38,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      b.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? Colors.purpleAccent
                            : Colors.white38,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
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

  // ── Remote backend panel (existing) ────────────────────────────────

  Widget _buildRemotePanel(StorageService storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info box
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                storage.remoteApiKey.isNotEmpty
                    ? Icons.check_circle
                    : Icons.info_outline,
                color: storage.remoteApiKey.isNotEmpty
                    ? Colors.green
                    : Colors.amber,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  storage.remoteApiKey.isNotEmpty
                      ? 'Using your remote API credentials for image generation.'
                      : 'Requires a remote API key — configure one in the Backend settings.',
                  style: TextStyle(
                    color: storage.remoteApiKey.isNotEmpty
                        ? Colors.white38
                        : Colors.amber,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Image Model selector
        const Text('Image Model',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _models
                        .any((m) => m.id == storage.imageGenModel)
                    ? storage.imageGenModel
                    : null,
                dropdownColor: const Color(0xFF374151),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                menuMaxHeight: 400,
                decoration: InputDecoration(
                  hintText: _loadingModels
                      ? 'Loading models...'
                      : _models.isEmpty
                          ? 'No image models found'
                          : 'Select a model',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: _buildGroupedModelItems(),
                onChanged: (val) {
                  if (val != null) storage.setImageGenModel(val);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _loadingModels
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.purpleAccent))
                  : const Icon(Icons.refresh, color: Colors.white54),
              tooltip: 'Refresh models',
              onPressed: _loadingModels ? null : _fetchModels,
            ),
          ],
        ),

        // Manual model name override
        const SizedBox(height: 8),
        TextField(
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Or type a model name manually...',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            isDense: true,
          ),
          controller: TextEditingController(text: storage.imageGenModel),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) storage.setImageGenModel(val.trim());
          },
        ),

        const SizedBox(height: 20),
        _buildSharedFields(storage),
      ],
    );
  }

  // ── Local backend panel (A1111 / Draw Things) ──────────────────────

  Widget _buildLocalPanel(StorageService storage) {
    final isDrawThings = storage.imageGenBackend == 'drawthings';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDrawThings
                ? Colors.purple.withValues(alpha: 0.08)
                : Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: isDrawThings ? Colors.purpleAccent : Colors.blue,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isDrawThings ? Icons.apple : Icons.info_outline,
                color: isDrawThings ? Colors.purpleAccent : Colors.blue,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDrawThings
                      ? 'Open Draw Things → Settings → Advanced → enable HTTP API Server. '
                        'If models load below, selecting one will switch Draw Things to it '
                        'before each generation — a fresh "project" every time. '
                        'If no models appear, select your model in Draw Things directly.'
                      : 'Start AUTOMATIC1111 with the --api flag (e.g. python launch.py --api). '
                        'Selecting a checkpoint below will switch models before each generation '
                        'via POST /sdapi/v1/options.',
                  style: TextStyle(
                    color: isDrawThings ? Colors.white54 : Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Server URL + test button
        const Text('Server URL',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _localUrlController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: isDrawThings
                      ? 'http://127.0.0.1:7860'
                      : 'http://127.0.0.1:7860',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                  suffixIcon: _connectionOk == null
                      ? null
                      : Icon(
                          _connectionOk!
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: _connectionOk!
                              ? Colors.green
                              : Colors.redAccent,
                          size: 18,
                        ),
                ),
                onChanged: (val) {
                  storage.setLocalImageGenUrl(val.trim());
                  // Reset connection indicator on edit
                  setState(() => _connectionOk = null);
                },
                onSubmitted: (_) => _testConnection(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _testingConnection ? null : _testConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              child: _testingConnection
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Test', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Checkpoint / model selector
        const Text('Checkpoint Model',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Fetched from the local server after pressing Test.',
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
        const SizedBox(height: 8),
        if (_loadingLocalModels)
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.purpleAccent),
            ),
          )
        else if (_localModels.isEmpty)
          Text(
            isDrawThings
                ? 'No models listed via API — switch the model directly in Draw Things, then press "Load Selected Model" to apply it.'
                : 'No models found — test the connection above to fetch them.',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _localModels.contains(storage.imageGenModel)
                ? storage.imageGenModel
                : null,
            dropdownColor: const Color(0xFF374151),
            style: const TextStyle(color: Colors.white),
            isExpanded: true,
            menuMaxHeight: 300,
            decoration: InputDecoration(
              hintText: 'Select a checkpoint',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
            items: _localModels
                .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white))))
                .toList(),
            onChanged: (val) {
              if (val != null) storage.setImageGenModel(val);
            },
          ),

        const SizedBox(height: 16),

        // Model action buttons.
        // Draw Things does NOT support /sdapi/v1/unload-checkpoint —
        // it manages memory itself when a new model is loaded.
        // Show a single "Load Selected" button for Draw Things;
        // show Unload + Switch for A1111 which supports both.
        if (isDrawThings) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _switchingModel
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Load Selected Model in Draw Things',
                  style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent.withValues(alpha: 0.25),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.purpleAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: (_switchingModel || storage.imageGenModel.isEmpty)
                  ? null
                  : _switchModel,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sends the selected checkpoint to Draw Things via POST /sdapi/v1/options. '
            'Draw Things will replace the current model automatically.',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _unloadingModel
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                      : const Icon(Icons.memory, size: 16, color: Colors.redAccent),
                  label: const Text('Unload Model',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: (_unloadingModel || _switchingModel) ? null : _unloadModel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: _switchingModel
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Switch to Selected',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent.withValues(alpha: 0.25),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.purpleAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: (_unloadingModel || _switchingModel || storage.imageGenModel.isEmpty)
                      ? null
                      : _switchModel,
                ),
              ),
            ],
          ),
        ],

        if (_modelActionStatus.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _modelActionStatus,
            style: TextStyle(
              fontSize: 11,
              color: _modelActionStatus.startsWith('✓')
                  ? Colors.greenAccent
                  : _modelActionStatus.startsWith('⚠')
                      ? Colors.amber
                      : Colors.redAccent,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // \u2500\u2500 LoRA selector (A1111 / Forge / SDNext only) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
        if (!isDrawThings) ...[
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          const Text('LoRA',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Applied to every generation via <lora:name:weight> in the prompt.',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
          const SizedBox(height: 8),
          if (_loadingLoras)
            const SizedBox(
              height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent),
            )
          else
            DropdownButtonFormField<String>(
              value: _localLoras.contains(storage.imageGenLora)
                  ? storage.imageGenLora
                  : (storage.imageGenLora.isEmpty ? '' : null),
              dropdownColor: const Color(0xFF374151),
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              menuMaxHeight: 300,
              decoration: InputDecoration(
                hintText: _localLoras.isEmpty
                    ? 'Test connection to load LoRAs'
                    : 'Select a LoRA (optional)',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('\u2014 None \u2014',
                    style: TextStyle(color: Colors.white54))),
                ..._localLoras.map((l) => DropdownMenuItem(
                    value: l,
                    child: Text(l,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white)))),
              ],
              onChanged: (val) {
                if (val != null) storage.setImageGenLora(val);
              },
            ),

          // Weight slider — only shown when a LoRA is selected
          if (storage.imageGenLora.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Weight', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: storage.imageGenLoraWeight,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    activeColor: Colors.purpleAccent,
                    inactiveColor: Colors.white12,
                    onChanged: (val) => storage.setImageGenLoraWeight(val),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    storage.imageGenLoraWeight.toStringAsFixed(2),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],

        _buildSharedFields(storage),


      ],
    );
  }

  // ── Shared size / style / negative-prompt fields ───────────────────

  Widget _buildSharedFields(StorageService storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image Size
        const Text('Image Size',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildSizeSelector(storage),

        const SizedBox(height: 20),

        // Default Style
        const Text('Default Style',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue:
              ImageGenService.styleLabels.containsKey(storage.imageGenStyle)
                  ? storage.imageGenStyle
                  : 'photorealistic',
          dropdownColor: const Color(0xFF374151),
          style: const TextStyle(color: Colors.white),
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          items: ImageGenService.styleLabels.entries.map((e) {
            return DropdownMenuItem(
              value: e.key,
              child: Text(e.value),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) storage.setImageGenStyle(val);
          },
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Pre-selected when generating images. Can be changed per generation.',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ),

        const SizedBox(height: 20),
        const Text('Prompt Format',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: storage.imageGenPromptParadigm,
          dropdownColor: const Color(0xFF374151),
          style: const TextStyle(color: Colors.white),
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(
              value: 'natural',
              child: Text('Natural Language (FLUX / SD3)'),
            ),
            DropdownMenuItem(
              value: 'tags',
              child: Text('Danbooru Tags (SD 1.5 / Anime)'),
            ),
          ],
          onChanged: (val) {
            if (val != null) storage.setImageGenPromptParadigm(val);
          },
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'How the LLM formats generated prompts. Use Tags for older anime models.',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ),

        const SizedBox(height: 20),
        const Text('Default Negative Prompt',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _negativePromptController,
          maxLines: 2,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'e.g. blurry, low quality, watermark, text',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          onChanged: (val) => storage.setImageGenNegativePrompt(val),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Applied automatically to all generations. Leave empty to skip.',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ),

        const SizedBox(height: 20),

        // ── Advanced Generation Settings ─────────────────────────────
        Consumer<StorageService>(
          builder: (context, storage, _) {
            final isLocal = storage.imageGenBackend != 'remote';
            return ExpansionTile(
              title: const Text('Advanced Generation Settings',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              subtitle: Text(isLocal ? 'Applied to local A1111/Draw Things generations' : 'Configure your local server first',
                  style: TextStyle(color: Colors.white24, fontSize: 10)),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
              children: isLocal ? _buildAdvancedFields(storage) : [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Select a local backend (A1111 or Draw Things) above to configure generation parameters.',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ── Grouped remote model dropdown items ─────────────────────────────

  /// Build dropdown items grouped by free (subscription-included) and paid.
  List<DropdownMenuItem<String>> _buildGroupedModelItems() {
    final freeModels = _models.where((m) => !m.isPaid).toList();
    final paidModels = _models.where((m) => m.isPaid).toList();
    final items = <DropdownMenuItem<String>>[];

    // ── Free models section ──
    if (freeModels.isNotEmpty) {
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__header_free__',
        child: Text('── Included with Pro Subscription ──',
            style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      ));
      for (final m in freeModels) {
        items.add(DropdownMenuItem(
          value: m.id,
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.pricingInfo != null ? '${m.displayName} — ${m.pricingInfo}' : m.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Text('Free', style: TextStyle(color: Colors.green.shade300, fontSize: 10)),
            ],
          ),
        ));
      }
    }

    // ── Paid models section ──
    if (paidModels.isNotEmpty) {
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__header_paid__',
        child: Text('── Pay Per Prompt (Check OpenRouter for Credit Requirements) ──',
            style: TextStyle(
                color: Colors.amber.shade300,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      ));
      for (final m in paidModels) {
        items.add(DropdownMenuItem(
          value: m.id,
          child: Row(
            children: [
              const Icon(Icons.attach_money, size: 14, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.pricingInfo != null ? '${m.displayName} — ${m.pricingInfo}' : m.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Text('Paid', style: TextStyle(color: Colors.amber.shade300, fontSize: 10)),
            ],
          ),
        ));
      }
    }

    return items;
  }

  /// Size selector — chip-style buttons.
  Widget _buildSizeSelector(StorageService storage) {
    const sizes        = ['512x512', '768x768', '1024x1024', '1536x1024', '1024x1536'];
    const labels       = ['512²',   '768²',    '1024²',     '1536×1024', '1024×1536'];
    const descriptions = ['Small',  'Medium',  'Square',    'Landscape', 'Portrait'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(sizes.length, (i) {
        final selected = storage.imageGenSize == sizes[i];
        return GestureDetector(
          onTap: () => storage.setImageGenSize(sizes[i]),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.purpleAccent.withValues(alpha: 0.3)
                  : Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: Colors.purpleAccent, width: 1)
                  : Border.all(color: Colors.white10, width: 1),
            ),
            child: Column(
              children: [
                Text(labels[i],
                    style: TextStyle(
                      color: selected ? Colors.purpleAccent : Colors.white54,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    )),
                const SizedBox(height: 2),
                Text(descriptions[i],
                    style: TextStyle(
                      color: selected ? Colors.white38 : Colors.white24,
                      fontSize: 9,
                    )),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── Advanced generation fields ──────────────────────────────────────

  List<Widget> _buildAdvancedFields(StorageService storage) {
    return [
      // Steps slider
      const SizedBox(height: 8),
      Row(
        children: [
          const Text('Steps', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: storage.imageGenSteps.toDouble(),
              min: 5,
              max: 50,
              divisions: 45,
              activeColor: Colors.purpleAccent,
              inactiveColor: Colors.white12,
              onChanged: (val) => storage.setImageGenSteps(val.round()),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(storage.imageGenSteps.toString(),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.end),
          ),
        ],
      ),

      // CFG Scale slider
      Row(
        children: [
          const Text('CFG Scale', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: storage.imageGenCfgScale,
              min: 1.0,
              max: 20.0,
              divisions: 190,
              activeColor: Colors.purpleAccent,
              inactiveColor: Colors.white12,
              onChanged: (val) => storage.setImageGenCfgScale(val),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(storage.imageGenCfgScale.toStringAsFixed(1),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.end),
          ),
        ],
      ),

      // Sampler dropdown
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(
            flex: 2,
            child: Text('Sampler', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: _localSamplers.contains(storage.imageGenSampler)
                  ? storage.imageGenSampler
                  : (storage.imageGenSampler.isNotEmpty ? null : 'Euler a'),
              dropdownColor: const Color(0xFF374151),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              isExpanded: true,
              decoration: InputDecoration(
                hintText: _loadingSamplers ? 'Loading...' : 'Select sampler',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              items: _localSamplers.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (val) {
                if (val != null) storage.setImageGenSampler(val);
              },
            ),
          ),
        ],
      ),

      // Seed field with randomize button
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(
            flex: 2,
            child: Text('Seed', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _seedController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '-1 = random',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final seed = int.tryParse(val) ?? -1;
                      storage.setImageGenSeed(seed);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.casino_outlined, size: 18, color: Colors.purpleAccent),
                  tooltip: 'Randomize seed',
                  onPressed: _randomizeSeed,
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}
