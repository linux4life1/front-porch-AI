// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HuggingFace search and queue-download. The local list stays
// on model_manager_page.dart.

part of 'model_manager_page.dart';

extension _ModelManagerPageDownload on _ModelManagerPageState {
  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    rebuildState(() {
      _isSearching = true;
      _searchResults = [];
      _modelsWithFiles = {};
      _searchError = null;
    });

    try {
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      final results = await modelManager.searchHFModels(query);

      if (results.isEmpty) {
        rebuildState(() {
          _isSearching = false;
        });
        return;
      }

      // Fetch files for all results
      final modelsWithFiles = await modelManager.fetchFilesForModels(results);

      if (mounted) {
        rebuildState(() {
          _searchResults = results;
          _modelsWithFiles = modelsWithFiles;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        rebuildState(() {
          _isSearching = false;
          _searchError = 'Search failed: $e';
        });
      }
    }
  }

  void _onDownload(HFModelFile file) {
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    modelManager.queueDownload(file);
    // Downloading a model IS local intent: fetch the managed engine alongside
    // it (a no-op when installed/downloading/remote) so both finish together
    // instead of the engine wait landing right when the user starts chatting.
    Provider.of<BackendManager>(context, listen: false).ensureEngineInstalled();
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
}
