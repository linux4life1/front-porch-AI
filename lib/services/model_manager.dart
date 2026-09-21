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

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/utils/utils.dart'; // GGUFModelInfo + parser, StartupTrace
import 'package:front_porch_ai/models/models.dart';

/// Manages local model files and HuggingFace model discovery.
///
/// Provides:
/// - Local model scanning and metadata
/// - HuggingFace search and file listing
/// - Download queue management via DownloadManager
/// - KV cache parsing for VRAM estimation
class ModelManager extends ChangeNotifier {
  final StorageService _storageService;
  final DownloadManager _downloadManager;

  /// Raw list of local model file entities.
  List<FileSystemEntity> _models = [];

  /// Cached KV bytes per token for rapid UI rendering.
  final Map<String, int> _kvBytesCache = {};

  /// Status message for import operations.
  String _statusMessage = '';

  // Legacy getters for backward compatibility
  List<FileSystemEntity> get models => List.unmodifiable(_models);
  String get statusMessage => _statusMessage;
  String get modelsPath => path.normalize(_storageService.modelsDir.path);

  /// Download manager instance for queue operations.
  DownloadManager get downloadManager => _downloadManager;

  /// Local models as typed [LocalModelInfo] objects.
  List<LocalModelInfo> get localModels {
    return _models.map((e) => LocalModelInfo.fromEntity(e)).toList();
  }

  /// Set of downloaded filenames (for UI checkmarks).
  Set<String> get downloadedFilenames {
    return _models
        .map((e) => e.path.split(Platform.pathSeparator).last)
        .toSet();
  }

  /// Map of currently downloading files.
  Map<String, DownloadTask> get downloadingFiles {
    final map = <String, DownloadTask>{};
    for (final task in _downloadManager.queue) {
      if (task.state.isActive || task.state == DownloadTaskState.paused) {
        map[task.filename] = task;
      }
    }
    return map;
  }

  ModelManager(this._storageService, this._downloadManager) {
    _init();
    _storageService.addListener(_onStorageChanged);
    _downloadManager.addListener(_onDownloadChanged);
  }

  // StorageService notifies on EVERY settings mutation, but a full recursive
  // model-directory rescan (synchronous listSync on the UI isolate) only
  // matters when the models directory itself moved — re-scanning per notify
  // made flipping any unrelated settings toggle walk the whole models dir.
  String? _lastScannedRoot;
  void _onStorageChanged() {
    final root = _storageService.rootPath;
    if (root == _lastScannedRoot) return;
    _lastScannedRoot = root;
    _init();
  }

  // Completed-task ids we have already scanned for. Progress ticks notify
  // on every chunk — rescanning the models dir then would hitch Settings.
  final Set<String> _seenCompletedDownloadIds = {};

  /// Notifies listeners when download state changes. A newly completed
  /// download is the one true door into [refreshModels] — Settings → Model
  /// Selection reads [models], so a rescan is what makes the file appear.
  void _onDownloadChanged() {
    final completedIds = {
      for (final task in _downloadManager.completedDownloads) task.id,
    };
    final discovered = completedIds.difference(_seenCompletedDownloadIds);
    _seenCompletedDownloadIds
      ..clear()
      ..addAll(completedIds);
    notifyListeners();
    if (discovered.isNotEmpty) {
      unawaited(refreshModels());
    }
  }

  /// Retrieves the exact Bytes Per Token required for KV Cache
  /// by parsing the GGUF file headers natively.
  Future<int?> getKvCacheBytesPerToken(String filePath) async {
    if (_kvBytesCache.containsKey(filePath)) {
      return _kvBytesCache[filePath];
    }

    try {
      final bytes = await GGUFParser.getKvCacheBytesPerToken(filePath);
      if (bytes != null) {
        _kvBytesCache[filePath] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Synchronous fetch for KV bytes from cache.
  int? getCachedKvBytesPerToken(String filePath) {
    return _kvBytesCache[filePath];
  }

  /// Cache for full GGUF architecture info (nLayers + kv bytes + helpers).
  final Map<String, GGUFModelInfo> _ggufInfoCache = {};

  /// Negative cache: files that yielded no parseable arch info, so we don't
  /// re-parse (and re-log) them on every UI rebuild.
  final Set<String> _ggufInfoUnparseable = {};

  /// Retrieves full architectural info (including real `nLayers` / block_count)
  /// by parsing the GGUF file. Populates an internal cache for fast subsequent
  /// calls (used by the layer solver / Auto-Configure).
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) async {
    if (_ggufInfoCache.containsKey(filePath)) {
      return _ggufInfoCache[filePath];
    }
    // A file that yields no arch info is attempted once, then negative-cached —
    // otherwise every rebuild re-parses and re-logs, spamming the console.
    if (_ggufInfoUnparseable.contains(filePath)) return null;

    try {
      final info = await GGUFParser.getModelArchitectureInfo(filePath);
      if (info != null) {
        _ggufInfoCache[filePath] = info;
      } else {
        _ggufInfoUnparseable.add(filePath);
      }
      return info;
    } catch (_) {
      _ggufInfoUnparseable.add(filePath);
      return null;
    }
  }

  /// Synchronous fetch for full GGUF architecture info from cache.
  GGUFModelInfo? getCachedModelArchitectureInfo(String filePath) {
    return _ggufInfoCache[filePath];
  }

  @override
  void dispose() {
    _storageService.removeListener(_onStorageChanged);
    _downloadManager.removeListener(_onDownloadChanged);
    super.dispose();
  }

  Future<void> _init() async {
    await refreshModels();
  }

  /// Scans the models directory for .gguf files.
  Future<void> refreshModels() async {
    if (_storageService.rootPath == null) return;
    final traceStart = DateTime.now();
    final modelDir = _storageService.modelsDir;

    if (await modelDir.exists()) {
      try {
        // Off the UI isolate: this walk used to listSync + resolve symlinks
        // recursively on the main thread (a visible startup/settings hitch on
        // big or networked model dirs). Entities rebuilt from paths — File
        // objects don't cross isolates.
        final paths = await compute(_scanGgufPathsSync, modelDir.path);
        _models = [for (final p in paths) File(p)];
      } catch (e) {
        print('AG_DEBUG: Error scanning models: $e');
        _models = [];
      }
    } else {
      _models = [];
    }
    notifyListeners();
    StartupTrace.mark(
      'ModelManager.refreshModels — ${_models.length} models in '
      '${DateTime.now().difference(traceStart).inMilliseconds}ms',
    );
  }

  /// Imports a local .gguf file into the models directory.
  Future<void> importLocalModel(String filePath) async {
    final sourceFile = File(filePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file does not exist');
    }

    if (!filePath.toLowerCase().endsWith('.gguf')) {
      throw Exception('File must be a .gguf model');
    }

    final modelDir = _storageService.modelsDir;
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final fileName = path.basename(filePath);
    final destinationPath = path.join(modelDir.path, fileName);

    _statusMessage = 'Importing $fileName...';
    notifyListeners();

    try {
      await sourceFile.copy(destinationPath);
      _statusMessage = 'Imported $fileName';
      await refreshModels();
    } catch (e) {
      _statusMessage = 'Import failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// HuggingFace endpoint root. A static seam, not a constructor param: the
  /// three URL builders (search, tree, download in [HFModelFile.fromApiMap])
  /// were hardcoded, which made the search/download journey untestable —
  /// the E2E suite points this at a local fake server.
  @visibleForTesting
  static String hfBaseUrl = 'https://huggingface.co';

  /// Searches HuggingFace for models matching the query.
  /// Returns typed [HFModel] objects.
  Future<List<HFModel>> searchHFModels(String query, {int limit = 20}) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      '$hfBaseUrl/api/models?search=$encoded&filter=gguf,text-generation&limit=$limit&full=true',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((m) => HFModel.fromSearchResult(m as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('HF Search Error: $e');
    }
    return [];
  }

  /// Gets the list of GGUF files for a HuggingFace repository.
  /// Returns typed [HFModelFile] objects.
  Future<List<HFModelFile>> getModelFiles(String repoId) async {
    final url = Uri.parse('$hfBaseUrl/api/models/$repoId/tree/main');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .where((f) => f['path'].toString().endsWith('.gguf'))
            .map(
              (f) => HFModelFile.fromApiMap(
                f as Map<String, dynamic>,
                repoId,
                baseUrl: hfBaseUrl,
              ),
            )
            .toList();
      }
    } catch (e) {
      print('HF Files Error: $e');
    }
    return [];
  }

  /// Fetches files for multiple repositories concurrently.
  /// Returns a map of repoId -> HFModel with files populated.
  Future<Map<String, HFModel>> fetchFilesForModels(List<HFModel> models) async {
    final results = <String, HFModel>{};

    for (final model in models) {
      try {
        final files = await getModelFiles(model.id);
        results[model.id] = model.withFiles(files);
      } catch (e) {
        print('Failed to fetch files for ${model.id}: $e');
        results[model.id] = model; // Return model without files
      }
    }

    return results;
  }

  /// Adds a model file to the download queue.
  /// Returns the created [DownloadTask].
  DownloadTask queueDownload(HFModelFile file) {
    return _downloadManager.addDownload(
      url: file.downloadUrl,
      filename: file.filename,
      repoId: file.repoId,
    );
  }

  /// Pauses a download by task ID.
  bool pauseDownload(String taskId) {
    return _downloadManager.pauseDownload(taskId);
  }

  /// Resumes a download by task ID.
  bool resumeDownload(String taskId) {
    return _downloadManager.resumeDownload(taskId);
  }

  /// Cancels a download by task ID.
  bool cancelDownload(String taskId) {
    return _downloadManager.cancelDownload(taskId);
  }

  /// Removes a completed/failed download from the queue.
  bool removeDownload(String taskId) {
    return _downloadManager.removeDownload(taskId);
  }

  /// Pauses all active downloads.
  void pauseAllDownloads() {
    _downloadManager.pauseAll();
  }

  /// Resumes all paused downloads.
  void resumeAllDownloads() {
    _downloadManager.resumeAll();
  }

  /// Clears completed downloads from the queue.
  void clearCompletedDownloads() {
    _downloadManager.clearCompleted();
  }

  /// Deletes a local model file.
  Future<void> deleteModel(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      await refreshModels();
    }
  }

  /// Gets recommended search queries based on available VRAM.
  List<String> getRecommendedSearchQueries(int vramMb) {
    final queries = <String>[];

    if (vramMb < 4000) {
      queries.addAll(['TinyLlama', 'Phi-2', 'Qwen-1.5-1.8B']);
    } else if (vramMb < 8000) {
      queries.addAll(['Mistral-7B', 'Llama-2-7b-chat', 'Gemma-7b']);
    } else if (vramMb < 12000) {
      queries.addAll(['Mistral-Nemo', 'Solar-10.7B', 'Yi-9B']);
    } else if (vramMb < 16000) {
      queries.addAll(['Mixtral-8x7B', 'Llama-2-13b', 'Command R']);
    } else {
      queries.addAll(['Llama-3-70B', 'Mixtral-8x22B', 'Midnight-Miqu']);
    }

    return queries;
  }

  // Legacy method - kept for backward compatibility
  @Deprecated('Use queueDownload with HFModelFile instead')
  Future<List<Map<String, dynamic>>> searchHFModelsLegacy(String query) async {
    final models = await searchHFModels(query);
    return models
        .map(
          (m) => {
            'id': m.id,
            'author': m.author,
            'likes': m.likes,
            'downloads': m.downloads,
          },
        )
        .toList();
  }

  // Legacy method - kept for backward compatibility
  @Deprecated('Use getModelFiles which returns HFModelFile instead')
  Future<List<Map<String, String>>> getModelFilesLegacy(String repoId) async {
    final files = await getModelFiles(repoId);
    return files
        .map(
          (f) => {
            'filename': f.filename,
            'url': f.downloadUrl,
            'size': f.sizeBytes.toString(),
          },
        )
        .toList();
  }
}

/// Isolate entry for the recursive .gguf scan (used via compute above).
/// Same traversal the old in-place _safeRecursiveScan did: follow links,
/// dedupe by canonical path, skip inaccessible directories.
List<String> _scanGgufPathsSync(String rootPath) {
  final seen = <String>{};
  final results = <String>[];
  void walk(Directory dir) {
    try {
      for (final entity in dir.listSync(followLinks: true)) {
        if (entity is Directory) {
          walk(entity);
        } else if (entity.path.toLowerCase().endsWith('.gguf')) {
          String canonical;
          try {
            canonical = File(entity.path).resolveSymbolicLinksSync();
          } catch (_) {
            canonical = entity.path;
          }
          if (seen.add(canonical)) {
            results.add(entity.path);
          }
        }
      }
    } catch (e) {
      print('AG_DEBUG: Skipping inaccessible directory: ${dir.path} ($e)');
    }
  }

  walk(Directory(rootPath));
  return results;
}
