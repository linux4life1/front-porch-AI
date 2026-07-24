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

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/expression/onnx_emotion_engine.dart'
    show OnnxEmotionEngine;
import 'package:front_porch_ai/services/expression/wordpiece_tokenizer.dart';
import 'package:front_porch_ai/services/onnx_runtime.dart';

/// In-process RAG embeddings: nomic-embed-text-v1.5 via onnxruntime, phase 5
/// of docs/design/sidecar-retirement.md (the last helper, the Rust
/// embed_server, becomes optional).
///
/// Pinned by cross-language goldens
/// (test/services/embedding/nomic_embedding_test.dart) to the EXACT vectors
/// the Rust server (fastembed 4) produced, captured live on 2026-07-18 —
/// stored embeddings in every user's memory database must keep comparing
/// correctly against vectors this engine produces, so the tokenize → run →
/// pool → normalize pipeline here must never drift from what fastembed did.
///
/// Recipe (verified against the goldens):
/// - prefix every input with `search_document: ` (the server did this for
///   both documents and queries — parity means we do too)
/// - BERT-uncased WordPiece ([CLS]/[SEP], lowercase + accent strip), same
///   tokenizer class the expression classifier already golden-verified,
///   truncated to fastembed's default 512 tokens
/// - ONNX forward pass → last_hidden_state, mean-pooled over tokens,
///   L2-normalized
///
/// One persistent worker isolate holds the loaded ~550MB session (model
/// load takes seconds — per-call sessions like the emotion engine uses
/// would be unusable here). [shutdown] releases it; the embedding service
/// calls that when setup is cancelled.
///
/// Model files: the fastembed hub cache the retired Rust server populated
/// is read as-is (zero re-download for existing users); fresh installs
/// download via [EmbeddingService.runSetup] into the app-managed dir.
class NativeEmbeddingEngine {
  /// Nomic task prefix — applied to every input, exactly like the retired
  /// server did.
  static const String taskPrefix = 'search_document: ';

  /// fastembed's default token budget (what the goldens were captured at).
  static const int maxTokens = 512;

  // ---- Model file resolution ----

  /// Locates `(model.onnx, tokenizer.json)` — the fastembed hub cache the
  /// Rust server populated (reused as-is, zero re-download for existing
  /// users), then the app-managed native download dir for fresh installs.
  /// The hub cache stores snapshot files as symlinks into blobs/, so every
  /// scan runs with followLinks:true (the lesson the expression classifier
  /// learned the hard way).
  static ({String model, String vocab})? resolveModelFiles(String? appRoot) {
    for (final cacheRoot in _fastembedCacheRoots()) {
      final repo = Directory(
        p.join(cacheRoot, 'models--nomic-ai--nomic-embed-text-v1.5'),
      );
      if (!repo.existsSync()) continue;
      final snapshots = Directory(p.join(repo.path, 'snapshots'));
      if (!snapshots.existsSync()) continue;
      try {
        for (final snap in snapshots.listSync(followLinks: true)) {
          if (snap is! Directory) continue;
          final model = File(p.join(snap.path, 'onnx', 'model.onnx'));
          final vocab = File(p.join(snap.path, 'tokenizer.json'));
          if (model.existsSync() &&
              vocab.existsSync() &&
              model.lengthSync() > 100 * 1024 * 1024) {
            return (model: model.path, vocab: vocab.path);
          }
        }
      } catch (_) {}
    }
    if (appRoot != null) {
      final dir = p.join(appRoot, 'models', 'embeddings', 'nomic-v1_5');
      final model = File(p.join(dir, 'model.onnx'));
      final vocab = File(p.join(dir, 'tokenizer.json'));
      if (model.existsSync() &&
          vocab.existsSync() &&
          model.lengthSync() > 100 * 1024 * 1024) {
        return (model: model.path, vocab: vocab.path);
      }
    }
    return null;
  }

  /// Where fastembed's `dirs::cache_dir()/front-porch-ai/embeddings` lands
  /// per platform (the Rust server's cache location, mirrored exactly).
  static List<String> _fastembedCacheRoots() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return [
      if (Platform.isMacOS && home.isNotEmpty)
        p.join(home, 'Library', 'Caches', 'front-porch-ai', 'embeddings'),
      if (Platform.isLinux)
        p.join(
          Platform.environment['XDG_CACHE_HOME'] ??
              (home.isEmpty ? '' : p.join(home, '.cache')),
          'front-porch-ai',
          'embeddings',
        ),
      if (Platform.isWindows &&
          (Platform.environment['LOCALAPPDATA'] ?? '').isNotEmpty)
        p.join(
          Platform.environment['LOCALAPPDATA']!,
          'front-porch-ai',
          'embeddings',
        ),
    ].where((e) => e.isNotEmpty).toList();
  }

  // ---- Persistent worker isolate (session loaded once) ----

  SendPort? _worker;
  String? _loadedModelPath;
  Future<void> _jobChain = Future.value();

  /// Embeds [text] (raw, unprefixed — the task prefix is added here).
  /// Returns the 768-dim normalized vector. Throws on failure — the caller
  /// owns the sidecar fallback and health reporting.
  Future<List<double>> embed({
    required String modelPath,
    required String vocabPath,
    required String text,
  }) {
    final result = _jobChain.then((_) async {
      if (_worker == null || _loadedModelPath != modelPath) {
        shutdown();
        _worker = await _spawn(modelPath, vocabPath);
        _loadedModelPath = modelPath;
      }
      final reply = ReceivePort();
      _worker!.send([reply.sendPort, taskPrefix + text]);
      final res = await reply.first;
      reply.close();
      if (res is String) throw StateError(res);
      return (res as Float64List).toList();
    });
    _jobChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Releases the worker (and with it the loaded session). Safe to call
  /// repeatedly; the next [embed] respawns.
  void shutdown() {
    _worker?.send(null);
    _worker = null;
    _loadedModelPath = null;
  }

  static Future<SendPort> _spawn(String modelPath, String vocabPath) async {
    final ready = ReceivePort();
    await Isolate.spawn(_workerMain, [ready.sendPort, modelPath, vocabPath]);
    final first = await ready.first;
    ready.close();
    if (first is String) throw StateError(first);
    return first as SendPort;
  }

  static void _workerMain(List<Object?> args) {
    final replyTo = args[0] as SendPort;
    final WordPieceTokenizer tokenizer;
    final OrtSession session;
    final bool wantsTokenTypes;
    try {
      tokenizer = WordPieceTokenizer(
        OnnxEmotionEngine.loadVocab(File(args[2] as String)),
      );
      // Outside a built app bundle (flutter test) the plugin's leaf-name
      // dlopen can't find libonnxruntime; FP_ORT_LIB pre-loads it by
      // absolute path so the leaf lookup hits the already-loaded image —
      // same pattern as FP_SHERPA_LIB for the sherpa engines.
      final ortLib = Platform.environment['FP_ORT_LIB'];
      if (ortLib != null && ortLib.isNotEmpty) {
        DynamicLibrary.open(ortLib);
      }
      OrtEnv.instance.init();
      final opts = OrtSessionOptions()
        ..setIntraOpNumThreads(
          math.max(1, Platform.numberOfProcessors ~/ 2),
        );
      session = ortSessionFromFile(File(args[1] as String), opts);
      opts.release();
      wantsTokenTypes = session.inputNames.contains('token_type_ids');
    } catch (e) {
      replyTo.send('embedding model load failed: $e');
      return;
    }
    final jobs = ReceivePort();
    replyTo.send(jobs.sendPort);
    jobs.listen((msg) {
      if (msg == null) {
        session.release();
        jobs.close();
        return;
      }
      final job = msg as List<Object?>;
      final reply = job[0] as SendPort;
      try {
        reply.send(
          _embedOne(session, tokenizer, wantsTokenTypes, job[1] as String),
        );
      } catch (e) {
        reply.send('embedding failed: $e');
      }
    });
  }

  static Float64List _embedOne(
    OrtSession session,
    WordPieceTokenizer tokenizer,
    bool wantsTokenTypes,
    String text,
  ) {
    final ids = tokenizer.encode(text, maxLength: maxTokens);
    final shape = [1, ids.length];
    final idsT = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(ids),
      shape,
    );
    final maskT = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(List.filled(ids.length, 1)),
      shape,
    );
    final typesT = wantsTokenTypes
        ? OrtValueTensor.createTensorWithDataList(
            Int64List(ids.length),
            shape,
          )
        : null;
    final ro = OrtRunOptions();
    List<OrtValue?>? outs;
    try {
      outs = session.run(ro, {
        'input_ids': idsT,
        'attention_mask': maskT,
        'token_type_ids': ?typesT,
      });
      // last_hidden_state [1, seq, 768] → mean over tokens → L2 normalize.
      // With a single unpadded sequence the attention-mask-weighted mean
      // fastembed computes reduces to a plain mean.
      final seq = (outs[0]!.value as List)[0] as List;
      final dims = (seq[0] as List).length;
      final pooled = Float64List(dims);
      for (final token in seq) {
        final row = token as List;
        for (var d = 0; d < dims; d++) {
          pooled[d] += (row[d] as num).toDouble();
        }
      }
      var norm = 0.0;
      for (var d = 0; d < dims; d++) {
        pooled[d] /= seq.length;
        norm += pooled[d] * pooled[d];
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        for (var d = 0; d < dims; d++) {
          pooled[d] /= norm;
        }
      }
      return pooled;
    } finally {
      if (outs != null) {
        for (final v in outs) {
          v?.release();
        }
      }
      idsT.release();
      maskT.release();
      typesT?.release();
      ro.release();
    }
  }
}
