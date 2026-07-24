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
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/embedding/native_embedding_engine.dart';
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Service that generates text embeddings (numerical vectors) for RAG memory retrieval.
///
/// Runs nomic-embed-text-v1.5 fully in-process via onnxruntime (phase 5 of
/// docs/design/sidecar-retirement.md — the Rust embed_server is gone,
/// completing the retirement: the app spawns no helper processes at all).
/// The engine is golden-pinned to the retired server's exact vectors, so
/// every embedding already stored in users' memory databases keeps
/// comparing correctly. Existing installs reuse the fastembed model cache
/// the server downloaded; fresh installs download the model here
/// ([runSetup], driven by the RAG consent dialog).
class EmbeddingService extends ChangeNotifier {
  final StorageService _storage;
  final NativeEmbeddingEngine _native = NativeEmbeddingEngine();
  ({String model, String vocab})? _files;

  bool _available = false;
  int _dimensions = 0;
  String? _lastEngineError;

  static const String _hfBase =
      'https://huggingface.co/nomic-ai/nomic-embed-text-v1.5/resolve/main';

  bool get isAvailable => _available;
  String get activeSource => _available ? 'onnx' : 'none';
  int get dimensions => _dimensions;

  /// Whether the model files exist on disk (fastembed cache or the
  /// app-managed download dir) — drives the sidebar status line.
  bool get modelOnDisk =>
      (_files ??= NativeEmbeddingEngine.resolveModelFiles(
        _storage.rootPath,
      )) !=
      null;

  EmbeddingService(this._storage);

  // ---- Setup / download state (consumed by RagSetupDialog) ----

  bool _settingUp = false;
  String _setupStatus = '';
  double _setupProgress = -1; // -1 = indeterminate
  String? _setupError;

  bool get isSettingUp => _settingUp;
  String get setupStatus => _setupStatus;
  double get setupProgress => _setupProgress;
  String? get setupError => _setupError;

  void clearSetupError() {
    _setupError = null;
    notifyListeners();
  }

  /// Downloads the model if it isn't on disk, then loads + verifies the
  /// engine. Progress/status/error surface through the getters above.
  /// Returns true when embeddings are ready.
  Future<bool> runSetup() async {
    if (_settingUp) return false;
    _settingUp = true;
    _setupError = null;
    _setupProgress = -1;
    _setupStatus = 'Checking for the embedding model...';
    notifyListeners();

    try {
      _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
      if (_files == null) {
        final root = _storage.rootPath;
        if (root == null) {
          throw StateError('storage not initialized');
        }
        final dir = Directory(
          p.join(root, 'models', 'embeddings', 'nomic-v1_5'),
        );
        await dir.create(recursive: true);
        _setupStatus = 'Downloading embedding model (~550 MB, one time)...';
        _setupProgress = 0;
        notifyListeners();
        await ModelFetch.fetch(
          '$_hfBase/tokenizer.json',
          File(p.join(dir.path, 'tokenizer.json')),
        );
        await ModelFetch.fetch(
          '$_hfBase/onnx/model.onnx',
          File(p.join(dir.path, 'model.onnx')),
          onProgress: (done, total) {
            if (total > 0) {
              _setupProgress = done / total;
              _setupStatus =
                  'Downloading embedding model... '
                  '${(done / (1024 * 1024)).round()} / '
                  '${(total / (1024 * 1024)).round()} MB';
              notifyListeners();
            }
          },
        );
        _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
        if (_files == null) {
          throw StateError('download finished but the model files failed '
              'verification');
        }
      }

      _setupStatus = 'Loading the model (first run takes a moment)...';
      _setupProgress = -1;
      notifyListeners();
      await checkAvailability();
      if (!_available) {
        // Surface the engine's actual failure — a bare "self-test failed"
        // gives the user (and us) nothing to act on.
        throw StateError(
          'the engine failed its self-test'
          '${_lastEngineError == null ? '' : ' — $_lastEngineError'}',
        );
      }
      _setupStatus = 'Memory is ready.';
      return true;
    } catch (e) {
      _setupError = '$e';
      _setupStatus = 'Setup failed.';
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'setup failed: $e',
      );
      return false;
    } finally {
      _settingUp = false;
      notifyListeners();
    }
  }

  /// Aborts setup from the dialog's Cancel: releases the (possibly
  /// half-warmed) session. A partial download is left as a .part file that
  /// the next attempt resumes past.
  void cancelSetup() {
    _native.shutdown();
  }

  /// Kicks availability in the background if embeddings aren't live yet —
  /// the sidebar toggle calls this when RAG turns on with consent already
  /// given.
  void ensureReady() {
    if (_available || _settingUp) return;
    unawaited(checkAvailability());
  }

  /// Loads the engine (if the model is on disk) and verifies it end to end
  /// with a real embed, which also warms the session so the first
  /// user-visible embed isn't the one paying the model load.
  Future<void> checkAvailability() async {
    debugPrint('[RAG:Embed] ── Checking embedding availability ──');

    _files = NativeEmbeddingEngine.resolveModelFiles(_storage.rootPath);
    if (_files == null) {
      _available = false;
      debugPrint(
        '[RAG:Embed] ⚠ No embedding model on disk — run RAG setup to '
        'download it',
      );
      notifyListeners();
      return;
    }

    try {
      final result = await _nativeEmbed('test');
      _dimensions = result.length;
      _available = true;
      _lastEngineError = null;
      debugPrint(
        '[RAG:Embed] ✅ In-process embeddings available '
        '(${_dimensions}d vectors)',
      );
    } catch (e) {
      _available = false;
      _lastEngineError = '$e';
      debugPrint('[RAG:Embed] ✗ In-process engine failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'engine self-test failed: $e',
      );
    }
    notifyListeners();
  }

  /// Generate an embedding vector for a text string.
  /// Returns null if embeddings are not available.
  Future<List<double>?> embed(String text) async {
    if (!_available || text.trim().isEmpty) return null;
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    final sw = Stopwatch()..start();

    try {
      final result = await _nativeEmbed(text);
      sw.stop();
      EngineHealth.instance.reportNative(EngineHealth.embeddings);
      debugPrint(
        '[RAG:Embed] ✅ ${result.length}d vector in ${sw.elapsedMilliseconds}ms ← "$preview"',
      );
      return result;
    } catch (e) {
      sw.stop();
      debugPrint(
        '[RAG:Embed] ✗ Embedding failed (${sw.elapsedMilliseconds}ms): $e',
      );
      EngineHealth.instance.reportFailure(
        EngineHealth.embeddings,
        'embed failed: $e',
      );
    }
    return null;
  }

  /// Batch embed multiple texts. Returns null entries for failures.
  Future<List<List<double>?>> embedBatch(List<String> texts) async {
    if (!_available) return List.filled(texts.length, null);

    final results = <List<double>?>[];
    for (final text in texts) {
      results.add(await embed(text));
    }
    return results;
  }

  Future<List<double>> _nativeEmbed(String text) => _native.embed(
    modelPath: _files!.model,
    vocabPath: _files!.vocab,
    text: text,
  );

  @override
  void dispose() {
    _native.shutdown();
    super.dispose();
  }
}
