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
import 'package:url_launcher/url_launcher.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:front_porch_ai/ui/widgets/local_model_card.dart';
import 'package:front_porch_ai/ui/widgets/download_queue_panel.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

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
        backgroundColor: AppColors.cardOf(context),
        title: Text(
          'Delete Model?',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Are you sure you want to delete ${path.split(Platform.pathSeparator).last}?',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Provider.of<ModelManager>(
                context,
                listen: false,
              ).deleteModel(path);
              Navigator.pop(context);
            },
            child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalModel() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['gguf'],
      dialogTitle: 'Select a GGUF Model to Import',
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      try {
        await Provider.of<ModelManager>(
          context,
          listen: false,
        ).importLocalModel(result.files.single.path!);
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
    final picked = await PickerPrefs.getDirectoryPath(
      category: PickerPrefs.catDirectory,
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
    final url = Uri.directory(
      Provider.of<ModelManager>(context, listen: false).modelsPath,
    );
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
        title: Text(
          'Model Manager',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.formMasterAccent),
            onPressed: () => modelManager.refreshModels(),
            tooltip: 'Scan for new models',
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.textPrimary(context),
          unselectedLabelColor: AppColors.textSecondary(context),
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
        .where(
          (m) =>
              _localFilter.isEmpty ||
              m.filename.toLowerCase().contains(_localFilter.toLowerCase()),
        )
        .toList();

    return Column(
      children: [
        // Folder controls bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            border: Border(
              bottom: BorderSide(
                color: AppColors.borderOf(context).withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    color: AppColors.iconSecondary(context),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      modelManager.modelsPath,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_to_drive_rounded,
                      size: 18,
                      color: Colors.amberAccent,
                    ),
                    tooltip: 'Import from Computer',
                    onPressed: _importLocalModel,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.drive_file_move_rounded,
                      size: 18,
                      color: Colors.orangeAccent,
                    ),
                    tooltip: 'Change Models Folder',
                    onPressed: _changeModelsFolder,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  if (Provider.of<StorageService>(context).customModelsPath !=
                      null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.restore_rounded,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Reset to Default Folder',
                      onPressed: _resetModelsFolder,
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.folder_open_rounded,
                      size: 18,
                      color: AppColors.iconSecondary(context),
                    ),
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
                  color: AppColors.surfaceContainerOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Filter models...',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary(context),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.iconSecondary(context),
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
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
            color: AppColors.resolve(
              context,
              Colors.blue.withValues(alpha: 0.1),
              Colors.blue.withValues(alpha: 0.08),
            ),
            child: Text(
              modelManager.statusMessage,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
              ),
            ),
          ),

        // Models list
        Expanded(
          child: localModels.isEmpty
              ? _buildEmptyState(
                  'No models found',
                  'Import a model or download from HuggingFace',
                )
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
            color: AppColors.surfaceContainerOf(context),
            border: Border(
              bottom: BorderSide(
                color: AppColors.borderOf(context).withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _searchFocus.hasFocus
                          ? Colors.indigoAccent
                          : AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Search HuggingFace models...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(context),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.iconSecondary(context),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(color: AppColors.textPrimary(context)),
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
                  backgroundColor: AppColors.resolve(
                    context,
                    Colors.indigo.withValues(alpha: 0.3),
                    Colors.indigo.withValues(alpha: 0.15),
                  ),
                  foregroundColor: AppColors.resolve(
                    context,
                    Colors.white,
                    Colors.black87,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
            color: AppColors.resolve(
              context,
              Colors.red.withValues(alpha: 0.1),
              Colors.red.withValues(alpha: 0.08),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _searchError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Results
        Expanded(
          child: _isSearching
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Searching HuggingFace...',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
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
              color: AppColors.resolve(
                context,
                Colors.white.withValues(alpha: 0.03),
                Colors.black.withValues(alpha: 0.03),
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_download_rounded,
              size: 48,
              color: AppColors.iconSecondary(context).withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
