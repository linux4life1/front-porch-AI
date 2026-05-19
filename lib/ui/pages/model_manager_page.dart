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
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:front_porch_ai/ui/widgets/local_model_card.dart';
import 'package:front_porch_ai/ui/widgets/download_queue_panel.dart';

class ModelManagerPage extends StatefulWidget {
  const ModelManagerPage({super.key});

  @override
  State<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends State<ModelManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Search state
  List<HFModel> _searchResults = [];
  Map<String, HFModel> _modelsWithFiles = {};
  bool _isSearching = false;
  String? _searchError;

  // Local models filter
  String _localFilter = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ModelManager>(context, listen: false).refreshModels();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _modelsWithFiles = {};
      _searchError = null;
    });

    try {
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      final results = await modelManager.searchHFModels(query);

      if (results.isEmpty) {
        setState(() {
          _isSearching = false;
        });
        return;
      }

      // Fetch files for all results
      final modelsWithFiles = await modelManager.fetchFilesForModels(results);

      if (mounted) {
        setState(() {
          _searchResults = results;
          _modelsWithFiles = modelsWithFiles;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = 'Search failed: $e';
        });
      }
    }
  }

  void _onDownload(HFModelFile file) {
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    modelManager.queueDownload(file);
  }

  void _confirmDelete(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Model?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${path.split(Platform.pathSeparator).last}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<ModelManager>(context, listen: false).deleteModel(path);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
      dialogTitle: 'Select a GGUF Model to Import',
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      try {
        await Provider.of<ModelManager>(context, listen: false)
            .importLocalModel(result.files.single.path!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Model imported successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _changeModelsFolder() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Models Folder',
    );
    if (picked != null && mounted) {
      final storage = Provider.of<StorageService>(context, listen: false);
      await storage.setCustomModelsPath(picked);
      if (mounted) {
        Provider.of<ModelManager>(context, listen: false).refreshModels();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Models folder set to: $picked')),
        );
      }
    }
  }

  Future<void> _resetModelsFolder() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    await storage.setCustomModelsPath(null);
    if (mounted) {
      Provider.of<ModelManager>(context, listen: false).refreshModels();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Models folder reset to default.')),
      );
    }
  }

  Future<void> _openModelsFolder() async {
    final url = Uri.directory(Provider.of<ModelManager>(context, listen: false).modelsPath);
    await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final modelManager = Provider.of<ModelManager>(context);
    final hardware = Provider.of<HardwareService>(context);
    final availableVram = hardware.hardwareInfo?.vramMb ?? 4096;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Model Manager'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: () => modelManager.refreshModels(),
            tooltip: 'Scan for new models',
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Models'),
            Tab(text: 'Search / Download'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyModelsTab(modelManager, availableVram),
                _buildSearchTab(modelManager, availableVram),
              ],
            ),
          ),
          // Download queue panel at bottom
          DownloadQueuePanel(
            activeDownloads: modelManager.downloadManager.activeDownloads,
            pendingDownloads: modelManager.downloadManager.pendingDownloads,
            overallProgress: modelManager.downloadManager.overallProgress,
            overallSpeed: modelManager.downloadManager.overallSpeed,
            onPause: modelManager.pauseDownload,
            onResume: modelManager.resumeDownload,
            onCancel: modelManager.cancelDownload,
            onPauseAll: modelManager.pauseAllDownloads,
            onResumeAll: modelManager.resumeAllDownloads,
            onClearCompleted: modelManager.clearCompletedDownloads,
          ),
        ],
      ),
    );
  }

  Widget _buildMyModelsTab(ModelManager modelManager, int availableVram) {
    final localModels = modelManager.localModels
        .where((m) => _localFilter.isEmpty ||
            m.filename.toLowerCase().contains(_localFilter.toLowerCase()))
        .toList();

    return Column(
      children: [
        // Folder controls bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_rounded, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      modelManager.modelsPath,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_to_drive_rounded, size: 18, color: Colors.amberAccent),
                    tooltip: 'Import from Computer',
                    onPressed: _importLocalModel,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_rounded, size: 18, color: Colors.orangeAccent),
                    tooltip: 'Change Models Folder',
                    onPressed: _changeModelsFolder,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  if (Provider.of<StorageService>(context).customModelsPath != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.restore_rounded, size: 18, color: Colors.redAccent),
                      tooltip: 'Reset to Default Folder',
                      onPressed: _resetModelsFolder,
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.white54),
                    tooltip: 'Open in File Manager',
                    onPressed: _openModelsFolder,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Filter field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filter models...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  onChanged: (value) => setState(() => _localFilter = value),
                ),
              ),
            ],
          ),
        ),

        // Status message
        if (modelManager.statusMessage.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.blue.withValues(alpha: 0.1),
            child: Text(
              modelManager.statusMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),

        // Models list
        Expanded(
          child: localModels.isEmpty
              ? _buildEmptyState('No models found', 'Import a model or download from HuggingFace')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: localModels.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final model = localModels[index];
                    return LocalModelCard(
                      model: model,
                      availableVramMb: availableVram,
                      onDelete: () => _confirmDelete(context, model.path),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchTab(ModelManager modelManager, int availableVram) {
    return Column(
      children: [
        // Search bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _searchFocus.hasFocus
                          ? Colors.indigoAccent
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: const InputDecoration(
                      hintText: 'Search HuggingFace models...',
                      hintStyle: TextStyle(color: Colors.white38),
                      prefixIcon: Icon(Icons.search, color: Colors.white38),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isSearching ? null : _performSearch,
                icon: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: Text(_isSearching ? 'Searching...' : 'Search'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.withValues(alpha: 0.3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // Error message
        if (_searchError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _searchError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Results
        Expanded(
          child: _isSearching
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Searching HuggingFace...',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                )
              : _searchResults.isEmpty
                  ? _buildEmptyState(
                      'Search for models',
                      'Enter a model name or architecture to search HuggingFace',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final model = _searchResults[index];
                        final modelWithFiles = _modelsWithFiles[model.id] ?? model;
                        return HFModelCard(
                          model: modelWithFiles,
                          availableVramMb: availableVram,
                          onDownload: _onDownload,
                          downloadingFiles: modelManager.downloadingFiles,
                          downloadedFiles: modelManager.downloadedFilenames,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_download_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
